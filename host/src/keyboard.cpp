#include <array>
#include <atomic>
#include <string>

#include "common.h"
#include "keyrouter.h"

#include <shellapi.h>

// Low-level keyboard hook mapping illogical-impulse's Super shortcuts onto the Windows key.
// What is swallowed and what is passed on is decided in keyrouter.cpp (tested on its own); the table
// of shortcuts is generated from shared/actions.json (docs/ATAJOS.md).
//
// Rules that keep Windows usable:
//  - The Win key itself is never swallowed, so Windows always knows it is held and its own
//    combos (Win+L, Win+E, Win+P, ...) keep working. Ctrl+Alt+Del never reaches hooks at all.
//  - Only combos in the table are swallowed, and only while the shell is running (its shortcut
//    sink window exists) and the app in front has not asked ii to step aside (below).
//  - A lone Win press opens ii's search instead of Start: before Windows sees the Win key-up we
//    inject an unassigned key (vkE8), which tells Windows "this was a combo" so Start stays closed.
//    Without the shell, nothing is injected and Start opens as usual.
//  - ii's shortcuts keep working over a maximized or ordinary window, a browser in F11 included.
//    They step aside (Windows gets its keys back) for exclusive fullscreen / presentation mode and
//    for borderless fullscreen windows, and for the programs named in shortcuts.ini [yield].
//
// The hook callback only reads cached state, feeds the router and posts messages; it calls no
// Windows API that can wait or enumerate (a hook that is slow is dropped silently by Windows, and
// then Win opens Start). The cache (is the shell there, who is in front) is refreshed OUTSIDE the
// hook, from window events and a once-a-second reconciliation.

namespace ii::keyboard {

namespace {

constexpr ULONG_PTR OWN_INPUT_TAG = 0x11A1D00D;

HHOOK hook = nullptr;
HWND notify = nullptr;

// Written by the host thread, read by the hook thread.
std::atomic<bool> cachedYield {false};
std::atomic<bool> cachedDesktop {false};
std::atomic<HWND> cachedSink {nullptr};
std::atomic<bool> resetRequested {false};
std::atomic<ULONGLONG> lastSinkLookup {0};

bool heldNow(int vk, void*) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }

Router router {heldNow, nullptr}; // touched only by the hook thread

std::wstring lowerExeName(DWORD pid) {
	std::wstring result;
	if (auto* process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid)) {
		wchar_t path[MAX_PATH * 2];
		DWORD size = static_cast<DWORD>(_countof(path));
		if (QueryFullProcessImageNameW(process, 0, path, &size)) {
			result.assign(path, size);
			result = result.substr(result.find_last_of(L"\\/") + 1);
			for (auto& c: result) c = static_cast<wchar_t>(towlower(c));
		}
		CloseHandle(process);
	}
	return result;
}

// %LOCALAPPDATA%\ii-windows\shortcuts.ini, re-read when it changes:
//   [policy]  fullscreen = auto | geometry | never
//   [yield]   processes = game.exe;other.exe     (ii's keys step aside for these)
//   [keep]    processes = app.exe                (ii's keys never step aside for these)
ForegroundRules loadRules() {
	static ForegroundRules rules;
	static FILETIME stamp {};
	static bool loaded = false;
	auto path = dataDir() + L"\\shortcuts.ini";
	WIN32_FILE_ATTRIBUTE_DATA data {};
	if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) {
		if (loaded && (stamp.dwLowDateTime || stamp.dwHighDateTime)) {
			rules = {};
			stamp = {};
		}
		loaded = true;
		return rules;
	}
	if (loaded && CompareFileTime(&data.ftLastWriteTime, &stamp) == 0) return rules;
	stamp = data.ftLastWriteTime;
	loaded = true;
	auto read = [&](const wchar_t* section, const wchar_t* key) {
		wchar_t buffer[2048] {};
		GetPrivateProfileStringW(section, key, L"", buffer, _countof(buffer), path.c_str());
		std::wstring text = buffer;
		for (auto& c: text) c = static_cast<wchar_t>(towlower(c));
		return text;
	};
	rules = {};
	auto policy = read(L"policy", L"fullscreen");
	if (policy == L"geometry") rules.policy = FullscreenPolicy::Geometry;
	else if (policy == L"never") rules.policy = FullscreenPolicy::Never;
	rules.yieldExes = read(L"yield", L"processes");
	rules.keepExes = read(L"keep", L"processes");
	log(L"keyboard: shortcuts.ini loaded (fullscreen=%s)", policy.empty() ? L"auto" : policy.c_str());
	return rules;
}

