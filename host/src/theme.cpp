#include "common.h"

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <cwchar>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <thread>

#include <shlobj.h>

// Windows follows ii's palette while ii runs: dark/light mode for apps and the system, and the
// accent color (title bars, Start, selection highlights) from the wallpaper's source color.
// All per-user (HKCU) personalization values. Before a value is first changed, its original is
// recorded in %LOCALAPPDATA%\ii-windows\theme.txt ("<subkey>\t<name>\t<type, -1 = absent>\t<hex>");
// restore(), the guard and the rescue tools write every original back and delete the file.

namespace ii::theme {

namespace {

constexpr const wchar_t* PERSONALIZE = L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t* DWM = L"Software\\Microsoft\\Windows\\DWM";
constexpr const wchar_t* ACCENT = L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Accent";

std::mutex mutex; // one writer at a time (apply runs on worker threads)
// Off once restore() starts, so an apply still waiting for the lock can't undo the restore.
std::atomic<bool> active {false};
FILETIME lastSeen {};

std::wstring backupPath() { return dataDir() + L"\\theme.txt"; }

std::wstring generatedDir() {
	PWSTR path = nullptr;
	SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &path);
	std::wstring dir = path ? path : L"";
	CoTaskMemFree(path);
	return dir + L"\\quickshell\\State\\user\\generated";
}

std::string readFile(const std::wstring& path) {
	std::string text;
	if (auto* f = _wfopen(path.c_str(), L"rb")) {
		char buffer[4096];
		size_t n = 0;
		while ((n = fread(buffer, 1, sizeof(buffer), f)) > 0) text.append(buffer, n);
		fclose(f);
	}
	return text;
}

// "#rrggbb" for a key of colors.json (flat object of strings, written by switchwall).
bool colorOf(const std::string& json, const char* key, COLORREF& rgb) {
	auto needle = std::string("\"") + key + "\"";
	auto at = json.find(needle);
	if (at == std::string::npos) return false;
	auto hash = json.find('#', at + needle.size());
	if (hash == std::string::npos || hash + 7 > json.size()) return false;
	unsigned value = 0;
	if (sscanf_s(json.c_str() + hash + 1, "%6x", &value) != 1) return false;
	rgb = RGB((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF);
	return true;
}

COLORREF mix(COLORREF a, COLORREF b, double t) {
	auto channel = [t](int x, int y) { return static_cast<BYTE>(x + (y - x) * t + 0.5); };
	return RGB(channel(GetRValue(a), GetRValue(b)), channel(GetGValue(a), GetGValue(b)), channel(GetBValue(a), GetBValue(b)));
}

// What this run last wrote for each value (keyed like the backup file: "<subkey>\t<name>"), to tell
// ii's own value from one the user changed since. A guard or rescue process has no map and restores
// unconditionally: that is crash recovery.
std::map<std::wstring, std::basic_string<BYTE>> lastApplied;

std::set<std::wstring> recordedValues() {
	std::set<std::wstring> keys;
	if (auto* f = _wfopen(backupPath().c_str(), L"rt, ccs=UTF-8")) {
		wchar_t line[1024];
		while (fgetws(line, 1024, f)) {
			std::wstring s = line;
			auto first = s.find(L'\t');
			auto second = first == std::wstring::npos ? first : s.find(L'\t', first + 1);
			if (second != std::wstring::npos) keys.insert(s.substr(0, second));
		}
		fclose(f);
	}
	return keys;
}

// Records the value's current state once, then writes the new data if it differs.
bool setValue(const wchar_t* subkey, const wchar_t* name, DWORD type, const void* data, DWORD size) {
	HKEY key = nullptr;
	if (RegCreateKeyExW(HKEY_CURRENT_USER, subkey, 0, nullptr, 0, KEY_QUERY_VALUE | KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
		return false;
	}
	BYTE current[256];
	DWORD currentSize = sizeof(current);
	DWORD currentType = 0;
	auto exists = RegQueryValueExW(key, name, nullptr, &currentType, current, &currentSize) == ERROR_SUCCESS;
	if (exists && currentType == type && currentSize == size && std::memcmp(current, data, size) == 0) {
		RegCloseKey(key);
		return false;
	}

	auto id = std::wstring(subkey) + L"\t" + name;
	if (!recordedValues().contains(id)) {
		if (auto* f = _wfopen(backupPath().c_str(), L"at, ccs=UTF-8")) {
			std::wstring hex;
			wchar_t byte[3];
			for (DWORD i = 0; exists && i < currentSize; ++i) {
				swprintf(byte, 3, L"%02x", current[i]);
				hex += byte;
			}
			fwprintf(f, L"%ls\t%d\t%ls\n", id.c_str(), exists ? static_cast<int>(currentType) : -1, hex.c_str());
			fclose(f);
		}
	}
	RegSetValueExW(key, name, 0, type, static_cast<const BYTE*>(data), size);
	lastApplied[id] = std::basic_string<BYTE>(static_cast<const BYTE*>(data), size);
	RegCloseKey(key);
	return true;
}

bool setDword(const wchar_t* subkey, const wchar_t* name, DWORD value) {
	return setValue(subkey, name, REG_DWORD, &value, sizeof(value));
}

DWORD abgr(COLORREF rgb) { return 0xFF000000u | rgb; } // COLORREF is 0x00BBGGRR already
DWORD argb(COLORREF rgb, BYTE alpha) {
	return (static_cast<DWORD>(alpha) << 24) | (GetRValue(rgb) << 16) | (GetGValue(rgb) << 8) | GetBValue(rgb);
}

void broadcast() {
	// Apps and Explorer re-read the theme and accent on this.
	DWORD_PTR result = 0;
	SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0, reinterpret_cast<LPARAM>(L"ImmersiveColorSet"), SMTO_ABORTIFHUNG, 2000, &result);
}

void applyNow() {
	std::scoped_lock lock(mutex);
	if (!active) return;
	auto colors = readFile(generatedDir() + L"\\colors.json");
	COLORREF background = 0;
	COLORREF primary = 0;
	if (!colorOf(colors, "background", background) || !colorOf(colors, "primary", primary)) return;

	auto lightness = (std::max({GetRValue(background), GetGValue(background), GetBValue(background)})
	                  + std::min({GetRValue(background), GetGValue(background), GetBValue(background)}))
	               / 510.0;
	auto dark = lightness < 0.5;

	// The wallpaper's source color is what Windows itself would pick as accent.
	COLORREF accent = primary;
	auto source = readFile(generatedDir() + L"\\color.txt");
	unsigned value = 0;
	if (source.size() >= 7 && source[0] == '#' && sscanf_s(source.c_str() + 1, "%6x", &value) == 1) {
		accent = RGB((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF);
	}

	auto changed = false;
	DWORD light = dark ? 0 : 1;
	changed |= setDword(PERSONALIZE, L"AppsUseLightTheme", light);
	changed |= setDword(PERSONALIZE, L"SystemUsesLightTheme", light);

	// Windows' palette: three lighter shades, the accent, three darker ones, then a spare.
	COLORREF shades[8] = {
	    mix(accent, RGB(255, 255, 255), 0.6),
	    mix(accent, RGB(255, 255, 255), 0.4),
	    mix(accent, RGB(255, 255, 255), 0.2),
	    accent,
	    mix(accent, RGB(0, 0, 0), 0.2),
	    mix(accent, RGB(0, 0, 0), 0.4),
	    mix(accent, RGB(0, 0, 0), 0.6),
	    RGB(0x88, 0x88, 0x88),
	};
	BYTE palette[32];
	for (int i = 0; i < 8; ++i) {
		palette[i * 4] = GetRValue(shades[i]);
		palette[i * 4 + 1] = GetGValue(shades[i]);
		palette[i * 4 + 2] = GetBValue(shades[i]);
		palette[i * 4 + 3] = 0;
	}
	changed |= setValue(ACCENT, L"AccentPalette", REG_BINARY, palette, sizeof(palette));
	changed |= setDword(ACCENT, L"AccentColorMenu", abgr(shades[4]));
	changed |= setDword(ACCENT, L"StartColorMenu", abgr(shades[5]));
	// Title bars and window borders in the accent only if the user wants them (appearance.windowEffects.
	// accentBorders, off by default): some wallpapers give loud borders. Without it they keep the plain
	// frame of the light/dark theme; the accent still colours Start, selections and focus rings.
	auto titleBar = dark ? shades[5] : shades[2];
	changed |= setDword(DWM, L"AccentColor", abgr(titleBar));
	changed |= setDword(DWM, L"ColorizationColor", argb(titleBar, 0xC4));
	changed |= setDword(DWM, L"ColorizationAfterglow", argb(titleBar, 0xC4));
	changed |= setDword(DWM, L"ColorPrevalence", windowfx::accentBorders() ? 1 : 0);

	if (changed) {
		state::set(L"themeApplied", 1);
		log(L"theme: %ls, accent #%02x%02x%02x", dark ? L"dark" : L"light", GetRValue(accent), GetGValue(accent), GetBValue(accent));
		broadcast();
	}
}

bool colorsChanged() {
	WIN32_FILE_ATTRIBUTE_DATA data {};
	if (!GetFileAttributesExW((generatedDir() + L"\\colors.json").c_str(), GetFileExInfoStandard, &data)) return false;
	if (CompareFileTime(&data.ftLastWriteTime, &lastSeen) == 0) return false;
	lastSeen = data.ftLastWriteTime;
	return true;
}

} // namespace

void start() {
	active = true;
	lastSeen = {};
	apply();
}

void refresh() { lastSeen = {}; }

void apply() {
	if (!active || !colorsChanged()) return;
	// Off the host's thread: the broadcast can wait on slow windows, the keyboard hook can't.
	std::thread(applyNow).detach();
}

void restore() {
	active = false;
	std::scoped_lock lock(mutex);
	auto* f = _wfopen(backupPath().c_str(), L"rt, ccs=UTF-8");
	lastSeen = {};
	if (!f) {
		state::set(L"themeApplied", 0);
		return;
	}
	int restored = 0;
	int kept = 0;
	wchar_t line[1024];
	while (fgetws(line, 1024, f)) {
		std::wstring s = line;
		while (!s.empty() && (s.back() == L'\n' || s.back() == L'\r')) s.pop_back();
		auto a = s.find(L'\t');
		auto b = a == std::wstring::npos ? a : s.find(L'\t', a + 1);
		auto c = b == std::wstring::npos ? b : s.find(L'\t', b + 1);
		if (c == std::wstring::npos) continue;
		auto subkey = s.substr(0, a);
		auto name = s.substr(a + 1, b - a - 1);
		auto type = _wtoi(s.substr(b + 1, c - b - 1).c_str());
		auto hex = s.substr(c + 1);

		HKEY key = nullptr;
		if (RegOpenKeyExW(HKEY_CURRENT_USER, subkey.c_str(), 0, KEY_QUERY_VALUE | KEY_SET_VALUE, &key) != ERROR_SUCCESS) continue;
		// If the value is no longer what ii last wrote, the user changed it while ii ran: leave it.
		if (auto applied = lastApplied.find(subkey + L"\t" + name); applied != lastApplied.end()) {
			BYTE current[256];
			DWORD currentSize = sizeof(current);
			DWORD currentType = 0;
			auto exists = RegQueryValueExW(key, name.c_str(), nullptr, &currentType, current, &currentSize) == ERROR_SUCCESS;
			if (!exists || std::basic_string<BYTE>(current, currentSize) != applied->second) {
				RegCloseKey(key);
				++kept;
				continue;
			}
		}
		if (type < 0) {
			RegDeleteValueW(key, name.c_str());
		} else {
			std::basic_string<BYTE> data;
			for (size_t i = 0; i + 1 < hex.size(); i += 2) data.push_back(static_cast<BYTE>(std::wcstoul(hex.substr(i, 2).c_str(), nullptr, 16)));
			RegSetValueExW(key, name.c_str(), 0, static_cast<DWORD>(type), data.data(), static_cast<DWORD>(data.size()));
		}
		RegCloseKey(key);
		++restored;
	}
	fclose(f);
	DeleteFileW(backupPath().c_str());
	state::set(L"themeApplied", 0);
	lastApplied.clear();
	log(L"theme: restored %d values, left %d that were changed since", restored, kept);
	if (restored > 0) broadcast();
}

} // namespace ii::theme
