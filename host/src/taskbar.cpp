#include "common.h"

#include <shellapi.h>

#include <algorithm>
#include <string>

// Hiding the taskbar without patching Explorer:
//  1. switch it to auto-hide (ABM_SETSTATE) so it stops reserving screen space,
//  2. hide its windows (Shell_TrayWnd on the primary screen, Shell_SecondaryTrayWnd on others),
//     and give them an empty window region: Explorer shows them again now and then (switching
//     virtual desktops, auto-hide reveal), and hiding them again only happens after the fact.
//     With no region there is nothing to see or click meanwhile. Not persistent either: a new
//     Explorer window has its own. Each bar's original region (none, or a rectangle: Windows
//     uses both) is recorded in state.ini (taskbarRgn<i>*, bars ordered by position), and
//     restore() and the rescue tools put exactly that back. Bars with any other region shape are
//     only hidden.
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

// Explorer's bars in a stable order (by position), so records match across processes.
std::vector<HWND> orderedTaskbars() {
	auto bars = allTaskbars();
	std::sort(bars.begin(), bars.end(), [](HWND a, HWND b) {
		RECT ra {};
		RECT rb {};
		GetWindowRect(a, &ra);
		GetWindowRect(b, &rb);
		return ra.left != rb.left ? ra.left < rb.left : ra.top < rb.top;
	});
	return bars;
}

std::wstring regionKey(size_t index, const wchar_t* part) {
	return L"taskbarRgn" + std::to_wstring(index) + part;
}

// Records each bar's region once per session (like the auto-hide state). Type: 0 none,
// 2 rectangle, 3 other (left alone), -1 not recorded.
void recordRegions() {
	auto bars = orderedTaskbars();
	for (size_t i = 0; i < bars.size(); ++i) {
		if (state::get(regionKey(i, L"Type").c_str(), -1) != -1) continue;
		RECT box {};
		auto type = GetWindowRgnBox(bars[i], &box);
		if (type == NULLREGION) continue; // already ours: a previous run's leftover
		auto recorded = type == ERROR ? 0 : (type == SIMPLEREGION ? 2 : 3);
		state::set(regionKey(i, L"L").c_str(), box.left);
		state::set(regionKey(i, L"T").c_str(), box.top);
		state::set(regionKey(i, L"R").c_str(), box.right);
		state::set(regionKey(i, L"B").c_str(), box.bottom);
		state::set(regionKey(i, L"Type").c_str(), recorded);
		log(L"taskbar: bar %d original region type %d", static_cast<int>(i), recorded);
	}
}

void restoreRegions() {
	auto bars = orderedTaskbars();
	for (size_t i = 0; i < bars.size(); ++i) {
		auto type = state::get(regionKey(i, L"Type").c_str(), -1);
		RECT box {};
		if (type == 2) {
			auto* region = CreateRectRgn(
			    state::get(regionKey(i, L"L").c_str(), 0),
			    state::get(regionKey(i, L"T").c_str(), 0),
			    state::get(regionKey(i, L"R").c_str(), 0),
			    state::get(regionKey(i, L"B").c_str(), 0)
			);
			SetWindowRgn(bars[i], region, TRUE);
		} else if (type == 0 || GetWindowRgnBox(bars[i], &box) == NULLREGION) {
			SetWindowRgn(bars[i], nullptr, TRUE);
		}
		state::set(regionKey(i, L"Type").c_str(), -1);
	}
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
	recordRegions();

	auto current = getState();
	if (!(current & ABS_AUTOHIDE)) setState(current | ABS_AUTOHIDE);

	reapply();
	log(L"taskbar: hidden");
}

// Windows 11's Start button is a popup OWNED by the taskbar window (class "Button", title "Inicio"/"Start"). Hiding the
// taskbar hides its owned windows only at that moment: a Start button created later (Explorer restarted, the
// taskbar rebuilt) stays on screen, floating over ii's dock. Those popups are hidden with the bar and shown with it.
std::vector<HWND> trayPopups(HWND bar) {
	struct Context {
		HWND bar;
		std::vector<HWND> found;
	} context {bar, {}};
	EnumWindows([](HWND hwnd, LPARAM data) -> BOOL {
		auto* c = reinterpret_cast<Context*>(data); // NOLINT
		if (GetWindow(hwnd, GW_OWNER) != c->bar) return TRUE;
		wchar_t cls[32] {};
		GetClassNameW(hwnd, cls, 32);
		if (wcscmp(cls, L"Button") == 0) c->found.push_back(hwnd);
		return TRUE;
	}, reinterpret_cast<LPARAM>(&context)); // NOLINT
	return context.found;
}

void conceal(HWND bar) {
	RECT box {};
	auto type = GetWindowRgnBox(bar, &box);
	// No region or a rectangle (both recorded by recordRegions): make it empty.
	if (state::get(L"taskbarHidden", 0) != 0 && (type == ERROR || type == SIMPLEREGION)) {
		recordRegions();
		SetWindowRgn(bar, CreateRectRgn(0, 0, 0, 0), FALSE);
	}
	if (IsWindowVisible(bar)) ShowWindow(bar, SW_HIDE);
	if (state::get(L"taskbarHidden", 0) != 0) {
		for (auto* popup: trayPopups(bar)) {
			if (IsWindowVisible(popup)) ShowWindow(popup, SW_HIDE);
		}
	}
}

void reapply() {
	for (auto* bar: allTaskbars()) conceal(bar);
}

void restore(bool force) {
	if (!force && state::get(L"taskbarHidden", 0) == 0) {
		log(L"taskbar: not hidden by this ii, leaving it as it is");
		return;
	}
	restoreRegions();
	for (auto* bar: allTaskbars()) {
		if (!IsWindowVisible(bar)) ShowWindow(bar, SW_SHOWNA);
		for (auto* popup: trayPopups(bar)) {
			if (!IsWindowVisible(popup)) ShowWindow(popup, SW_SHOWNA);
		}
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
