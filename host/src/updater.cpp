// ii-shim update: ii-windows' updater (plan 2026-10-31, block B; docs/PLAN-2026-10-31/03-actualizaciones.md).
//
//   ii-shim update check     [--force]   ask GitHub's releases; a newer signed release -> state "available"
//   ii-shim update download  [--force]   the package of the available release, resumable, SHA-256 checked -> "downloaded"
//   ii-shim update install               verified payload copied next to the active version, current.txt "pending"
//                                        (the launcher starts it at the next start of ii and goes back if it fails) -> "ready"
//   ii-shim update status                prints the state
//   ii-shim update skip <version>        never offer that version again
//
// State: <data>\update\state.json (written atomically; the shell's Updates service and ii-host read it).
// ii-host runs these hidden, never during a game, a locked session or (for download) on a metered connection; "--force"
// is the user's own "Buscar ahora" / "Actualizar", which skips the metered-connection rule.
//
// Nothing runs and nothing is installed unless release.json carries a valid ECDSA P-256 signature by one of the two
// keys below (tools/package/sign-release.ps1) and every file matches the hashes it and the payload manifest give.
// Only HTTPS to GitHub's API and download hosts. Never a lower version than the one installed.
//
// Tests (tools/sandbox/tests/test-updater.ps1): II_UPDATE_API (release list URL), II_UPDATE_ROOT (install root),
// II_UPDATE_CURRENT (installed version id), II_HTTP_TEST_RESPONSES with --test (fixtures instead of the network),
// II_UPDATE_TEST_KEY (hex X||Y of an extra public key for test signatures; honoured only with II_DATA_DIR set).

#include <algorithm>
#include <cstdio>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <vector>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <bcrypt.h>
#include <shlobj.h>
#include <wincrypt.h>

// clang-format off
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Networking.Connectivity.h>
// clang-format on

#include "configtool.h"
#include "http.h"
#include "jsonlite.h"
#include "rollout.h"

namespace fs = std::filesystem;

namespace {

using Args = std::vector<std::wstring>;

// Release signing keys (sign-release.ps1 -NewKeys): X, Y of the P-256 public points.
struct PublicKey {
	unsigned char x[32];
	unsigned char y[32];
};
const PublicKey KEYS[] = {
    // current key
    {{0x99, 0x69, 0x4c, 0x0d, 0xfb, 0xbb, 0x60, 0xde, 0x5b, 0xe0, 0xb8, 0xdf, 0x79, 0xec, 0x8c, 0xfe, 0x32, 0x64, 0xb6, 0xf2, 0xa0, 0xad, 0x10, 0x0b, 0xb0, 0xcf, 0x49, 0x55, 0x05, 0xfc, 0x51, 0x73},
     {0x93, 0xdb, 0x01, 0xa3, 0x01, 0xde, 0xf7, 0x2b, 0x05, 0xbd, 0x04, 0x10, 0x88, 0x02, 0xdf, 0xbd, 0x6e, 0x25, 0xba, 0x0d, 0x17, 0x5c, 0xf4, 0xba, 0xe5, 0x22, 0xb2, 0xe7, 0x96, 0xb8, 0x5b, 0x4e}},
    // backup key
    {{0x72, 0xd5, 0x7e, 0xbb, 0x28, 0x20, 0xaf, 0x62, 0x58, 0x64, 0xed, 0x06, 0xfa, 0xbe, 0xc9, 0x04, 0xca, 0x3a, 0xf8, 0x9d, 0x3c, 0x18, 0x2d, 0x56, 0xf3, 0x57, 0x0a, 0x0d, 0x5c, 0x48, 0xfc, 0x06},
     {0x79, 0x99, 0x30, 0x4a, 0x8f, 0x63, 0x5a, 0xce, 0x1a, 0xab, 0xf8, 0xd2, 0x2a, 0xab, 0x9d, 0x31, 0x47, 0x0b, 0xc3, 0x03, 0x76, 0x96, 0xde, 0xfb, 0xa7, 0xae, 0x51, 0xc9, 0x72, 0x28, 0xef, 0x62}},
};

const wchar_t* RELEASES_API = L"https://api.github.com/repos/TheCarlosS5/ii-windows/releases?per_page=10";
const std::vector<std::wstring> HOSTS = {L"api.github.com", L"github.com", L"objects.githubusercontent.com", L"release-assets.githubusercontent.com"};

std::wstring env(const wchar_t* name) {
	wchar_t value[2048];
	auto n = GetEnvironmentVariableW(name, value, 2048);
	return n > 0 && n < 2048 ? std::wstring(value, n) : std::wstring();
}

std::string utf8(const std::wstring& text) {
	if (text.empty()) return {};
	auto n = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
	std::string out(static_cast<size_t>(n), '\0');
	WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), n, nullptr, nullptr);
	return out;
}

