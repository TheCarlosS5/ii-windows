#include "common.h"

#include <shellapi.h>

// Hiding the taskbar without patching Explorer:
//  1. switch it to auto-hide (ABM_SETSTATE) so it stops reserving screen space,
//  2. hide its windows (Shell_TrayWnd on the primary screen, Shell_SecondaryTrayWnd on others).
// Only (1) persists (Explorer saves it), so the original state is recorded in state.ini first
// and put back by restore(), the guard process and the rescue tools.

namespace ii::taskbar {

namespace {

std::vector<HWND> allTaskbars() {
	auto bars = findTopLevel(L"Shell_TrayWnd");
	auto secondary = findTopLevel(L"Shell_SecondaryTrayWnd");
	bars.insert(bars.end(), secondary.begin(), secondary.end());
	return bars;
}

UINT_PTR getState() {
	APPBARDATA abd {};
	abd.cbSize = sizeof(abd);
	return SHAppBarMessage(ABM_GETSTATE, &abd);
}

void setState(UINT_PTR value) {
	auto tray = FindWindowW(L"Shell_TrayWnd", nullptr);
	if (!tray) return;
	APPBARDATA abd {};
	abd.cbSize = sizeof(abd);
	abd.hWnd = tray;
	abd.lParam = static_cast<LPARAM>(value);
	SHAppBarMessage(ABM_SETSTATE, &abd);
}

} // namespace

bool isTaskbarWindow(HWND hwnd) {
	wchar_t cls[64];
	if (!GetClassNameW(hwnd, cls, 64)) return false;
	return wcscmp(cls, L"Shell_TrayWnd") == 0 || wcscmp(cls, L"Shell_SecondaryTrayWnd") == 0;
}

void hide() {
	if (!FindWindowW(L"Shell_TrayWnd", nullptr)) {
		log(L"taskbar: Shell_TrayWnd not found (Explorer not running?)");
		return;
	}

	// Record only once per "session of changes": if a previous run crashed without restoring,
	// state.ini still holds the real original value and must not be overwritten with ours.
	if (state::get(L"taskbarHidden", 0) == 0) {
		auto original = static_cast<int>(getState());
		state::set(L"taskbarOriginalState", original);
		log(L"taskbar: original appbar state %d", original);
	}
	state::set(L"taskbarHidden", 1);

	auto current = getState();
	if (!(current & ABS_AUTOHIDE)) setState(current | ABS_AUTOHIDE);

	reapply();
	log(L"taskbar: hidden");
}

void reapply() {
	for (auto* bar: allTaskbars()) {
		if (IsWindowVisible(bar)) ShowWindow(bar, SW_HIDE);
	}
}

void restore() {
	for (auto* bar: allTaskbars()) {
		if (!IsWindowVisible(bar)) ShowWindow(bar, SW_SHOWNA);
	}

	auto original = state::get(L"taskbarOriginalState", -1);
	if (state::get(L"taskbarHidden", 0) != 0 && original >= 0) {
		setState(static_cast<UINT_PTR>(original));
		log(L"taskbar: restored appbar state %d", original);
	}

	state::set(L"taskbarHidden", 0);
	log(L"taskbar: shown");
}

} // namespace ii::taskbar
