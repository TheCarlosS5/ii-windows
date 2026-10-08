// randomwall: ii's Konachan and osu! random wallpaper scripts, without bash/curl/jq.
//   randomwall konachan|osu [--no-apply] [--out <dir>]

#include <algorithm>
#include <cstdio>
#include <cwctype>
#include <memory>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <shlobj.h>
#include <winhttp.h>

// clang-format off
#include <winrt/base.h>
#include <winrt/Windows.Data.Json.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
// clang-format on

int switchwall(const std::vector<std::wstring>& args);

using Args = std::vector<std::wstring>;
namespace json = winrt::Windows::Data::Json;

namespace {

constexpr size_t IMAGE_LIMIT = 40 * 1024 * 1024;
constexpr size_t JSON_LIMIT = 1024 * 1024;

struct InternetClose {
	void operator()(void* handle) const { WinHttpCloseHandle(handle); }
};
using Internet = std::unique_ptr<void, InternetClose>;

struct FileClose {
	void operator()(void* handle) const { CloseHandle(handle); }
};
using File = std::unique_ptr<void, FileClose>;

struct Apartment {
	Apartment() { winrt::init_apartment(winrt::apartment_type::single_threaded); }
	~Apartment() { winrt::uninit_apartment(); }
};

void require(bool ok, const char* reason) {
	if (!ok) throw std::runtime_error(reason);
}

void httpRequire(bool ok, const char* reason) {
	if (!ok) throw std::runtime_error(std::string(reason) + " (WinHTTP " + std::to_string(GetLastError()) + ")");
}

std::wstring env(const wchar_t* name) {
	auto size = GetEnvironmentVariableW(name, nullptr, 0);
	if (!size) return {};
	std::wstring value(size, L'\0');
	auto count = GetEnvironmentVariableW(name, value.data(), size);
	if (!count || count >= size) return {};
	value.resize(count);
	return value;
}

void progress(const std::wstring& line) {
	std::printf("%s\n", winrt::to_string(line).c_str());
	std::fflush(stdout);
}

std::wstring folder(REFKNOWNFOLDERID id) {
	PWSTR path = nullptr;
	auto result = SHGetKnownFolderPath(id, 0, nullptr, &path);
	std::wstring value = path ? path : L"";
	CoTaskMemFree(path);
	require(SUCCEEDED(result) && !value.empty(), "cannot locate Windows known folder");
	return value;
}

std::string readBytes(const std::wstring& path, size_t cap, bool optional = false) {
	auto handle = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
	                          nullptr, OPEN_EXISTING, 0, nullptr);
	if (handle == INVALID_HANDLE_VALUE && optional) return {};
	require(handle != INVALID_HANDLE_VALUE, "cannot read fixture/config file");
	File file(handle);
	LARGE_INTEGER size {};
	require(GetFileSizeEx(file.get(), &size) != 0 && size.QuadPart >= 0
	        && size.QuadPart <= static_cast<LONGLONG>(cap), "file exceeds size limit");
	std::string bytes(static_cast<size_t>(size.QuadPart), '\0');
	DWORD read = 0;
	require(ReadFile(file.get(), bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr) != 0
	        && read == bytes.size(), "cannot read fixture/config file");
	return bytes;
}

std::string readUtf8(const std::wstring& path, bool optional = false) {
	auto bytes = readBytes(path, JSON_LIMIT, optional);
	if (bytes.rfind("\xEF\xBB\xBF", 0) == 0) bytes.erase(0, 3);
	return bytes;
}

json::JsonObject existing(const json::JsonObject& parent, const wchar_t* name) {
	if (parent.HasKey(name) && parent.GetNamedValue(name).ValueType() == json::JsonValueType::Object) {
		return parent.GetNamedObject(name);
	}
	return json::JsonObject();
}

std::wstring getString(const json::JsonObject& parent, const wchar_t* name) {
	if (!parent.HasKey(name) || parent.GetNamedValue(name).ValueType() != json::JsonValueType::String) return {};
	return std::wstring(parent.GetNamedString(name));
}

std::wstring fullPath(std::wstring path) {
	if (path.rfind(L"file:///", 0) == 0) path.erase(0, 8);
	for (auto& c: path) {
		if (c == L'/') c = L'\\';
	}
	if (path.size() > 3 && path[0] == L'\\' && path[2] == L':') path.erase(0, 1);
	auto size = GetFullPathNameW(path.c_str(), 0, nullptr, nullptr);
	require(size != 0, "invalid output path");
	std::wstring result(size, L'\0');
	auto count = GetFullPathNameW(path.c_str(), size, result.data(), nullptr);
	require(count != 0 && count < size, "invalid output path");
	result.resize(count);
	return result;
}

