// Stand-in for quickshell.exe in the host tests. Never part of a package.
//   fake-shell.exe -p <mode>
//     exit:<n>   exits at once with code n
//     hang       stays alive and shows nothing (a QML that never renders)
//     window     shows one almost-invisible, click-through window per monitor (a shell that is up)
//     slow:<ms>  hangs for <ms>, then behaves like "window"
// The host starts its shell as: "<shell>" -p "<config>", so the mode travels as the config.
#include <windows.h>

#include <shellapi.h>

#include <string>
#include <vector>

namespace {

std::vector<HWND> windows;

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
	wc.lpfnWndProc = DefWindowProcW;
	wc.hInstance = GetModuleHandleW(nullptr);
	wc.lpszClassName = L"IiFakeShell";
	RegisterClassW(&wc);
	EnumDisplayMonitors(nullptr, nullptr, onMonitor, 0);
	MSG msg;
	while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
		TranslateMessage(&msg);
		DispatchMessageW(&msg);
	}
}

} // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
	int argc = 0;
	auto** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
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
	showWindowsAndWait();
	return 0;
}
