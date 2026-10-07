#include <dwmapi.h>

#include "common.h"

// Win+D without Explorer's version (which raises the Windows desktop over ii's background):
// minimize every application window, remember which ones, restore them on the next press.

namespace ii::desktop {

namespace {

std::vector<HWND> minimizedByUs;

bool isAppWindow(HWND hwnd) {
	if (!IsWindowVisible(hwnd) || IsIconic(hwnd)) return false;
	if (GetAncestor(hwnd, GA_ROOT) != hwnd) return false;
	auto ex = GetWindowLongW(hwnd, GWL_EXSTYLE);
	if (!(ex & WS_EX_APPWINDOW)) {
		if (ex & (WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE)) return false;
		if (GetWindow(hwnd, GW_OWNER)) return false;
	}
	DWORD cloaked = 0;
	DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked, sizeof(cloaked));
	if (cloaked) return false;
	if (GetWindowTextLengthW(hwnd) == 0) return false;
	wchar_t cls[64] = {};
	GetClassNameW(hwnd, cls, 64);
	return wcscmp(cls, L"Progman") != 0 && wcscmp(cls, L"WorkerW") != 0 && wcscmp(cls, L"Shell_TrayWnd") != 0;
}

} // namespace

void toggleShowDesktop() {
	// Second press: bring back what we minimized (bottom-most first so z-order is kept).
	auto restored = false;
	for (auto it = minimizedByUs.rbegin(); it != minimizedByUs.rend(); ++it) {
		if (IsWindow(*it) && IsIconic(*it)) {
			ShowWindowAsync(*it, SW_RESTORE);
			restored = true;
		}
	}
	minimizedByUs.clear();
	if (restored) {
		log(L"show desktop: restored windows");
		return;
	}

	EnumWindows(
	    [](HWND hwnd, LPARAM) -> BOOL {
		    if (isAppWindow(hwnd)) minimizedByUs.push_back(hwnd); // z-order: top first
		    return TRUE;
	    },
	    0
	);
	for (auto* hwnd: minimizedByUs) ShowWindowAsync(hwnd, SW_SHOWMINNOACTIVE);
	log(L"show desktop: minimized %zu windows", minimizedByUs.size());
}

} // namespace ii::desktop