// Cheap: a window handle check, with a real lookup at most every 250 ms while there is none.
bool shellSinkPresent() {
	auto* sink = cachedSink.load();
	if (sink && IsWindow(sink)) return true;
	auto now = GetTickCount64();
	if (now - lastSinkLookup.load() < 250) return false;
	lastSinkLookup = now;
	sink = findShellSink();
	cachedSink = sink;
	return sink != nullptr;
}

// Releases a Win key-up preceded by an unassigned key (vkE8), all injected in one SendInput so
// the order is guaranteed. Windows then treats the Win press as part of a combo: no Start menu.
void releaseWinMasked(UINT winVk) {
	std::array<INPUT, 3> inputs {};
	for (auto& in: inputs) {
		in.type = INPUT_KEYBOARD;
		in.ki.dwExtraInfo = OWN_INPUT_TAG;
	}
	inputs[0].ki.wVk = 0xE8;
	inputs[1].ki.wVk = 0xE8;
	inputs[1].ki.dwFlags = KEYEVENTF_KEYUP;
	inputs[2].ki.wVk = static_cast<WORD>(winVk);
	inputs[2].ki.dwFlags = KEYEVENTF_KEYUP | KEYEVENTF_EXTENDEDKEY;
	SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT));
}

LRESULT CALLBACK proc(int code, WPARAM wParam, LPARAM lParam) {
	if (code != HC_ACTION) return CallNextHookEx(hook, code, wParam, lParam);

	auto* key = reinterpret_cast<KBDLLHOOKSTRUCT*>(lParam);
	// Skip only our own replayed keys; other injected input (on-screen keyboard, automation)
	// is treated like a physical keyboard.
	if (key->dwExtraInfo == OWN_INPUT_TAG) return CallNextHookEx(hook, code, wParam, lParam);

	if (resetRequested.exchange(false)) router.reset();

	auto down = wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN;
	Context context;
	context.shellPresent = shellSinkPresent();
	context.yieldToForeground = cachedYield.load();
	context.desktopInFront = cachedDesktop.load();

	auto result = router.onKey(key->vkCode, down, context);
	for (int i = 0; i < result.postCount; ++i) {
		PostMessageW(notify, WM_II_SHORTCUT, result.posts[static_cast<size_t>(i)].pressed ? 1 : 0, result.posts[static_cast<size_t>(i)].index);
	}
	if (result.maskWinRelease) releaseWinMasked(result.winVk);
	return result.swallow ? 1 : CallNextHookEx(hook, code, wParam, lParam);
}

HWINEVENTHOOK foregroundHook = nullptr;

void CALLBACK onForegroundChanged(HWINEVENTHOOK, DWORD, HWND, LONG, LONG, DWORD, DWORD) { refreshContext(); }

HANDLE hookThread = nullptr;
DWORD hookThreadId = 0;
HANDLE hookReady = nullptr;

// The hook lives on its own thread. Windows calls a low-level hook on the thread that installed
// it, and if that thread is busy for a moment (tray forwarding, Explorer restarts, the theme...)
// it skips the hook: the Win key then reaches Windows and opens Start. This thread does nothing
// but run the hook.
DWORD WINAPI hookThreadMain(LPVOID) {
	hook = SetWindowsHookExW(WH_KEYBOARD_LL, proc, GetModuleHandleW(nullptr), 0);
	auto error = GetLastError();
	SetEvent(hookReady);
	if (!hook) {
		log(L"keyboard: SetWindowsHookEx failed (%lu)", error);
		return 1;
	}
	log(L"keyboard: hook installed");
	MSG msg;
	while (GetMessageW(&msg, nullptr, 0, 0) > 0) DispatchMessageW(&msg);
	UnhookWindowsHookEx(hook);
	hook = nullptr;
	return 0;
}

} // namespace