std::wstring wide(const std::string& text) {
	if (text.empty()) return {};
	auto n = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
	std::wstring out(static_cast<size_t>(n), L'\0');
	MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), n);
	return out;
}

std::wstring dataDir() {
	auto custom = env(L"II_DATA_DIR");
	if (!custom.empty()) return custom;
	PWSTR base = nullptr;
	std::wstring dir;
	if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &base))) dir = std::wstring(base) + L"\\ii-windows";
	CoTaskMemFree(base);
	return dir;
}

std::wstring updateDir() { return dataDir() + L"\\update"; }

std::string readFile(const std::wstring& path, size_t cap = 4 * 1024 * 1024) {
	std::ifstream f(fs::path(path), std::ios::binary);
	if (!f) return {};
	std::string text;
	char buffer[16384];
	while (f.read(buffer, sizeof(buffer)) || f.gcount() > 0) {
		text.append(buffer, static_cast<size_t>(f.gcount()));
		if (text.size() > cap) return {};
	}
	return text;
}

bool writeAtomic(const std::wstring& path, const std::string& bytes) {
	std::error_code ignored;
	fs::create_directories(fs::path(path).parent_path(), ignored);
	auto temp = path + L".tmp";
	{
		std::ofstream f(fs::path(temp), std::ios::binary | std::ios::trunc);
		if (!f) return false;
		f.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
		if (!f) return false;
	}
	return MoveFileExW(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
}

std::string text(const jsonlite::Value* v) { return v && v->type == jsonlite::Type::String ? v->text : std::string(); }
const jsonlite::Value* member(const jsonlite::Value& object, const char* key) { return object.isObject() ? object.find(key) : nullptr; }

std::string nowUtc() {
	SYSTEMTIME t;
	GetSystemTime(&t);
	char buffer[32];
	std::snprintf(buffer, sizeof(buffer), "%04d-%02d-%02dT%02d:%02d:%02dZ", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond);
	return buffer;
}

// --- state.json ------------------------------------------------------------------------------------------------------

jsonlite::Value loadState() {
	auto parsed = jsonlite::parse(readFile(updateDir() + L"\\state.json"));
	if (parsed.ok && parsed.value.isObject()) return parsed.value;
	auto v = jsonlite::Value::makeObject();
	v.set("schema", jsonlite::Value::makeNumber("1"));
	v.set("status", jsonlite::Value::makeString("idle"));
	return v;
}

void saveState(jsonlite::Value& state) {
	state.set("updated", jsonlite::Value::makeString(nowUtc()));
	writeAtomic(updateDir() + L"\\state.json", jsonlite::stringify(state, true));
}

void setStatus(jsonlite::Value& state, const char* status, const std::string& error = {}) {
	state.set("status", jsonlite::Value::makeString(status));
	if (error.empty()) state.erase("error");
	else state.set("error", jsonlite::Value::makeString(error));
	saveState(state);
	std::printf("%s%s%s\n", status, error.empty() ? "" : ": ", error.c_str());
}

// --- versions --------------------------------------------------------------------------------------------------------

struct Installed {
	std::wstring root; // <root>\versions\<id> layout, empty in a build tree
	std::wstring id;   // "0.6.1-20261102-abc1234" or "dev"
};

Installed installed() {
	Installed i;
	i.root = env(L"II_UPDATE_ROOT");
	i.id = env(L"II_UPDATE_CURRENT");
	if (i.root.empty() || i.id.empty()) {
		// <root>\versions\<id>\quickshell\bin\ii-shim.exe
		wchar_t self[MAX_PATH * 2];
		GetModuleFileNameW(nullptr, self, MAX_PATH * 2);
		auto dir = fs::path(self).parent_path().parent_path().parent_path(); // versions\<id>
		std::wstring root, id;
		if (ii::rollout::locate(dir.wstring(), root, id)) {
			if (i.root.empty()) i.root = root;
			if (i.id.empty()) i.id = id;
		}
	}
	if (i.id.empty()) i.id = L"dev";
	return i;
}

// "0.7.0" or "v0.7.0" or "0.7.0-20261108-abc" -> {0,7,0}; anything unreadable -> {0,0,0}.
std::vector<int> versionParts(std::string v) {
	if (!v.empty() && (v[0] == 'v' || v[0] == 'V')) v.erase(0, 1);
	v = v.substr(0, v.find('-'));
	std::vector<int> parts;
	size_t start = 0;
	while (parts.size() < 3) {
		auto end = v.find('.', start);
		auto piece = v.substr(start, end == std::string::npos ? std::string::npos : end - start);
		if (piece.empty() || piece.find_first_not_of("0123456789") != std::string::npos) return {0, 0, 0};
		parts.push_back(std::stoi(piece));
		if (end == std::string::npos) break;
		start = end + 1;
	}
	while (parts.size() < 3) parts.push_back(0);
	return parts;
}

int compareVersions(const std::string& a, const std::string& b) {
	auto x = versionParts(a), y = versionParts(b);
	return x < y ? -1 : x > y ? 1 : 0;
}

// --- crypto ----------------------------------------------------------------------------------------------------------

bool sha256(const void* data, size_t size, unsigned char out[32]) {
	return BCryptHash(BCRYPT_SHA256_ALG_HANDLE, nullptr, 0, static_cast<PUCHAR>(const_cast<void*>(data)), static_cast<ULONG>(size), out, 32) == 0;
}

std::string hex(const unsigned char* bytes, size_t n) {
	static const char* digits = "0123456789abcdef";
	std::string out;
	for (size_t i = 0; i < n; ++i) {
		out += digits[bytes[i] >> 4];
		out += digits[bytes[i] & 15];
	}
	return out;
}

std::string fileSha256(const std::wstring& path) {
	BCRYPT_HASH_HANDLE hash = nullptr;
	if (BCryptCreateHash(BCRYPT_SHA256_ALG_HANDLE, &hash, nullptr, 0, nullptr, 0, 0) != 0) return {};
	auto file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
	std::string result;
	if (file != INVALID_HANDLE_VALUE) {
		std::vector<unsigned char> buffer(1 << 20);
		DWORD read = 0;
		bool ok = true;
		while (ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr) && read > 0) {
			if (BCryptHashData(hash, buffer.data(), read, 0) != 0) {
				ok = false;
				break;
			}
		}
		CloseHandle(file);
		unsigned char digest[32];
		if (ok && BCryptFinishHash(hash, digest, 32, 0) == 0) result = hex(digest, 32);
	}
	BCryptDestroyHash(hash);
	return result;
}