struct Url {
	std::wstring host;
	std::wstring target;
	std::wstring path;
	INTERNET_PORT port;
};

Url parseUrl(const std::wstring& text) {
	require(text.find_first_of(L"\r\n\\") == std::wstring::npos, "invalid HTTPS URL");
	URL_COMPONENTS parts {};
	parts.dwStructSize = sizeof(parts);
	parts.dwHostNameLength = parts.dwUrlPathLength = parts.dwExtraInfoLength = static_cast<DWORD>(-1);
	parts.dwUserNameLength = parts.dwPasswordLength = static_cast<DWORD>(-1);
	require(WinHttpCrackUrl(text.c_str(), 0, 0, &parts) != 0, "invalid HTTPS URL");
	require(parts.nScheme == INTERNET_SCHEME_HTTPS, "only HTTPS URLs are allowed");
	require(parts.dwHostNameLength != 0 && parts.dwUserNameLength == 0 && parts.dwPasswordLength == 0,
	        "invalid HTTPS URL");
	Url url;
	url.host.assign(parts.lpszHostName, parts.dwHostNameLength);
	if (parts.dwUrlPathLength) url.path.assign(parts.lpszUrlPath, parts.dwUrlPathLength);
	url.target = url.path.empty() ? L"/" : url.path;
	if (parts.dwExtraInfoLength) url.target.append(parts.lpszExtraInfo, parts.dwExtraInfoLength);
	auto fragment = url.target.find(L'#');
	if (fragment != std::wstring::npos) url.target.resize(fragment);
	url.port = parts.nPort;
	return url;
}

std::wstring imageExtension(const std::wstring& url) {
	auto path = parseUrl(url).path;
	auto dot = path.find_last_of(L'.');
	std::wstring ext = dot == std::wstring::npos ? L"" : path.substr(dot + 1);
	for (auto& c: ext) c = static_cast<wchar_t>(std::towlower(c));
	require(ext == L"jpg" || ext == L"jpeg" || ext == L"png" || ext == L"webp" || ext == L"gif" || ext == L"bmp",
	        "URL has no supported image extension");
	return ext;
}

std::wstring header(HINTERNET request, DWORD name) {
	DWORD size = 0;
	if (!WinHttpQueryHeaders(request, name, WINHTTP_HEADER_NAME_BY_INDEX, nullptr, &size, WINHTTP_NO_HEADER_INDEX)) {
		if (GetLastError() == ERROR_WINHTTP_HEADER_NOT_FOUND) return {};
		require(GetLastError() == ERROR_INSUFFICIENT_BUFFER, "cannot read HTTP headers");
	}
	std::wstring value(size / sizeof(wchar_t), L'\0');
	require(WinHttpQueryHeaders(request, name, WINHTTP_HEADER_NAME_BY_INDEX, value.data(), &size, WINHTTP_NO_HEADER_INDEX) != 0,
	        "cannot read HTTP headers");
	while (!value.empty() && value.back() == L'\0') value.pop_back();
	return value;
}

struct Http {
	Internet session;

	explicit Http(const std::wstring& agent): session(WinHttpOpen(agent.c_str(), WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
	                                                          WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0)) {
		require(session != nullptr, "cannot open WinHTTP session");
		require(WinHttpSetTimeouts(session.get(), 20000, 20000, 20000, 20000) != 0, "cannot set HTTP timeouts");
	}

