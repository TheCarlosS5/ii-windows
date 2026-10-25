#include "common.h"
#include "jsonlite.h"

#include <cstdio>
#include <string>

#include <shlobj.h>

// Plan 2.2: ii's own minimize animation (the shell flies a live thumbnail of the window down to the dock) needs
// Windows' own one off, or both would play. Only Windows' in-memory setting is changed (SPI_SETANIMATION without
// SPIF_UPDATEINIFILE): the user's saved value in HKCU\Control Panel\Desktop\WindowMetrics\MinAnimate is never
// touched, so putting it back is applying that saved value again, which every restore path does (normal exit,
// panic key, guard, rescue), and a logoff does by itself whatever happens.
//
// config.json: windowAnimations.minimizeToDock (default true). Off as well with appearance.reduceMotion (the
// lightweight mode: no animations from ii, Windows keeps its own).

namespace ii::minanim {

namespace {

bool overridden = false;
FILETIME seen {};
bool wanted = false;

std::wstring configPath() {
	PWSTR base = nullptr;
	std::wstring path;
	if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &base))) path = std::wstring(base) + L"\\quickshell\\illogical-impulse\\config.json";
	CoTaskMemFree(base);
	return path;
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

bool boolAt(const jsonlite::Value& root, const char* section, const char* key, bool fallback) {
	const auto* s = root.find(section);
	const auto* v = s && s->isObject() ? s->find(key) : nullptr;
	return v && v->type == jsonlite::Type::Bool ? v->boolean : fallback;
}

void setWindowsMinAnimate(int value) {
	ANIMATIONINFO info {};
	info.cbSize = sizeof(info);
	info.iMinAnimate = value;
	SystemParametersInfoW(SPI_SETANIMATION, sizeof(info), &info, SPIF_SENDCHANGE); // in memory only
}

} // namespace

void tick() {
	if (noUi()) return; // test hosts never change the tester's desktop
	auto path = configPath();
	WIN32_FILE_ATTRIBUTE_DATA data {};
	if (path.empty() || !GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) return;
	if (CompareFileTime(&data.ftLastWriteTime, &seen) != 0) {
		seen = data.ftLastWriteTime;
		auto parsed = jsonlite::parse(readFile(path));
		if (parsed.ok) {
			wanted = boolAt(parsed.value, "windowAnimations", "minimizeToDock", true) && !boolAt(parsed.value, "appearance", "reduceMotion", false);
		}
	}
	if (wanted && !overridden) {
		setWindowsMinAnimate(0);
		overridden = true;
		state::set(L"minAnimateOverridden", 1);
		log(L"minimize: Windows' own animation off while ii animates (in memory only)");
	} else if (!wanted && overridden) {
		restore();
	}
}

void restore() {
	// Whatever this or another process did: Windows gets the user's saved value back.
	if (noUi()) return;
	if (!overridden && state::get(L"minAnimateOverridden", 0) == 0) return;
	wchar_t value[8] {};
	DWORD size = sizeof(value);
	auto saved = RegGetValueW(HKEY_CURRENT_USER, L"Control Panel\\Desktop\\WindowMetrics", L"MinAnimate", RRF_RT_REG_SZ, nullptr, value, &size) == ERROR_SUCCESS
	           ? _wtoi(value) : 1;
	setWindowsMinAnimate(saved);
	overridden = false;
	seen = {};
	state::set(L"minAnimateOverridden", 0);
	log(L"minimize: Windows' own animation back to the saved setting (%d)", saved);
}

} // namespace ii::minanim