std::vector<unsigned char> base64(const std::string& text) {
	DWORD size = 0;
	std::vector<unsigned char> out;
	if (!CryptStringToBinaryA(text.c_str(), static_cast<DWORD>(text.size()), CRYPT_STRING_BASE64, nullptr, &size, nullptr, nullptr)) return out;
	out.resize(size);
	if (!CryptStringToBinaryA(text.c_str(), static_cast<DWORD>(text.size()), CRYPT_STRING_BASE64, out.data(), &size, nullptr, nullptr)) out.clear();
	out.resize(size);
	return out;
}

bool verifyWith(const PublicKey& key, const std::string& data, const std::vector<unsigned char>& signature) {
	struct Blob {
		BCRYPT_ECCKEY_BLOB header;
		unsigned char x[32];
		unsigned char y[32];
	} blob {};
	blob.header.dwMagic = BCRYPT_ECDSA_PUBLIC_P256_MAGIC;
	blob.header.cbKey = 32;
	std::copy(std::begin(key.x), std::end(key.x), blob.x);
	std::copy(std::begin(key.y), std::end(key.y), blob.y);
	BCRYPT_KEY_HANDLE handle = nullptr;
	if (BCryptImportKeyPair(BCRYPT_ECDSA_P256_ALG_HANDLE, nullptr, BCRYPT_ECCPUBLIC_BLOB, &handle, reinterpret_cast<PUCHAR>(&blob), sizeof(blob), 0) != 0) return false;
	unsigned char digest[32];
	auto ok = sha256(data.data(), data.size(), digest)
	       && BCryptVerifySignature(handle, nullptr, digest, 32, const_cast<PUCHAR>(signature.data()), static_cast<ULONG>(signature.size()), 0) == 0;
	BCryptDestroyKey(handle);
	return ok;
}

bool verifySignature(const std::string& data, const std::string& signatureText) {
	auto signature = base64(signatureText);
	if (signature.size() != 64) return false;
	for (const auto& key: KEYS) {
		if (verifyWith(key, data, signature)) return true;
	}
	// Tests only (an isolated II_DATA_DIR): a throwaway key, so test releases need no real private key.
	auto testKey = env(L"II_UPDATE_TEST_KEY");
	if (!testKey.empty() && !env(L"II_DATA_DIR").empty() && testKey.size() == 128) {
		PublicKey key {};
		for (int i = 0; i < 64; ++i) {
			auto byte = static_cast<unsigned char>(std::stoi(utf8(testKey.substr(static_cast<size_t>(i) * 2, 2)), nullptr, 16));
			(i < 32 ? key.x[i] : key.y[i - 32]) = byte;
		}
		return verifyWith(key, data, signature);
	}
	return false;
}

