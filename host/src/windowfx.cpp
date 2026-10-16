#include "common.h"

#include <algorithm>
#include <cstdio>
#include <cwchar>
#include <cwctype>
#include <iterator>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include <dwmapi.h>
#include <shlobj.h>

#include "jsonlite.h"

// Light transparency for the windows of other programs, and no loud accent-coloured window borders.
//
// Transparency: a window that is an ordinary application window gets WS_EX_LAYERED with a constant alpha
// (SetLayeredWindowAttributes), the same thing a program can do to its own window. Nothing is injected into
// any process. What is left alone, always: games and their launchers (by folder and by name), windows that
// cover a whole monitor, windows that already use transparency themselves, store/WinUI apps and Windows
// Terminal (they draw through DirectComposition and a layered style would blank them), always-on-top
// windows, tool windows, menus, ii's own windows, and the programs the user listed.
//
// Every window this touches is marked with a window property; stop() and restore() undo exactly those, so
// turning the option off, quitting ii-host and the rescue tools (--rescue) all give the windows back as
// they were.
//
// The settings come from ii's config.json (appearance.windowEffects), re-read when the file changes:
//   transparency  bool  (default true)    opacity  int, percent (default 94)
//   accentBorders bool  (default false)   exclude  string, program names separated by ; or ,

namespace ii::windowfx {

namespace {

constexpr const wchar_t* MARK = L"ii.windowfx";
constexpr LONG_PTR EX_NOREDIRECTIONBITMAP = 0x00200000L;

struct Settings {
	bool enabled = true;
	int opacity = 94;
	bool accentBorders = false;
	std::vector<std::wstring> exclude; // lower case program names / path pieces
};

std::mutex settingsMutex; // theme.cpp reads accentBorders() from a worker thread
Settings settings;
FILETIME settingsStamp {};
bool settingsLoaded = false;

std::unordered_map<HWND, BYTE> applied; // windows this run made translucent -> the alpha they got
std::unordered_map<DWORD, std::wstring> exeOfPid; // pid -> lower-case exe path ("?" = cannot tell)
ULONGLONG exeCacheCleared = 0;
HWINEVENTHOOK showHook = nullptr;
const DWORD ownPid = GetCurrentProcessId();

std::wstring lowerCopy(std::wstring text) {
	for (auto& c: text) c = static_cast<wchar_t>(std::towlower(c));
	return text;
}

std::wstring configPath() {
	PWSTR path = nullptr;
	SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &path);
	std::wstring dir = path ? path : L"";
	CoTaskMemFree(path);
	return dir + L"\\quickshell\\illogical-impulse\\config.json";
}

std::wstring widen(const std::string& text) {
	if (text.empty()) return {};
	auto size = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
	std::wstring out(static_cast<size_t>(size), L'\0');
	MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size);
	return out;
}

// Reads config.json when it changed. True when the settings changed.
bool reloadSettings() {
	std::scoped_lock lock(settingsMutex);
	WIN32_FILE_ATTRIBUTE_DATA data {};
	if (!GetFileAttributesExW(configPath().c_str(), GetFileExInfoStandard, &data)) return false;
	if (settingsLoaded && CompareFileTime(&data.ftLastWriteTime, &settingsStamp) == 0) return false;
	settingsStamp = data.ftLastWriteTime;

	Settings next;
	if (auto* f = _wfopen(configPath().c_str(), L"rb")) {
		std::string text;
		char buffer[4096];
		size_t n = 0;
		while ((n = fread(buffer, 1, sizeof(buffer), f)) > 0 && text.size() < (8u << 20)) text.append(buffer, n);
		fclose(f);
		auto parsed = jsonlite::parse(text);
		if (parsed.ok) {
			const jsonlite::Value* node = parsed.value.find("appearance");
			node = node ? node->find("windowEffects") : nullptr;
			if (node && node->isObject()) {
				if (auto* v = node->find("transparency"); v && v->type == jsonlite::Type::Bool) next.enabled = v->boolean;
				if (auto* v = node->find("opacity"); v && v->type == jsonlite::Type::Number) next.opacity = std::clamp(static_cast<int>(v->asDouble()), 40, 100);
				if (auto* v = node->find("accentBorders"); v && v->type == jsonlite::Type::Bool) next.accentBorders = v->boolean;
				if (auto* v = node->find("exclude"); v && v->type == jsonlite::Type::String) {
					std::wstring list = lowerCopy(widen(v->text)), piece;
					for (auto c: list + L";") {
						if (c == L';' || c == L',') {
							while (!piece.empty() && piece.front() == L' ') piece.erase(piece.begin());
							while (!piece.empty() && piece.back() == L' ') piece.pop_back();
							if (!piece.empty()) next.exclude.push_back(piece);
							piece.clear();
						} else {
							piece += c;
						}
					}
				}
			}
		}
	}
	auto changed = !settingsLoaded || next.enabled != settings.enabled || next.opacity != settings.opacity
	            || next.accentBorders != settings.accentBorders || next.exclude != settings.exclude;
	settings = next;
	settingsLoaded = true;
	return changed;
}

