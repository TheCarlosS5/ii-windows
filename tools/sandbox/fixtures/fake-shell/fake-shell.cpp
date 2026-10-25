// Stand-in for quickshell.exe in the host tests. Never part of a package.
//   fake-shell.exe -p <mode>
//     exit:<n>      exits at once with code n
//     hang          stays alive and shows nothing (a QML that never renders)
//     window        shows one almost-invisible, click-through window per monitor (a shell that is up)
//     slow:<ms>     hangs for <ms>, then behaves like "window"
//     hb:<variant>  like "window", and reports the notification listener's health to the host once
//                   a second, the way the real shell does (host/src/health.cpp, protocol v1):
//         ok           available / granted / subscribed
//         denied       permission-required / denied / not subscribed
//         badinstance  a wrong instance id (must be ignored)
//         badversion   protocol version 99 (must be ignored)
//         silent2      two good heartbeats, then silence (the listener hung)
//         revoke2      two good heartbeats, then permission-required / denied (revoked)
//         foreign      like ok, but this is not the process the host started (must be ignored);
//                      the test passes II_HOST_HWND and a guessed II_INSTANCE_ID in the environment
//     beat          like "window", and posts the GUI-thread heartbeat (WM_APP + 5) once a second, as Quickshell does
//     freeze:<n>    "beat", then after n beats the GUI thread stops for ever (its windows stay on screen)
//     nowin:<n>     "beat", then after n beats its windows go (a lost graphics device) while it keeps beating
//     (any mode) WM_APP + 30 posted to its window: its windows go always-on-top without the foreground and are marked
//                   "quickshell:overview", the way ii's search shows over a game that keeps the foreground
//     (any mode) WM_APP + 31: its windows go always-on-top without the mark (another full-screen layer of ii's, such
//                   as the minimize animation: not the search)
//     busy:<n>      "beat", then after n beats the GUI thread computes for 9 s (busy, not frozen) and goes on beating
// The host starts its shell as: "<shell>" -p "<config>", so the mode travels as the config.
//
// Named ii-host.exe it is a stand-in for the HOST, started by ii-launcher (R07 tests); the mode is
// the environment variable II_FAKE_HOST:
//     ok        after a moment marks its version verified (as the real host does when its shell is
//               up), stays II_FAKE_HOST_LIFETIME_MS (default 1500), exits 0
//     crash     exits with code 3 at once
//     hang      never verifies and never exits
//     already   exits 17 (another host owns the desktop)
//   "--rescue" on the command line: writes rescue-ran.txt next to the exe and exits 0.
#include <windows.h>

#include <shellapi.h>

#include <string>
#include <vector>

#include "rollout.h"

namespace {

std::vector<HWND> windows;
std::wstring variant;
int beats = 0;

std::wstring env(const wchar_t* name) {
	wchar_t buffer[512];
	auto n = GetEnvironmentVariableW(name, buffer, _countof(buffer));
	return n > 0 && n < _countof(buffer) ? std::wstring(buffer, n) : std::wstring();
}

void sendHeartbeat(HWND self) {
	auto hostText = env(L"II_HOST_HWND");
	auto* host = reinterpret_cast<HWND>(static_cast<ULONG_PTR>(_wcstoui64(hostText.c_str(), nullptr, 10))); // NOLINT
	if (!host) return;
	++beats;
	if (variant == L"silent2" && beats > 2) return;

	std::wstring state = L"available";
	std::wstring permission = L"granted";
	bool subscribed = true;
	std::wstring version = L"1";
	auto id = env(L"II_INSTANCE_ID");
	if (variant == L"denied" || (variant == L"revoke2" && beats > 2)) {
		state = L"permission-required";
		permission = L"denied";
		subscribed = false;
	} else if (variant == L"badinstance") {
		id = L"{00000000-0000-0000-0000-000000000000}";
	} else if (variant == L"badversion") {
		version = L"99";
	}
	DWORD session = 0;
	ProcessIdToSessionId(GetCurrentProcessId(), &session);
	std::wstring json = L"{\"protocolVersion\":" + version + L",\"instanceId\":\"" + id + L"\",\"sessionId\":" + std::to_wstring(session)
	                  + L",\"requestId\":\"" + std::to_wstring(beats) + L"\",\"messageType\":\"service-state\",\"service\":\"notifications\",\"state\":\""
	                  + state + L"\",\"permission\":\"" + permission + L"\",\"subscribed\":" + (subscribed ? L"true" : L"false")
	                  + L",\"observedAtMonotonicMs\":" + std::to_wstring(GetTickCount64()) + L",\"error\":null}";
	COPYDATASTRUCT data {};
	data.dwData = 0x49490020; // COPYDATA_SERVICE_STATE
	data.cbData = static_cast<DWORD>((json.size() + 1) * sizeof(wchar_t));
	data.lpData = json.data();
	DWORD_PTR result = 0;
	SendMessageTimeoutW(host, WM_COPYDATA, reinterpret_cast<WPARAM>(self), reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG, 500, &result);
}

// beat / freeze:<n> / nowin:<n>
int guiBeats = 0;
int freezeAfter = 0;
int hideAfter = 0;
int busyAfter = 0;
bool guiHeartbeat = false;

void postGuiHeartbeat() {
	auto* host = reinterpret_cast<HWND>(static_cast<ULONG_PTR>(_wcstoui64(env(L"II_HOST_HWND").c_str(), nullptr, 10))); // NOLINT
	if (host) PostMessageW(host, WM_APP + 5, GetCurrentProcessId(), 0);
	++guiBeats;
	if (freezeAfter > 0 && guiBeats >= freezeAfter) {
		for (;;) Sleep(1000);
	}
	if (busyAfter > 0 && guiBeats == busyAfter) {
		volatile unsigned long long x = 0;
		auto until = GetTickCount64() + 9000;
		while (GetTickCount64() < until) x = x + 1;
	}
	if (hideAfter > 0 && guiBeats == hideAfter) {
		for (auto* w: windows) ShowWindow(w, SW_HIDE);
	}
}

LRESULT CALLBACK windowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
	if (msg == WM_TIMER && wParam == 1) {
		sendHeartbeat(hwnd);
		return 0;
	}
	if (msg == WM_TIMER && wParam == 2) {
		postGuiHeartbeat();
		return 0;
	}
	if (msg == WM_APP + 30 || msg == WM_APP + 31) { // tests: "the search is showing" / another layer on top
		for (auto* w: windows) {
			SetWindowPos(w, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
			if (msg == WM_APP + 30) SetPropW(w, L"quickshell:overview", reinterpret_cast<HANDLE>(1)); // NOLINT
		}
		return 0;
	}
	return DefWindowProcW(hwnd, msg, wParam, lParam);
}

BOOL CALLBACK onMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM) {
	MONITORINFO info {};
	info.cbSize = sizeof(info);
	if (!GetMonitorInfoW(monitor, &info)) return TRUE;
	auto* hwnd = CreateWindowExW(
	    WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED | WS_EX_TRANSPARENT,
	    L"IiFakeShell",
	    L"fake-shell",
	    WS_POPUP,
	    info.rcMonitor.left,
	    info.rcMonitor.top,
	    info.rcMonitor.right - info.rcMonitor.left,
	    info.rcMonitor.bottom - info.rcMonitor.top,
	    nullptr,
	    nullptr,
	    GetModuleHandleW(nullptr),
	    nullptr
	);
	if (hwnd) {
		SetLayeredWindowAttributes(hwnd, 0, 1, LWA_ALPHA); // 1/255: present but invisible
		ShowWindow(hwnd, SW_SHOWNOACTIVATE);
		windows.push_back(hwnd);
	}
	return TRUE;
}