// --- network ---------------------------------------------------------------------------------------------------------

bool testing = false;

bool meteredConnection() {
	if (testing) return env(L"II_UPDATE_TEST_METERED") == L"1";
	try {
		using namespace winrt::Windows::Networking::Connectivity;
		auto profile = NetworkInformation::GetInternetConnectionProfile();
		if (!profile) return false;
		auto cost = profile.GetConnectionCost();
		if (!cost) return false;
		return cost.Roaming() || cost.OverDataLimit() || cost.NetworkCostType() == NetworkCostType::Fixed
		    || cost.NetworkCostType() == NetworkCostType::Variable;
	} catch (...) {
		return false;
	}
}

std::unique_ptr<http::Client> makeClient() {
	auto client = std::make_unique<http::Client>(L"ii-windows-updater/" + installed().id, testing);
	if (!testing) client->allowHosts(HOSTS);
	return client;
}

std::wstring channelFromConfig() {
	auto parsed = jsonlite::parse(readFile(configtool::paths().file));
	if (parsed.ok) {
		const auto* updates = member(parsed.value, "iiUpdates");
		auto channel = updates ? text(member(*updates, "channel")) : std::string();
		if (channel == "beta") return L"beta";
	}
	return L"stable";
}

std::set<std::string> skipped(const jsonlite::Value& state) {
	std::set<std::string> out;
	if (const auto* list = member(state, "skipped"); list && list->type == jsonlite::Type::Array) {
		for (const auto& v: list->items) out.insert(text(&v));
	}
	return out;
}

// --- check -----------------------------------------------------------------------------------------------------------