Settings currentSettings() {
	std::scoped_lock lock(settingsMutex);
	return settings;
}

// What is never touched, whatever the user says: games, their launchers and anti-cheat.
bool builtinExcluded(const std::wstring& exePath) {
	static const wchar_t* folders[] = {L"\\steamapps\\common\\", L"\\riot games\\", L"\\epic games\\", L"\\battle.net\\", L"\\ubisoft game launcher\\",
	                                   L"\\ea games\\", L"\\gog galaxy\\games\\", L"\\xboxgames\\", L"\\easyanticheat", L"\\battleye"};
	static const wchar_t* names[] = {L"valorant", L"vgc.exe", L"vgtray.exe", L"riotclient", L"leagueclient", L"league of legends", L"fortnite",
	                                 L"easyanticheat", L"battleye", L"cs2.exe", L"csgo.exe", L"genshinimpact", L"yuanshen", L"starrail", L"zenlesszonezero"};
	for (auto* f: folders)
		if (exePath.find(f) != std::wstring::npos) return true;
	auto slash = exePath.find_last_of(L'\\');
	auto base = slash == std::wstring::npos ? exePath : exePath.substr(slash + 1);
	for (auto* n: names)
		if (base.find(n) != std::wstring::npos) return true;
	return false;
}

const std::wstring& exeOf(DWORD pid) {
	auto now = GetTickCount64();
	if (now - exeCacheCleared > 60000) { // pids get reused
		exeOfPid.clear();
		exeCacheCleared = now;
	}
	auto it = exeOfPid.find(pid);
	if (it != exeOfPid.end()) return it->second;
	std::wstring path = L"?";
	if (auto* process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid)) {
		wchar_t buffer[MAX_PATH * 2];
		DWORD size = static_cast<DWORD>(std::size(buffer));
		if (QueryFullProcessImageNameW(process, 0, buffer, &size)) path = lowerCopy(std::wstring(buffer, size));
		CloseHandle(process);
	}
	return exeOfPid.emplace(pid, path).first->second;
}

bool userExcluded(const Settings& s, const std::wstring& exePath) {
	for (const auto& piece: s.exclude) {
		if (exePath.find(piece) != std::wstring::npos) return true; // "chrome", "chrome.exe", "\\games\\"
	}
	return false;
}

// Should this window be translucent? `tracked`: the layered style on it is ours.
bool eligible(HWND h, const Settings& s, bool tracked) {
	if (!IsWindow(h) || !IsWindowVisible(h)) return false;
	if (GetAncestor(h, GA_ROOT) != h || GetWindow(h, GW_OWNER) != nullptr) return false;

	auto ex = GetWindowLongPtrW(h, GWL_EXSTYLE);
	auto style = GetWindowLongPtrW(h, GWL_STYLE);
	LONG_PTR never = WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST | WS_EX_TRANSPARENT | EX_NOREDIRECTIONBITMAP;
	if (!tracked) never |= WS_EX_LAYERED; // the program uses transparency itself: not ours to touch
	if (ex & never) return false;
	if (!(style & (WS_CAPTION | WS_THICKFRAME))) return false; // splash screens, popups, custom overlays
	if (GetWindowTextLengthW(h) == 0) return false;

	DWORD cloaked = 0;
	DwmGetWindowAttribute(h, DWMWA_CLOAKED, &cloaked, sizeof(cloaked));
	if (cloaked != 0) return false; // another virtual desktop, a suspended store app

	wchar_t cls[96] {};
	GetClassNameW(h, cls, static_cast<int>(std::size(cls)));
	static const wchar_t* skipClasses[] = {L"Progman", L"WorkerW", L"Shell_TrayWnd", L"Shell_SecondaryTrayWnd", L"ApplicationFrameWindow",
	                                      L"Windows.UI.Core.CoreWindow", L"CASCADIA_HOSTING_WINDOW_CLASS", L"#32768", L"tooltips_class32",
	                                      L"XamlExplorerHostIslandWindow", L"WinUIDesktopWin32WindowClass"};
	for (auto* c: skipClasses)
		if (wcscmp(cls, c) == 0) return false;

	// A window covering its whole monitor without a title bar: a game or a video in fullscreen.
	RECT rect {};
	MONITORINFO info {};
	info.cbSize = sizeof(info);
	if (GetWindowRect(h, &rect) && GetMonitorInfoW(MonitorFromWindow(h, MONITOR_DEFAULTTONEAREST), &info)) {
		auto covers = rect.left <= info.rcMonitor.left && rect.top <= info.rcMonitor.top && rect.right >= info.rcMonitor.right
		           && rect.bottom >= info.rcMonitor.bottom;
		if (covers && (style & WS_CAPTION) != WS_CAPTION) return false;
	}

	DWORD pid = 0;
	GetWindowThreadProcessId(h, &pid);
	if (pid == 0 || pid == ownPid) return false;
	const auto& exe = exeOf(pid);
	if (exe == L"?") return false; // cannot tell (elevated or protected): leave it
	auto slash = exe.find_last_of(L'\\');
	auto base = slash == std::wstring::npos ? exe : exe.substr(slash + 1);
	if (base == L"quickshell.exe" || base == L"ii-host.exe" || base == L"ii-shim.exe" || base == L"qs.exe") return false;
	if (builtinExcluded(exe) || userExcluded(s, exe)) return false;
	return true;
}

