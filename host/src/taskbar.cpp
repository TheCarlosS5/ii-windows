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
	std::vector<HWND> bars;
	if (auto* tray = explorerTray()) bars.push_back(tray);
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
	auto tray = explorerTray();
	if (!tray) return;
	APPBARDATA abd {};
	abd.cbSize = sizeof(abd);
	abd.hWnd = tray;
	abd.lParam = static_cast<LPARAM>(value);
	SHAppBarMessage(ABM_SETSTATE, &abd);
}

// ABM_SETSTATE only changes Explorer's live state; it saves it to StuckRects3 whenever it next
// feels like it (possibly while ours is active). After a restore, write the restored auto-hide
// bit there too, so an Explorer crash or logoff can't bring back the hidden state.
void persistAutoHide(bool autoHide) {
	HKEY key = nullptr;
	if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StuckRects3", 0, KEY_QUERY_VALUE | KEY_SET_VALUE, &key) != ERROR_SUCCESS) {
		return;
	}
	BYTE data[256];
	DWORD size = sizeof(data);
	DWORD type = 0;
	if (RegQueryValueExW(key, L"Settings", nullptr, &type, data, &size) == ERROR_SUCCESS && type == REG_BINARY && size > 8) {
		auto wanted = static_cast<BYTE>(autoHide ? (data[8] | 0x01) : (data[8] & ~0x01));
		if (wanted != data[8]) {
			data[8] = wanted;
			RegSetValueExW(key, L"Settings", 0, REG_BINARY, data, size);
			log(L"taskbar: saved auto-hide=%d to StuckRects3", autoHide ? 1 : 0);
		}
	}
	RegCloseKey(key);
}

} // namespace

bool isTaskbarWindow(HWND hwnd) {
	wchar_t cls[64];
	if (!GetClassNameW(hwnd, cls, 64)) return false;
	return wcscmp(cls, L"Shell_TrayWnd") == 0 || wcscmp(cls, L"Shell_SecondaryTrayWnd") == 0;
}

void hide() {
	if (!explorerTray()) {
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
		persistAutoHide((original & ABS_AUTOHIDE) != 0);
		log(L"taskbar: restored appbar state %d", original);
	}

	state::set(L"taskbarHidden", 0);
	log(L"taskbar: shown");
}

} // namespace ii::taskbar
