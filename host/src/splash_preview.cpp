// Development only (not packaged): the welcome cover on its own, without a shell, to look at it.
//   ii-splash-preview.exe [interfaceMs] [desktopMs] [readyMs]
// The stages are faked with windows of this process (the cover watches the "shell" pid); set
// II_DATA_DIR to a scratch folder so the real startup timing and ready file are left alone.
#include "common.h"

#include <objbase.h>
#include <shellapi.h>

namespace ii::keyboard {
void setCoverUp(bool) {}
} // namespace ii::keyboard

namespace {
HWND fake = nullptr;

LRESULT CALLBACK fakeProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
	if (msg == WM_PAINT) {
		PAINTSTRUCT ps;
		auto* dc = BeginPaint(hwnd, &ps);
		FillRect(dc, &ps.rcPaint, static_cast<HBRUSH>(GetStockObject(DKGRAY_BRUSH)));
		EndPaint(hwnd, &ps);
		return 0;
	}
	return DefWindowProcW(hwnd, msg, wParam, lParam);
}
} // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
	int argc = 0;
	auto** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
	ULONGLONG interfaceMs = argc > 1 ? _wtoi(argv[1]) : 2500;
	ULONGLONG desktopMs = argc > 2 ? _wtoi(argv[2]) : 4500;
	ULONGLONG readyMs = argc > 3 ? _wtoi(argv[3]) : 6500;
	LocalFree(argv);

	CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
	ii::splash::show();
	ii::splash::setShellPid(GetCurrentProcessId());
	WNDCLASSW wc {};
	wc.lpfnWndProc = fakeProc;
	wc.hInstance = instance;
	wc.lpszClassName = L"IiSplashPreviewFake";
	RegisterClassW(&wc);

	auto start = GetTickCount64();
	bool shownSmall = false;
	bool shownFull = false;
	bool readyWritten = false;
	MSG msg;
	for (;;) {
		while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
			TranslateMessage(&msg);
			DispatchMessageW(&msg);
		}
		auto t = GetTickCount64() - start;
		if (!shownSmall && t >= interfaceMs) {
			shownSmall = true;
			fake = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, wc.lpszClassName, L"", WS_POPUP, 0, 0, 40, 40, nullptr, nullptr, instance, nullptr);
			ShowWindow(fake, SW_SHOWNOACTIVATE);
		}
		if (!shownFull && t >= desktopMs) {
			shownFull = true;
			SetWindowPos(fake, nullptr, 0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN), SWP_NOZORDER | SWP_NOACTIVATE);
		}
		if (!readyWritten && t >= readyMs) {
			readyWritten = true;
			auto* f = CreateFileW((ii::dataDir() + L"\\shell-visual-ready").c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, 0, nullptr);
			if (f != INVALID_HANDLE_VALUE) CloseHandle(f);
		}
		if (readyWritten && !FindWindowW(L"IiSplash", nullptr)) break;
		if (t > 120000) break;
		MsgWaitForMultipleObjects(0, nullptr, FALSE, 5, QS_ALLINPUT);
	}
	ii::splash::close();
	if (fake) DestroyWindow(fake);
	return 0;
}