void showWindowsAndWait() {
	WNDCLASSW wc {};
	wc.lpfnWndProc = windowProc;
	wc.hInstance = GetModuleHandleW(nullptr);
	wc.lpszClassName = L"IiFakeShell";
	RegisterClassW(&wc);
	EnumDisplayMonitors(nullptr, nullptr, onMonitor, 0);
	if (!variant.empty() && !windows.empty()) SetTimer(windows.front(), 1, 1000, nullptr);
	if (guiHeartbeat && !windows.empty()) SetTimer(windows.front(), 2, 1000, nullptr);
	MSG msg;
	while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
		TranslateMessage(&msg);
		DispatchMessageW(&msg);
	}
}

std::wstring exeDirectory() {
	wchar_t path[MAX_PATH];
	GetModuleFileNameW(nullptr, path, MAX_PATH);
	std::wstring full = path;
	return full.substr(0, full.find_last_of(L"\\/"));
}

int runAsFakeHost(int argc, wchar_t** argv) {
	auto dir = exeDirectory();
	for (int i = 1; i < argc; ++i) {
		if (std::wstring(argv[i]) == L"--rescue") {
			if (auto* f = _wfopen((dir + L"\\rescue-ran.txt").c_str(), L"wb")) fclose(f);
			return 0;
		}
	}
	auto mode = env(L"II_FAKE_HOST");
	if (mode == L"crash") return 3;
	if (mode == L"already") return 17;
	if (mode == L"hang") {
		Sleep(INFINITE);
		return 0;
	}
	Sleep(400);
	ii::rollout::markVerified(dir);
	auto lifetime = env(L"II_FAKE_HOST_LIFETIME_MS");
	Sleep(lifetime.empty() ? 1500 : static_cast<DWORD>(_wtoi(lifetime.c_str())));
	return 0;
}

bool isNamedHost() {
	auto dir = exeDirectory();
	wchar_t path[MAX_PATH];
	GetModuleFileNameW(nullptr, path, MAX_PATH);
	std::wstring name = path;
	name = name.substr(name.find_last_of(L"\\/") + 1);
	return _wcsicmp(name.c_str(), L"ii-host.exe") == 0;
}

} // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
	int argc = 0;
	auto** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
	if (isNamedHost()) return runAsFakeHost(argc, argv);
	std::wstring mode = L"window";
	for (int i = 1; i + 1 < argc; ++i) {
		if (std::wstring(argv[i]) == L"-p") mode = argv[i + 1];
	}
	LocalFree(argv);

	if (mode.rfind(L"exit:", 0) == 0) return _wtoi(mode.c_str() + 5);
	if (mode == L"hang") {
		Sleep(INFINITE);
		return 0;
	}
	if (mode.rfind(L"slow:", 0) == 0) {
		Sleep(static_cast<DWORD>(_wtoi(mode.c_str() + 5)));
		showWindowsAndWait();
		return 0;
	}
	if (mode.rfind(L"hb:", 0) == 0) variant = mode.substr(3);
	if (mode == L"beat" || mode.rfind(L"freeze:", 0) == 0 || mode.rfind(L"nowin:", 0) == 0 || mode.rfind(L"busy:", 0) == 0) guiHeartbeat = true;
	if (mode.rfind(L"busy:", 0) == 0) busyAfter = _wtoi(mode.c_str() + 5);
	if (mode.rfind(L"freeze:", 0) == 0) freezeAfter = _wtoi(mode.c_str() + 7);
	if (mode.rfind(L"nowin:", 0) == 0) hideAfter = _wtoi(mode.c_str() + 6);
	showWindowsAndWait();
	return 0;
}
