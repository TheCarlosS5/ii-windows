#include "common.h"
#include "jsonlite.h"

#include <cstdio>
#include <string>

#include <shlobj.h>

// Plan 2.2: ii's own minimize animation (the shell flies a card of the window down to the dock) needs Windows' own one
// off, or both would play. That one setting (MinAnimate) is also Windows' maximize and restore animation of every
// window: those are off too while ii runs (Settings > Interface > Window animations says so).
// Only Windows' in-memory setting is changed (SPI_SETANIMATION without SPIF_UPDATEINIFILE); a logoff puts the saved
// one back whatever happens. The value Windows had when ii turned it off is kept in state.ini (minAnimateOriginal), and
// every restore path (normal exit, panic key, guard, rescue) applies that one, not the registry's: Windows writes its
// in-memory value to the registry when the user presses Apply in System Properties > Performance while ii runs, and
// that would be ii's 0. If the registry was left that way, the original is written back to it too.
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

void setWindowsMinAnimate(int value, bool save = false) {
	ANIMATIONINFO info {};
	info.cbSize = sizeof(info);
	info.iMinAnimate = value;
	SystemParametersInfoW(SPI_SETANIMATION, sizeof(info), &info, SPIF_SENDCHANGE | (save ? SPIF_UPDATEINIFILE : 0)); // in memory unless save
}

int windowsMinAnimate() {
	ANIMATIONINFO info {};
	info.cbSize = sizeof(info);
	return SystemParametersInfoW(SPI_GETANIMATION, sizeof(info), &info, 0) ? info.iMinAnimate : 1;
}

// The saved setting: 0 or 1, or -1 if there is none.
int registryMinAnimate() {
	wchar_t value[8] {};
	DWORD size = sizeof(value);
	if (RegGetValueW(HKEY_CURRENT_USER, L"Control Panel\\Desktop\\WindowMetrics", L"MinAnimate", RRF_RT_REG_SZ, nullptr, value, &size) != ERROR_SUCCESS) return -1;
	return _wtoi(value) ? 1 : 0;
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
		// What Windows has now is the user's, unless an ii that ended without restoring left its own 0 in memory
		// (then the original it recorded stays).
		if (state::get(L"minAnimateOverridden", 0) == 0) state::set(L"minAnimateOriginal", windowsMinAnimate() ? 1 : 0);
		setWindowsMinAnimate(0);
		overridden = true;
		state::set(L"minAnimateOverridden", 1);
		log(L"minimize: Windows' own animation off while ii animates (in memory only)");
	} else if (!wanted && overridden) {
		restore();
	}
}

void restore() {
	// Whatever this or another process did: Windows gets back what it had before ii.
	if (noUi()) return;
	if (!overridden && state::get(L"minAnimateOverridden", 0) == 0) return;
	auto registry = registryMinAnimate();
	auto original = state::get(L"minAnimateOriginal", -1);
	if (original < 0) original = registry < 0 ? 1 : registry; // recorded by an older ii-host: the registry's
	// Windows saved ii's 0 (Performance > Apply while ii ran): the user's value goes back to the registry as well.
	auto rewrite = registry >= 0 && registry != original;
	setWindowsMinAnimate(original, rewrite);
	overridden = false;
	seen = {};
	state::set(L"minAnimateOverridden", 0);
	log(L"minimize: Windows' own animation back to %d, as it was before ii%s", original, rewrite ? L" (the registry too: it had ii's value)" : L"");
}

} // namespace ii::minanim