int check(bool force) {
	auto state = loadState();
	auto current = installed();
	state.set("current", jsonlite::Value::makeString(utf8(current.id)));
	auto channel = channelFromConfig();
	state.set("channel", jsonlite::Value::makeString(utf8(channel)));
	setStatus(state, "checking");
	(void) force;

	auto api = env(L"II_UPDATE_API");
	if (api.empty()) api = RELEASES_API;
	auto client = makeClient();
	std::vector<std::wstring> headers = {L"Accept: application/vnd.github+json", L"X-GitHub-Api-Version: 2022-11-28"};
	auto etag = wide(text(member(state, "etag")));
	auto cachePath = updateDir() + L"\\releases.json";
	if (!etag.empty() && GetFileAttributesW(cachePath.c_str()) != INVALID_FILE_ATTRIBUTES) headers.push_back(L"If-None-Match: " + etag);
	auto reply = client->request(api, headers, 4 * 1024 * 1024);
	std::string body;
	if (reply.status == 304) {
		body = readFile(cachePath);
	} else if (reply.status == 403 || reply.status == 429) {
		auto wait = reply.retryAfter.empty() ? std::string("3600") : utf8(reply.retryAfter);
		state.set("retryAfterSeconds", jsonlite::Value::makeNumber(wait.find_first_not_of("0123456789") == std::string::npos ? wait : "3600"));
		setStatus(state, "error", "GitHub limit reached; trying again later");
		return 1;
	} else if (reply.status != 200) {
		setStatus(state, "error", "GitHub answered " + std::to_string(reply.status));
		return 1;
	} else {
		body = reply.body;
		writeAtomic(cachePath, body);
		if (!reply.etag.empty()) state.set("etag", jsonlite::Value::makeString(utf8(reply.etag)));
	}
	state.set("lastCheck", jsonlite::Value::makeString(nowUtc()));

	auto releases = jsonlite::parse(body);
	if (!releases.ok || releases.value.type != jsonlite::Type::Array) {
		setStatus(state, "error", "unreadable release list");
		return 1;
	}
	auto skip = skipped(state);
	auto currentBase = utf8(current.id);
	for (const auto& release: releases.value.items) {
		const auto* draft = member(release, "draft");
		if (draft && draft->type == jsonlite::Type::Bool && draft->boolean) continue;
		const auto* pre = member(release, "prerelease");
		auto prerelease = pre && pre->type == jsonlite::Type::Bool && pre->boolean;
		if (prerelease && channel != L"beta") continue;
		std::string manifestUrl, signatureUrl;
		std::map<std::string, std::pair<std::string, double>> assets; // name -> url, size
		if (const auto* list = member(release, "assets"); list && list->type == jsonlite::Type::Array) {
			for (const auto& asset: list->items) {
				auto name = text(member(asset, "name"));
				auto url = text(member(asset, "browser_download_url"));
				const auto* size = member(asset, "size");
				assets[name] = {url, size && size->type == jsonlite::Type::Number ? size->asDouble() : 0};
				if (name.size() >= 12 && name.compare(name.size() - 12, 12, "release.json") == 0) manifestUrl = url;
				if (name.size() >= 16 && name.compare(name.size() - 16, 16, "release.json.sig") == 0) signatureUrl = url;
			}
		}
		if (manifestUrl.empty() || signatureUrl.empty()) continue; // a release from before the updater (or a broken one)
		auto tag = text(member(release, "tag_name"));
		// Newer than what is installed? (A build tree "dev" is offered nothing unless told its version.)
		if (currentBase == "dev" || compareVersions(tag, currentBase) <= 0) break; // releases come newest first
		auto manifest = client->request(wide(manifestUrl), {}, 512 * 1024);
		auto signature = client->request(wide(signatureUrl), {}, 4096);
		if (manifest.status != 200 || signature.status != 200) {
			setStatus(state, "error", "release.json of " + tag + " could not be downloaded");
			return 1;
		}
		if (!verifySignature(manifest.body, signature.body)) {
			setStatus(state, "error", "release.json of " + tag + " has no valid signature: ignored");
			return 1;
		}
		auto info = jsonlite::parse(manifest.body);
		if (!info.ok || !info.value.isObject()) {
			setStatus(state, "error", "unreadable release.json of " + tag);
			return 1;
		}
		auto version = text(member(info.value, "version"));
		auto id = text(member(info.value, "id"));
		if (compareVersions(version, currentBase) <= 0 || !ii::rollout::validId(wide(id))) break;
		if (skip.count(version)) {
			setStatus(state, "idle");
			std::printf("%s was skipped by the user\n", version.c_str());
			return 0;
		}
		auto minFrom = text(member(info.value, "minFrom"));
		const auto* package = member(info.value, "package");
		auto packageName = package ? text(member(*package, "name")) : std::string();
		auto packageSha = package ? text(member(*package, "sha256")) : std::string();
		const auto* packageSize = package ? member(*package, "size") : nullptr;
		if (packageName.empty() || packageSha.size() != 64 || !assets.count(packageName)) {
			setStatus(state, "error", "release " + tag + " has no package");
			return 1;
		}
		writeAtomic(updateDir() + L"\\" + wide(id) + L"\\release.json", manifest.body);
		auto latest = jsonlite::Value::makeObject();
		latest.set("version", jsonlite::Value::makeString(version));
		latest.set("id", jsonlite::Value::makeString(id));
		latest.set("tag", jsonlite::Value::makeString(tag));
		latest.set("prerelease", jsonlite::Value::makeBool(prerelease));
		latest.set("publishedAt", jsonlite::Value::makeString(text(member(release, "published_at"))));
		latest.set("url", jsonlite::Value::makeString(text(member(release, "html_url"))));
		latest.set("packageUrl", jsonlite::Value::makeString(assets[packageName].first));
		latest.set("packageName", jsonlite::Value::makeString(packageName));
		latest.set("sha256", jsonlite::Value::makeString(packageSha));
		latest.set("size", packageSize && packageSize->type == jsonlite::Type::Number ? *packageSize : jsonlite::Value::makeNumber("0"));
		const auto* critical = member(info.value, "critical");
		latest.set("critical", jsonlite::Value::makeBool(critical && critical->type == jsonlite::Type::Bool && critical->boolean));
		const auto* needs = member(info.value, "needsInstaller");
		latest.set("needsInstaller", jsonlite::Value::makeBool(needs && needs->type == jsonlite::Type::Bool && needs->boolean));
		const auto* notes = member(info.value, "notes");
		latest.set("notes", jsonlite::Value::makeString(notes ? text(member(*notes, "es")) : std::string()));
		latest.set("tooOld", jsonlite::Value::makeBool(!minFrom.empty() && compareVersions(currentBase, minFrom) < 0));
		auto previous = member(state, "latest") ? text(member(*member(state, "latest"), "id")) : std::string();
		state.set("latest", latest);
		auto downloaded = GetFileAttributesW((updateDir() + L"\\" + wide(id) + L"\\" + wide(packageName)).c_str()) != INVALID_FILE_ATTRIBUTES;
		auto status = text(member(state, "status"));
		(void) status;
		auto wasReady = previous == id && text(member(state, "readyId")) == id;
		setStatus(state, wasReady ? "ready" : downloaded ? "downloaded" : "available");
		std::printf("latest %s (%s)\n", version.c_str(), id.c_str());
		return 0;
	}
	state.erase("latest");
	setStatus(state, "idle");
	return 0;
}

// --- download --------------------------------------------------------------------------------------------------------

