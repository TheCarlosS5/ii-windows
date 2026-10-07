#include "common.h"

#include <cstdio>
#include <set>

// Windows' own notification banners would pop up next to ii's. While ii runs, each app's
// "Show notification banners" switch (HKCU ...\Notifications\Settings\<AUMID>, DWORD ShowBanner)
// is turned off. Toasts still reach the notification center, which is where ii reads them from.
//
// Before a value is touched, its original state goes to %LOCALAPPDATA%\ii-windows\banners.txt
// ("<original>\t<key path>", original -1 = value absent). restore(), the guard process and the
// rescue tools put every recorded value back and delete the file.

namespace ii::banners {

namespace {

constexpr const wchar_t* SETTINGS_KEY = L"Software\\Microsoft\\Windows\\CurrentVersion\\Notifications\\Settings";

std::wstring backupPath() { return dataDir() + L"\\banners.txt"; }

// Paths already recorded in the backup (the first record holds the true original).
std::set<std::wstring>& recorded() {
	static std::set<std::wstring> paths;
	static bool loaded = false;
	if (!loaded) {
		loaded = true;
		if (auto* f = _wfopen(backupPath().c_str(), L"rt, ccs=UTF-8")) {
			wchar_t line[1024];
			while (fgetws(line, 1024, f)) {
				std::wstring s = line;
				while (!s.empty() && (s.back() == L'\n' || s.back() == L'\r')) s.pop_back();
				auto tab = s.find(L'\t');
				if (tab != std::wstring::npos) paths.insert(s.substr(tab + 1));
			}
			fclose(f);
		}
	}
	return paths;
}

void record(const std::wstring& path, int original) {
	if (auto* f = _wfopen(backupPath().c_str(), L"at, ccs=UTF-8")) {
		fwprintf(f, L"%d\t%ls\n", original, path.c_str());
		fclose(f);
	}
	recorded().insert(path);
}

// App keys are the ones holding values; AUMIDs with backslashes nest as subkeys.
void forEachAppKey(HKEY key, const std::wstring& path, void (*fn)(HKEY, const std::wstring&)) {
	DWORD values = 0;
	DWORD subkeys = 0;
	if (RegQueryInfoKeyW(key, nullptr, nullptr, nullptr, &subkeys, nullptr, nullptr, &values, nullptr, nullptr, nullptr, nullptr) != ERROR_SUCCESS) {
		return;
	}
	if (values > 0 && !path.empty()) fn(key, path);

	for (DWORD i = 0; i < subkeys; ++i) {
		wchar_t name[256];
		DWORD len = 256;
		if (RegEnumKeyExW(key, i, name, &len, nullptr, nullptr, nullptr, nullptr) != ERROR_SUCCESS) continue;
		HKEY child = nullptr;
		if (RegOpenKeyExW(key, name, 0, KEY_READ | KEY_SET_VALUE, &child) != ERROR_SUCCESS) continue;
		forEachAppKey(child, path.empty() ? name : path + L"\\" + name, fn);
		RegCloseKey(child);
	}
}

void hideIn(HKEY key, const std::wstring& path) {
	DWORD value = 1;
	DWORD size = sizeof(value);
	DWORD type = 0;
	auto present = RegQueryValueExW(key, L"ShowBanner", nullptr, &type, reinterpret_cast<BYTE*>(&value), &size) == ERROR_SUCCESS
	            && type == REG_DWORD;

	if (!recorded().contains(path)) record(path, present ? static_cast<int>(value) : -1);
	if (present && value == 0) return;

	DWORD off = 0;
	RegSetValueExW(key, L"ShowBanner", 0, REG_DWORD, reinterpret_cast<const BYTE*>(&off), sizeof(off));
}

} // namespace

void hide() {
	HKEY settings = nullptr;
	if (RegOpenKeyExW(HKEY_CURRENT_USER, SETTINGS_KEY, 0, KEY_READ | KEY_SET_VALUE, &settings) != ERROR_SUCCESS) return;
	auto before = recorded().size();
	forEachAppKey(settings, L"", hideIn);
	RegCloseKey(settings);
	state::set(L"bannersHidden", 1);
	if (recorded().size() != before) log(L"banners: off for %zu apps", recorded().size() - before);
}

void restore() {
	auto* f = _wfopen(backupPath().c_str(), L"rt, ccs=UTF-8");
	if (!f) {
		state::set(L"bannersHidden", 0);
		return;
	}

	std::set<std::wstring> done;
	int restored = 0;
	wchar_t line[1024];
	while (fgetws(line, 1024, f)) {
		std::wstring s = line;
		while (!s.empty() && (s.back() == L'\n' || s.back() == L'\r')) s.pop_back();
		auto tab = s.find(L'\t');
		if (tab == std::wstring::npos) continue;
		auto original = _wtoi(s.substr(0, tab).c_str());
		auto path = s.substr(tab + 1);
		if (!done.insert(path).second) continue;

		HKEY key = nullptr;
		auto full = std::wstring(SETTINGS_KEY) + L"\\" + path;
		if (RegOpenKeyExW(HKEY_CURRENT_USER, full.c_str(), 0, KEY_SET_VALUE, &key) != ERROR_SUCCESS) continue;
		if (original < 0) {
			RegDeleteValueW(key, L"ShowBanner");
		} else {
			auto value = static_cast<DWORD>(original);
			RegSetValueExW(key, L"ShowBanner", 0, REG_DWORD, reinterpret_cast<const BYTE*>(&value), sizeof(value));
		}
		RegCloseKey(key);
		++restored;
	}
	fclose(f);

	DeleteFileW(backupPath().c_str());
	recorded().clear();
	state::set(L"bannersHidden", 0);
	log(L"banners: restored %d apps", restored);
}

} // namespace ii::banners