	std::string get(std::wstring url, size_t cap) {
		auto started = GetTickCount64();
		for (int redirects = 0; redirects <= 5; ++redirects) {
			auto parts = parseUrl(url);
			Internet connection(WinHttpConnect(session.get(), parts.host.c_str(), parts.port, 0));
			require(connection != nullptr, "HTTP connection failed");
			Internet request(WinHttpOpenRequest(connection.get(), L"GET", parts.target.c_str(), nullptr,
			                                    WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE));
			require(request != nullptr, "cannot create HTTP request");
			// Resolve redirects ourselves, checking HTTPS at every hop, including signed download URLs.
			DWORD policy = WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
			require(WinHttpSetOption(request.get(), WINHTTP_OPTION_REDIRECT_POLICY, &policy, sizeof(policy)) != 0,
			        "cannot set redirect policy");
			httpRequire(WinHttpSendRequest(request.get(), WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0) != 0
			        && WinHttpReceiveResponse(request.get(), nullptr) != 0, "HTTP request failed");
			DWORD status = 0, size = sizeof(status);
			require(WinHttpQueryHeaders(request.get(), WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
			                           WINHTTP_HEADER_NAME_BY_INDEX, &status, &size, WINHTTP_NO_HEADER_INDEX) != 0,
			        "cannot read HTTP status");
			if (status == 301 || status == 302 || status == 303 || status == 307 || status == 308) {
				auto location = header(request.get(), WINHTTP_QUERY_LOCATION);
				require(!location.empty(), "HTTP redirect has no location");
				url = winrt::Windows::Foundation::Uri(url).CombineUri(location).AbsoluteUri();
				require(GetTickCount64() - started < 60000, "HTTP request timed out");
				continue;
			}
			require(status >= 200 && status < 300, ("HTTP status " + std::to_string(status)).c_str());
			auto length = header(request.get(), WINHTTP_QUERY_CONTENT_LENGTH);
			size_t expected = 0;
			if (!length.empty()) {
				require(length.find_first_not_of(L"0123456789") == std::wstring::npos, "invalid HTTP content length");
				auto count = _wcstoui64(length.c_str(), nullptr, 10);
				require(count <= cap, "download exceeds size limit");
				expected = static_cast<size_t>(count);
			}
			std::string bytes;
			char buffer[64 * 1024];
			for (;;) {
				require(GetTickCount64() - started < 60000, "HTTP request timed out");
				DWORD read = 0;
				httpRequire(WinHttpReadData(request.get(), buffer, sizeof(buffer), &read) != 0, "HTTP download failed");
				if (!read) break;
				require(read <= cap - bytes.size(), "download exceeds size limit");
				bytes.append(buffer, read);
			}
			require(length.empty() || bytes.size() == expected, "incomplete HTTP download");
			require(!bytes.empty(), "empty HTTP response");
			return bytes;
		}
		throw std::runtime_error("too many HTTP redirects");
	}
};

size_t randomIndex(size_t count) {
	std::random_device random;
	std::mt19937 generator(random());
	return std::uniform_int_distribution<size_t>(0, count - 1)(generator);
}

std::wstring chooseImage(const std::wstring& provider, const std::string& response) {
	if (provider == L"konachan") {
		json::JsonArray posts;
		require(json::JsonArray::TryParse(winrt::to_hstring(response), posts), "invalid JSON from Konachan");
		require(posts.Size() != 0, "Konachan returned no wallpapers");
		require(posts.GetAt(0).ValueType() == json::JsonValueType::Object, "invalid JSON wallpaper entry");
		auto url = getString(posts.GetObjectAt(0), L"file_url");
		require(!url.empty(), "missing image URL");
		return url;
	}
	json::JsonObject seasonal;
	require(json::JsonObject::TryParse(winrt::to_hstring(response), seasonal), "invalid JSON from osu!");
	require(seasonal.HasKey(L"backgrounds") && seasonal.GetNamedValue(L"backgrounds").ValueType() == json::JsonValueType::Array,
	        "invalid JSON backgrounds list");
	auto backgrounds = seasonal.GetNamedArray(L"backgrounds");
	require(backgrounds.Size() != 0, "osu! returned no wallpapers");
	auto index = static_cast<uint32_t>(randomIndex(backgrounds.Size()));
	require(backgrounds.GetAt(index).ValueType() == json::JsonValueType::Object, "invalid JSON wallpaper entry");
	auto url = getString(backgrounds.GetObjectAt(index), L"url");
	require(!url.empty(), "missing image URL");
	return url;
}

bool imageSignature(const std::string& bytes, const std::wstring& ext) {
	if (ext == L"jpg" || ext == L"jpeg") return bytes.size() >= 3 && bytes.compare(0, 3, "\xFF\xD8\xFF") == 0;
	if (ext == L"png") return bytes.size() >= 8 && bytes.compare(0, 8, "\x89PNG\r\n\x1A\n") == 0;
	if (ext == L"webp") return bytes.size() >= 12 && bytes.compare(0, 4, "RIFF") == 0 && bytes.compare(8, 4, "WEBP") == 0;
	if (ext == L"gif") return bytes.size() >= 6 && (bytes.compare(0, 6, "GIF87a") == 0 || bytes.compare(0, 6, "GIF89a") == 0);
	return bytes.size() >= 2 && bytes.compare(0, 2, "BM") == 0;
}

std::wstring imageFormat(const std::string& bytes, const std::wstring& preferred) {
	if (imageSignature(bytes, preferred)) return preferred;
	for (const auto* ext: {L"jpg", L"png", L"webp", L"gif", L"bmp"}) {
		if (imageSignature(bytes, ext)) return ext;
	}
	throw std::runtime_error("download is not a supported image");
}