int download(bool force) {
	auto state = loadState();
	const auto* latest = member(state, "latest");
	if (!latest) {
		setStatus(state, "idle");
		return 1;
	}
	if (!force && meteredConnection()) {
		setStatus(state, "waiting-network", "metered connection: the download waits for Wi-Fi or cable");
		return 3;
	}
	auto id = wide(text(member(*latest, "id")));
	auto name = wide(text(member(*latest, "packageName")));
	auto sha = text(member(*latest, "sha256"));
	const auto* sizeValue = member(*latest, "size");
	auto size = sizeValue ? static_cast<unsigned long long>(sizeValue->asDouble()) : 0ULL;
	auto dir = updateDir() + L"\\" + id;
	std::error_code ignored;
	fs::create_directories(dir, ignored);
	auto finalPath = dir + L"\\" + name;
	if (GetFileAttributesW(finalPath.c_str()) != INVALID_FILE_ATTRIBUTES && fileSha256(finalPath) == sha) {
		setStatus(state, "downloaded");
		return 0;
	}
	// Space for the zip, its extraction and the installed copy.
	ULARGE_INTEGER free {};
	if (size && GetDiskFreeSpaceExW(dataDir().c_str(), &free, nullptr, nullptr) && free.QuadPart < size * 4) {
		setStatus(state, "error", "not enough disk space: " + std::to_string(size * 4 / (1024 * 1024)) + " MB needed");
		return 1;
	}
	state.set("status", jsonlite::Value::makeString("downloading"));
	auto client = makeClient();
	auto part = finalPath + L".part";
	try {
		client->download(wide(text(member(*latest, "packageUrl"))), part, size, [&](unsigned long long done, unsigned long long total) {
			auto progress = jsonlite::Value::makeObject();
			progress.set("bytes", jsonlite::Value::makeNumber(std::to_string(done)));
			progress.set("total", jsonlite::Value::makeNumber(std::to_string(total)));
			state.set("progress", progress);
			saveState(state);
			return true;
		});
	} catch (const std::exception& e) {
		setStatus(state, "error", std::string("download stopped: ") + e.what() + " (it resumes next time)");
		return 1;
	}
	setStatus(state, "verifying");
	if (fileSha256(part) != sha) {
		DeleteFileW(part.c_str());
		setStatus(state, "error", "the download arrived damaged (SHA-256); it will be downloaded again");
		return 1;
	}
	MoveFileExW(part.c_str(), finalPath.c_str(), MOVEFILE_REPLACE_EXISTING);
	state.erase("progress");
	setStatus(state, "downloaded");
	return 0;
}

// --- install ---------------------------------------------------------------------------------------------------------

bool run(std::wstring command, const std::wstring& dir, DWORD timeoutMs, DWORD& code) {
	STARTUPINFOW si {};
	si.cb = sizeof(si);
	PROCESS_INFORMATION pi {};
	if (!CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, dir.empty() ? nullptr : dir.c_str(), &si, &pi)) return false;
	CloseHandle(pi.hThread);
	auto finished = WaitForSingleObject(pi.hProcess, timeoutMs) == WAIT_OBJECT_0;
	if (!finished) TerminateProcess(pi.hProcess, 1);
	GetExitCodeProcess(pi.hProcess, &code);
	CloseHandle(pi.hProcess);
	return finished;
}

std::wstring relativePath(const fs::path& base, const fs::path& file) { return fs::relative(file, base).wstring(); }

// The payload is exactly what its manifest says (Test-IiPayload in ii-runtime.ps1, natively).
std::string checkPayload(const std::wstring& dir) {
	auto manifestText = readFile(dir + L"\\payload.manifest", 16 * 1024 * 1024);
	if (manifestText.empty()) return "payload.manifest is missing";
	std::map<std::wstring, std::string> expected;
	size_t start = 0;
	while (start < manifestText.size()) {
		auto end = manifestText.find('\n', start);
		auto line = manifestText.substr(start, end == std::string::npos ? std::string::npos : end - start);
		start = end == std::string::npos ? manifestText.size() : end + 1;
		while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) line.pop_back();
		if (line.empty()) continue;
		if (line.size() < 67 || line.compare(64, 2, "  ") != 0) return "unreadable manifest line";
		auto hash = line.substr(0, 64);
		std::transform(hash.begin(), hash.end(), hash.begin(), [](char c) { return static_cast<char>(std::tolower(static_cast<unsigned char>(c))); });
		expected[wide(line.substr(66))] = hash;
	}
	for (const wchar_t* required: {L"ii-host.exe", L"quickshell\\quickshell.exe", L"ii\\shell.qml", L"VERSION"}) {
		if (!expected.count(required)) return "required file not in the manifest: " + utf8(required);
	}
	for (const auto& [rel, hash]: expected) {
		if (fileSha256(dir + L"\\" + rel) != hash) return "missing or different: " + utf8(rel);
	}
	std::error_code error;
	for (const auto& entry: fs::recursive_directory_iterator(dir, error)) {
		if (!entry.is_regular_file()) continue;
		auto rel = relativePath(dir, entry.path());
		if (rel != L"payload.manifest" && !expected.count(rel)) return "not in the manifest: " + utf8(rel);
	}
	return {};
}