// Called from the host's thread: on foreground changes, when the shell starts or stops, and once a
// second to reconcile (the sink window, shortcuts.ini, a window that went fullscreen in place).
void refreshContext() {
	cachedSink = findShellSink();
	HWND fg = GetForegroundWindow();
	if (!fg) {
		cachedYield = false;
		cachedDesktop = false;
		return;
	}
	wchar_t cls[64] {};
	GetClassNameW(fg, cls, 64);
	auto desktop = wcscmp(cls, L"Progman") == 0 || wcscmp(cls, L"WorkerW") == 0;
	cachedDesktop = desktop;

	DWORD pid = 0;
	GetWindowThreadProcessId(fg, &pid);
	auto* sink = cachedSink.load();
	ForegroundFacts facts;
	facts.isShellOrDesktop = desktop || wcscmp(cls, L"Shell_TrayWnd") == 0 || wcscmp(cls, L"Shell_SecondaryTrayWnd") == 0
	                      || pid == GetCurrentProcessId() || (sink && pid == processIdOf(sink));
	if (!facts.isShellOrDesktop) {
		RECT rect {};
		MONITORINFO info {};
		info.cbSize = sizeof(info);
		if (GetWindowRect(fg, &rect) && GetMonitorInfoW(MonitorFromWindow(fg, MONITOR_DEFAULTTONEAREST), &info)) {
			facts.coversMonitor = rect.left <= info.rcMonitor.left && rect.top <= info.rcMonitor.top
			                   && rect.right >= info.rcMonitor.right && rect.bottom >= info.rcMonitor.bottom;
		}
		auto style = GetWindowLongPtrW(fg, GWL_STYLE);
		facts.hasCaption = (style & WS_CAPTION) == WS_CAPTION;
		facts.maximized = IsZoomed(fg) || (style & WS_MAXIMIZE);
		QUERY_USER_NOTIFICATION_STATE state {};
		facts.exclusiveFullscreen = SUCCEEDED(SHQueryUserNotificationState(&state))
		                         && (state == QUNS_RUNNING_D3D_FULL_SCREEN || state == QUNS_PRESENTATION_MODE);
		facts.exe = lowerExeName(pid);
	}
	auto yield = shouldYield(facts, loadRules());
	if (yield != cachedYield.load()) {
		log(L"keyboard: shortcuts %s for %s", yield ? L"step aside" : L"active again", facts.exe.empty() ? L"(unknown)" : facts.exe.c_str());
	}
	cachedYield = yield;
}

void resetState() { resetRequested = true; }

bool install(HWND notifyWindow) {
	notify = notifyWindow;
	refreshContext();
	// Out of context: the callback runs on the host's thread, never inside another process.
	foregroundHook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, nullptr, onForegroundChanged, 0, 0, WINEVENT_OUTOFCONTEXT);
	hookReady = CreateEventW(nullptr, TRUE, FALSE, nullptr);
	hookThread = CreateThread(nullptr, 0, hookThreadMain, nullptr, 0, &hookThreadId);
	if (!hookThread) {
		log(L"keyboard: CreateThread failed (%lu)", GetLastError());
		return false;
	}
	// Above normal: key events must never wait behind other work on this machine.
	SetThreadPriority(hookThread, THREAD_PRIORITY_ABOVE_NORMAL);
	WaitForSingleObject(hookReady, 5000);
	return hook != nullptr;
}

void uninstall() {
	if (foregroundHook) UnhookWinEvent(foregroundHook);
	foregroundHook = nullptr;
	if (hookThread) {
		PostThreadMessageW(hookThreadId, WM_QUIT, 0, 0);
		WaitForSingleObject(hookThread, 2000);
		CloseHandle(hookThread);
		hookThread = nullptr;
	}
	if (hookReady) CloseHandle(hookReady);
	hookReady = nullptr;
	log(L"keyboard: hook removed");
}

const wchar_t* shortcutName(LPARAM index) { return nameOf(static_cast<Index>(index)); }

} // namespace ii::keyboard
