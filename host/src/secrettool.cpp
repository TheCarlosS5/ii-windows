// secret-tool for Windows (ii-shim): where ii keeps API keys (AI chat, etc.), as libsecret does on
// Linux. Each secret is encrypted with DPAPI for the current Windows user (only this user, on
// this PC, can read it back) and kept in %LOCALAPPDATA%\ii-windows\secrets\<hash>.bin; the
// attributes (e.g. application illogical-impulse) name the entry.
//
//   secret-tool store --label=<l> <attr> <value> ...   secret from stdin
//   secret-tool lookup <attr> <value> ...               prints it; exit 1 if there is none
//   secret-tool clear <attr> <value> ...

#include <cstdio>
#include <string>
#include <vector>

#include <windows.h>
#include <dpapi.h>
#include <shlobj.h>

namespace {

std::wstring entryPath(const std::vector<std::wstring>& attributes, bool create) {
	wchar_t* base = nullptr;
	if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &base))) return {};
	std::wstring dir = std::wstring(base) + L"\\ii-windows\\secrets";
	CoTaskMemFree(base);
	if (create) SHCreateDirectoryExW(nullptr, dir.c_str(), nullptr);
	// FNV-1a of the attributes: a stable file name for the entry.
	unsigned long long hash = 1469598103934665603ULL;
	for (const auto& a: attributes) {
		for (auto ch: a + L'\x1f') {
			hash ^= static_cast<unsigned long long>(ch);
			hash *= 1099511628211ULL;
		}
	}
	wchar_t name[32];
	swprintf(name, 32, L"\\%016llx.bin", hash);
	return dir + name;
}

std::vector<std::wstring> attributesOf(const std::vector<std::wstring>& args, size_t from) {
	std::vector<std::wstring> attrs;
	for (auto i = from; i < args.size(); ++i) {
		if (args[i].rfind(L"--", 0) == 0) continue; // --label=..., options
		attrs.push_back(args[i]);
	}
	return attrs;
}

std::string readStdin() {
	std::string data;
	char buffer[4096];
	size_t n = 0;
	while ((n = fread(buffer, 1, sizeof(buffer), stdin)) > 0) data.append(buffer, n);
	return data;
}

} // namespace

int secretTool(const std::vector<std::wstring>& args) {
	if (args.empty()) return 2;
	const auto& command = args[0];
	auto attrs = attributesOf(args, 1);
	if (attrs.empty()) return 2;

	if (command == L"store") {
		auto secret = readStdin();
		DATA_BLOB in {static_cast<DWORD>(secret.size()), reinterpret_cast<BYTE*>(secret.data())};
		DATA_BLOB out {};
		if (!CryptProtectData(&in, L"ii-windows secret", nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &out)) return 1;
		auto path = entryPath(attrs, true);
		auto* file = _wfopen(path.c_str(), L"wb");
		auto ok = file && fwrite(out.pbData, 1, out.cbData, file) == out.cbData;
		if (file) fclose(file);
		LocalFree(out.pbData);
		return ok ? 0 : 1;
	}
	if (command == L"lookup") {
		auto* file = _wfopen(entryPath(attrs, false).c_str(), L"rb");
		if (!file) return 1;
		std::string data;
		char buffer[4096];
		size_t n = 0;
		while ((n = fread(buffer, 1, sizeof(buffer), file)) > 0) data.append(buffer, n);
		fclose(file);
		DATA_BLOB in {static_cast<DWORD>(data.size()), reinterpret_cast<BYTE*>(data.data())};
		DATA_BLOB out {};
		if (!CryptUnprotectData(&in, nullptr, nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &out)) return 1;
		fwrite(out.pbData, 1, out.cbData, stdout);
		fflush(stdout);
		SecureZeroMemory(out.pbData, out.cbData);
		LocalFree(out.pbData);
		return 0;
	}
	if (command == L"clear") {
		DeleteFileW(entryPath(attrs, false).c_str());
		return 0;
	}
	return 2;
}