bool copyTree(const std::wstring& from, const std::wstring& to) {
	std::error_code error;
	fs::create_directories(to, error);
	for (const auto& entry: fs::recursive_directory_iterator(from, error)) {
		auto target = fs::path(to) / fs::relative(entry.path(), from);
		if (entry.is_directory()) {
			fs::create_directories(target, error);
		} else if (entry.is_regular_file()) {
			fs::create_directories(target.parent_path(), error);
			if (!CopyFileW(entry.path().c_str(), target.c_str(), FALSE)) return false;
		}
	}
	return !error;
}

void writeJournal(const std::wstring& root, const std::wstring& txn, const char* step, const std::wstring& to, const std::wstring& staging) {
	auto content = "txn=" + utf8(txn) + "\r\nstep=" + step + "\r\nto=" + utf8(to) + "\r\nstaging=" + utf8(staging) + "\r\n";
	writeAtomic(root + L"\\journal.txt", content);
}

int install() {
	auto state = loadState();
	const auto* latest = member(state, "latest");
	if (!latest) {
		setStatus(state, "idle");
		return 1;
	}
	auto current = installed();
	if (current.root.empty()) {
		setStatus(state, "error", "this copy of ii is not an installation (a build tree): nothing to install into");
		return 1;
	}
	auto id = wide(text(member(*latest, "id")));
	auto name = wide(text(member(*latest, "packageName")));
	auto sha = text(member(*latest, "sha256"));
	auto dir = updateDir() + L"\\" + id;
	auto zip = dir + L"\\" + name;
	if (GetFileAttributesW(zip.c_str()) == INVALID_FILE_ATTRIBUTES) {
		setStatus(state, "available", "download first");
		return 1;
	}
	setStatus(state, "installing");
	if (fileSha256(zip) != sha) {
		DeleteFileW(zip.c_str());
		setStatus(state, "available", "the downloaded package does not match its hash; it will be downloaded again");
		return 1;
	}
	// Extracted with Windows' own tar.exe (bsdtar, in every Windows 10 1803+ / 11), into a fresh folder.
	auto pkg = dir + L"\\pkg";
	std::error_code ignored;
	fs::remove_all(pkg, ignored);
	fs::create_directories(pkg, ignored);
	wchar_t system[MAX_PATH];
	GetSystemDirectoryW(system, MAX_PATH);
	DWORD code = 1;
	if (!run(L"\"" + std::wstring(system) + L"\\tar.exe\" -xf \"" + zip + L"\" -C \"" + pkg + L"\"", L"", 300000, code) || code != 0) {
		setStatus(state, "error", "the package could not be extracted (tar " + std::to_string(code) + ")");
		return 1;
	}
	fs::path packageRoot;
	for (const auto& entry: fs::directory_iterator(pkg, ignored)) {
		if (entry.is_directory() && fs::exists(entry.path() / L"app" / L"payload.manifest")) packageRoot = entry.path();
	}
	if (packageRoot.empty()) {
		setStatus(state, "error", "the package has no app\\payload.manifest");
		return 1;
	}
	auto payload = (packageRoot / L"app").wstring();
	auto problem = checkPayload(payload);
	if (!problem.empty()) {
		setStatus(state, "error", "the package does not match its manifest: " + problem);
		return 1;
	}
	auto version = readFile(payload + L"\\VERSION");
	version = version.substr(0, version.find_first_of("\r\n "));
	if (wide(version) != id) {
		setStatus(state, "error", "the package is version " + version + ", not " + utf8(id));
		return 1;
	}

	const auto* needs = member(*latest, "needsInstaller");
	if (needs && needs->type == jsonlite::Type::Bool && needs->boolean) {
		// This version changes what only the full installer does (shortcuts, the logon task...): its own install.ps1,
		// silent, keeping the logon task as it is.
		SetEnvironmentVariableW(L"PSModulePath", nullptr); // Windows PowerShell 5.1 under a pwsh 7 parent (setup.iss)
		auto command = L"powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"" + (packageRoot / L"install.ps1").wstring() + L"\" -Yes -NoAutostart";
		if (!run(command, packageRoot.wstring(), 600000, code) || code != 0) {
			setStatus(state, "error", "the installer of the new version failed (" + std::to_string(code) + ")");
			return 1;
		}
	} else {
		// Install-IiRuntime, natively: staging next to the active version, verified, one rename, then the pointer.
		auto versions = current.root + L"\\versions";
		fs::create_directories(versions, ignored);
		auto finalDir = versions + L"\\" + id;
		auto txn = std::to_wstring(GetTickCount64() % 100000000);
		auto staging = finalDir + L".staging-" + txn;
		auto reuse = fs::exists(finalDir) && checkPayload(finalDir).empty();
		if (fs::exists(finalDir) && !reuse) {
			int n = 2;
			while (fs::exists(versions + L"\\" + id + L"-" + std::to_wstring(n))) ++n;
			id = id + L"-" + std::to_wstring(n);
			finalDir = versions + L"\\" + id;
			staging = finalDir + L".staging-" + txn;
		}
		if (!reuse) {
			writeJournal(current.root, txn, "copying", id, staging);
			if (!copyTree(payload, staging) || !checkPayload(staging).empty()) {
				fs::remove_all(staging, ignored);
				writeJournal(current.root, txn, "aborted", id, L"");
				setStatus(state, "error", "the copy of the new version failed (disk full?)");
				return 1;
			}
			writeJournal(current.root, txn, "staged", id, staging);
			if (!MoveFileExW(staging.c_str(), finalDir.c_str(), 0)) {
				fs::remove_all(staging, ignored);
				writeJournal(current.root, txn, "aborted", id, L"");
				setStatus(state, "error", "the new version could not be put in place");
				return 1;
			}
			writeJournal(current.root, txn, "renamed", id, L"");
		}
		ii::rollout::Current pointer;
		auto known = ii::rollout::read(current.root, pointer);
		ii::rollout::Current next;
		next.present = true;
		next.active = id;
		next.previous = known ? (pointer.active == id ? pointer.previous : pointer.active) : L"none";
		next.state = L"pending";
		next.attempts = 0;
		if (!ii::rollout::write(current.root, next)) {
			setStatus(state, "error", "current.txt could not be written");
			return 1;
		}
		DeleteFileW((current.root + L"\\journal.txt").c_str());
		// A newer launcher (the stable entry point) goes next to the versions, replaced atomically.
		auto launcher = (packageRoot / L"ii-launcher.exe").wstring();
		auto installedLauncher = current.root + L"\\ii-launcher.exe";
		if (fs::exists(launcher) && fileSha256(launcher) != fileSha256(installedLauncher)) {
			auto temp = installedLauncher + L".new";
			if (CopyFileW(launcher.c_str(), temp.c_str(), FALSE)) MoveFileExW(temp.c_str(), installedLauncher.c_str(), MOVEFILE_REPLACE_EXISTING);
		}
	}
	fs::remove_all(pkg, ignored);
	state.set("readyId", jsonlite::Value::makeString(utf8(id)));
	setStatus(state, "ready");
	return 0;
}

} // namespace