void saveImage(const std::wstring& path, const std::string& bytes) {
	auto dir = path.substr(0, path.find_last_of(L'\\'));
	auto result = SHCreateDirectoryExW(nullptr, dir.c_str(), nullptr);
	require(result == ERROR_SUCCESS || result == ERROR_ALREADY_EXISTS || result == ERROR_FILE_EXISTS,
	        "cannot create wallpaper folder");
	auto temp = path + L"." + std::to_wstring(GetCurrentProcessId()) + L"."
	          + std::to_wstring(GetTickCount64()) + L".tmp";
	auto handle = CreateFileW(temp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
	require(handle != INVALID_HANDLE_VALUE, "cannot create temporary wallpaper");
	File file(handle);
	try {
		DWORD written = 0;
		require(WriteFile(file.get(), bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr) != 0
		        && written == bytes.size() && FlushFileBuffers(file.get()) != 0, "cannot write wallpaper");
		file.reset();
		require(MoveFileExW(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0,
		        "cannot rename wallpaper");
	} catch (...) {
		file.reset();
		DeleteFileW(temp.c_str());
		throw;
	}
}

} // namespace

int randomwall(const Args& args) {
	try {
		const char* usage = "usage: randomwall konachan|osu [--no-apply] [--out <dir>]";
		require(!args.empty() && (args[0] == L"konachan" || args[0] == L"osu"), usage);
		bool noApply = env(L"II_RANDOMWALL_NO_APPLY") == L"1";
		std::wstring output;
		for (size_t i = 1; i < args.size(); ++i) {
			if (args[i] == L"--no-apply") noApply = true;
			else if (args[i] == L"--out" && i + 1 < args.size() && !args[i + 1].empty()
			         && args[i + 1].rfind(L"--", 0) != 0) output = args[++i];
			else throw std::runtime_error(usage);
		}
		Apartment apartment;
		// Test overrides are read-only fixtures, available only when applying is disabled.
		auto testEnv = [&](const wchar_t* name) { return noApply ? env(name) : std::wstring(); };
		if (output.empty()) output = testEnv(L"II_RANDOMWALL_TEST_OUT");
		if (output.empty()) output = folder(FOLDERID_Pictures) + L"\\Wallpapers";
		output = fullPath(output);
		auto configPath = testEnv(L"II_RANDOMWALL_TEST_CONFIG");
		if (configPath.empty()) {
			configPath = env(L"LOCALAPPDATA");
			if (configPath.empty()) configPath = folder(FOLDERID_LocalAppData);
			configPath += L"\\quickshell\\illogical-impulse\\config.json";
		}
		json::JsonObject config;
		auto text = readUtf8(configPath, true);
		if (!text.empty()) json::JsonObject::TryParse(winrt::to_hstring(text), config);
		if (!config) config = json::JsonObject();
		auto agent = getString(existing(config, L"networking"), L"userAgent");
		if (agent.empty()) agent = L"ii-windows/randomwall";
		require(agent.find_first_of(L"\r\n") == std::wstring::npos, "invalid configured User-Agent");
		Http http(agent);
		progress(L"Fetching " + args[0] + L" wallpapers...");
		auto api = testEnv(L"II_RANDOMWALL_TEST_API_URL");
		if (api.empty()) api = args[0] == L"konachan"
		    ? L"https://konachan.net/post.json?tags=rating%3Asafe&limit=1&page=" + std::to_wstring(randomIndex(1000) + 1)
		    : L"https://osu.ppy.sh/api/v2/seasonal-backgrounds";
		auto fixture = testEnv(L"II_RANDOMWALL_TEST_RESPONSE");
		auto response = fixture.empty() ? http.get(api, JSON_LIMIT) : readUtf8(fixture);
		auto url = chooseImage(args[0], response);
		auto ext = imageExtension(url);
		progress(L"Downloading wallpaper...");
		auto imageFixture = testEnv(L"II_RANDOMWALL_TEST_IMAGE");
		auto bytes = imageFixture.empty() ? http.get(url, IMAGE_LIMIT) : readBytes(imageFixture, IMAGE_LIMIT);
		ext = imageFormat(bytes, ext);
		auto path = fullPath(output + L"\\random_wallpaper." + ext);
		auto current = getString(existing(config, L"background"), L"wallpaperPath");
		if (!current.empty() && _wcsicmp(path.c_str(), fullPath(current).c_str()) == 0) {
			path = fullPath(output + L"\\random_wallpaper-1." + ext);
		}
		saveImage(path, bytes);
		progress(L"Saved: " + path);
		if (noApply) {
			progress(L"Not applied (--no-apply).");
			return 0;
		}
		progress(L"Applying wallpaper...");
		require(::switchwall({L"--image", path}) == 0, "could not apply wallpaper");
		progress(L"Wallpaper applied.");
		return 0;
	} catch (const winrt::hresult_error&) {
		std::fputs("randomwall: invalid JSON/URL or Windows API failure\n", stderr);
	} catch (const std::exception& error) {
		std::fprintf(stderr, "randomwall: %s\n", error.what());
	}
	return 1;
}