BYTE alphaOf(const Settings& s) { return static_cast<BYTE>(std::clamp(s.opacity, 40, 100) * 255 / 100); }

void restoreOne(HWND h) {
	if (IsWindow(h)) {
		auto ex = GetWindowLongPtrW(h, GWL_EXSTYLE);
		if (ex & WS_EX_LAYERED) {
			SetWindowLongPtrW(h, GWL_EXSTYLE, ex & ~static_cast<LONG_PTR>(WS_EX_LAYERED));
			RedrawWindow(h, nullptr, nullptr, RDW_INVALIDATE | RDW_FRAME | RDW_ALLCHILDREN);
		}
		RemovePropW(h, MARK);
	}
	applied.erase(h);
}

void applyTo(HWND h, const Settings& s) {
	auto alpha = alphaOf(s);
	auto known = applied.find(h);
	if (known != applied.end()) {
		if (known->second != alpha && SetLayeredWindowAttributes(h, 0, alpha, LWA_ALPHA)) known->second = alpha;
		return;
	}
	if (!eligible(h, s, false)) return;
	auto ex = GetWindowLongPtrW(h, GWL_EXSTYLE);
	SetWindowLongPtrW(h, GWL_EXSTYLE, ex | WS_EX_LAYERED);
	if (!(GetWindowLongPtrW(h, GWL_EXSTYLE) & WS_EX_LAYERED)) return; // refused (another user's or elevated window)
	if (!SetLayeredWindowAttributes(h, 0, alpha, LWA_ALPHA)) {
		SetWindowLongPtrW(h, GWL_EXSTYLE, ex);
		return;
	}
	SetPropW(h, MARK, reinterpret_cast<HANDLE>(1));
	applied[h] = alpha;
}

void CALLBACK onWindowEvent(HWINEVENTHOOK, DWORD, HWND h, LONG idObject, LONG idChild, DWORD, DWORD) {
	if (!h || idObject != OBJID_WINDOW || idChild != CHILDID_SELF) return;
	auto s = currentSettings();
	if (s.enabled) applyTo(h, s);
}

BOOL CALLBACK sweepProc(HWND h, LPARAM data) {
	auto* s = reinterpret_cast<const Settings*>(data); // NOLINT
	if (!applied.contains(h)) applyTo(h, *s);
	return TRUE;
}

BOOL CALLBACK restoreMarkedProc(HWND h, LPARAM) {
	if (GetPropW(h, MARK)) restoreOne(h);
	return TRUE;
}

} // namespace

bool accentBorders() {
	reloadSettings();
	return currentSettings().accentBorders;
}

void start() {
	reloadSettings();
	if (!showHook) {
		showHook = SetWinEventHook(EVENT_OBJECT_SHOW, EVENT_OBJECT_SHOW, nullptr, onWindowEvent, 0, 0, WINEVENT_OUTOFCONTEXT);
	}
	tick();
}

// Once a second: the settings, windows the events missed, windows that stopped being eligible.
void tick() {
	auto changed = reloadSettings();
	auto s = currentSettings();
	if (changed) theme::refresh(); // the accent borders option decides ColorPrevalence

	if (!s.enabled) {
		for (auto it = applied.begin(); it != applied.end();) {
			auto h = it->first;
			++it;
			restoreOne(h);
		}
		return;
	}
	for (auto it = applied.begin(); it != applied.end();) {
		auto h = it->first;
		++it;
		if (!IsWindow(h)) applied.erase(h);
		else if (!eligible(h, s, true)) restoreOne(h);
	}
	EnumWindows(sweepProc, reinterpret_cast<LPARAM>(&s)); // NOLINT
}

// Gives back every window this run touched, and stops watching.
void stop() {
	if (showHook) UnhookWinEvent(showHook);
	showHook = nullptr;
	restore();
}

// Gives back every window that carries our mark, from any process: the rescue and the guard call this too.
void restore() {
	for (auto it = applied.begin(); it != applied.end();) {
		auto h = it->first;
		++it;
		restoreOne(h);
	}
	EnumWindows(restoreMarkedProc, 0);
}

} // namespace ii::windowfx