int update(const std::vector<std::wstring>& argsIn) {
	Args args(argsIn.begin(), argsIn.end());
	testing = std::find(args.begin(), args.end(), L"--test") != args.end();
	auto force = std::find(args.begin(), args.end(), L"--force") != args.end();
	if (args.empty()) {
		std::fputs("usage: update check|download|install|status|skip <version> [--force] [--test]\n", stderr);
		return 2;
	}
	winrt::init_apartment(winrt::apartment_type::single_threaded);
	try {
		if (args[0] == L"check") return check(force);
		if (args[0] == L"download") return download(force);
		if (args[0] == L"install") return install();
		if (args[0] == L"status") {
			auto state = loadState();
			std::puts(jsonlite::stringify(state, true).c_str());
			return 0;
		}
		if (args[0] == L"skip" && args.size() >= 2) {
			auto state = loadState();
			auto list = member(state, "skipped") ? *member(state, "skipped") : jsonlite::Value::makeArray();
			if (list.type != jsonlite::Type::Array) list = jsonlite::Value::makeArray();
			list.items.push_back(jsonlite::Value::makeString(utf8(args[1])));
			state.set("skipped", list);
			state.erase("latest");
			setStatus(state, "idle");
			return 0;
		}
	} catch (const std::exception& e) {
		auto state = loadState();
		setStatus(state, "error", e.what());
		return 1;
	} catch (const winrt::hresult_error& e) {
		auto state = loadState();
		setStatus(state, "error", utf8(std::wstring(e.message())));
		return 1;
	}
	return 2;
}
