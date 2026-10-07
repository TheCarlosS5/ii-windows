#include <array>

#include "common.h"

// Low-level keyboard hook mapping illogical-impulse's Super shortcuts onto the Windows key.
//
// Rules that keep Windows usable:
//  - The Win key itself is never swallowed, so Windows always knows it is held and its own
//    combos (Win+L, Win+D, Win+E, ...) keep working. Ctrl+Alt+Del never reaches hooks at all.
//  - Only combos in the table below are swallowed, and only while the shell is running
//    (its shortcut sink window exists) and the foreground app is not fullscreen.
//  - A lone Win press opens ii's search instead of Start: before Windows sees the Win key-up
//    we inject an unassigned key (vkE8), which tells Windows "this was a combo" so Start stays
//    closed. Without the shell, nothing is injected and Start opens as usual.
// The hook only posts messages; talking to the shell happens outside the hook callback.

namespace ii::keyboard {

namespace {

struct Shortcut {
	bool win, ctrl, alt, shift;
	UINT vk;
	const wchar_t* name;
};

// Names are illogical-impulse GlobalShortcut names (see its Hyprland keybinds).
constexpr std::array SHORTCUTS = {
    Shortcut {true, false, false, false, VK_TAB, L"overviewWorkspacesToggle"},
    Shortcut {true, false, false, false, 'V', L"overviewClipboardToggle"},
    Shortcut {true, false, false, false, VK_OEM_PERIOD, L"overviewEmojiToggle"},
    Shortcut {true, false, false, false, 'A', L"sidebarLeftToggle"},
    Shortcut {true, false, true, false, 'A', L"sidebarLeftToggleDetach"},
    Shortcut {true, false, false, false, 'B', L"sidebarLeftToggle"},
    Shortcut {true, false, false, false, 'O', L"sidebarLeftToggle"},
    Shortcut {true, false, false, false, 'N', L"sidebarRightToggle"},
    Shortcut {true, false, false, false, VK_OEM_2, L"cheatsheetToggle"},
    Shortcut {true, false, false, false, 'K', L"oskToggle"},
    Shortcut {true, false, false, false, 'M', L"mediaControlsToggle"},
    Shortcut {true, false, false, false, 'G', L"overlayToggle"},
    Shortcut {true, false, false, false, 'J', L"barToggle"},
    // Handled by ii-host itself ('@' prefix): Windows' own Win+D raises its desktop over
    // ii's wallpaper and widgets.
    Shortcut {true, false, false, false, 'D', L"@showDesktop"},
    // Ctrl+Alt+Del is the secure attention sequence on Windows; Ctrl+Alt+End is the
    // remote-desktop stand-in for it, so the session menu goes there.
    Shortcut {false, true, true, false, VK_END, L"sessionToggle"},
    Shortcut {true, true, false, false, 'T', L"wallpaperSelectorToggle"},
    Shortcut {true, true, true, false, 'T', L"wallpaperSelectorRandom"},
    Shortcut {true, true, false, true, 'D', L"toggleLightDark"},
    Shortcut {true, false, false, true, 'S', L"regionScreenshot"},
    Shortcut {true, false, false, true, 'A', L"regionSearch"},
    Shortcut {true, false, false, true, 'X', L"regionOcr"},
    Shortcut {true, false, false, true, 'T', L"screenTranslate"},
    Shortcut {true, false, false, true, 'R', L"regionRecord"},
    Shortcut {true, false, true, false, 'R', L"regionRecord"},
};

// Pseudo shortcuts driven by the Win key itself.
constexpr LPARAM IDX_SEARCH = 1000;      // searchToggleRelease: press on Win down, release on up
constexpr LPARAM IDX_INTERRUPT = 1001;   // searchToggleReleaseInterrupt: another key while held
constexpr LPARAM IDX_WSNUMBER = 1002;    // workspaceNumber: held while Win is down

constexpr ULONG_PTR OWN_INPUT_TAG = 0x11A1D00D;

HHOOK hook = nullptr;
HWND notify = nullptr;

bool winDown = false;
bool winSolo = false;
bool chordActive = false;   // shell handles this Win chord
bool swallowedInChord = false;
std::array<bool, 256> swallowedDown {};

bool keyHeld(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }

bool foregroundIsFullscreen() {
	auto* fg = GetForegroundWindow();
	if (!fg) return false;

	wchar_t cls[64] = {};
	GetClassNameW(fg, cls, 64);
	if (wcscmp(cls, L"Progman") == 0 || wcscmp(cls, L"WorkerW") == 0) return false;
	if (wcsncmp(cls, L"Qt", 2) == 0 && processIdOf(fg) == processIdOf(findShellSink())) return false;

	RECT rect;
	if (!GetWindowRect(fg, &rect)) return false;
	MONITORINFO info {};
	info.cbSize = sizeof(info);
	if (!GetMonitorInfoW(MonitorFromWindow(fg, MONITOR_DEFAULTTONEAREST), &info)) return false;

	return rect.left <= info.rcMonitor.left && rect.top <= info.rcMonitor.top
	    && rect.right >= info.rcMonitor.right && rect.bottom >= info.rcMonitor.bottom;
}

bool shellActive() { return findShellSink() != nullptr && !foregroundIsFullscreen(); }

void post(bool pressed, LPARAM index) {
	PostMessageW(notify, WM_II_SHORTCUT, pressed ? 1 : 0, index);
}

// Replays a Win key-up preceded by an unassigned key (vkE8), all injected in one SendInput so
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

const Shortcut* match(UINT vk, bool win) {
	auto ctrl = keyHeld(VK_CONTROL);
	auto alt = keyHeld(VK_MENU);
	auto shift = keyHeld(VK_SHIFT);
	for (const auto& s: SHORTCUTS) {
		if (s.vk == vk && s.win == win && s.ctrl == ctrl && s.alt == alt && s.shift == shift) return &s;
	}
	return nullptr;
}

LRESULT CALLBACK proc(int code, WPARAM wParam, LPARAM lParam) {
	if (code != HC_ACTION) return CallNextHookEx(hook, code, wParam, lParam);

	auto* key = reinterpret_cast<KBDLLHOOKSTRUCT*>(lParam);
	// Skip only our own replayed keys; other injected input (on-screen keyboard, automation)
	// is treated like a physical keyboard.
	if (key->dwExtraInfo == OWN_INPUT_TAG) return CallNextHookEx(hook, code, wParam, lParam);

	auto down = wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN;
	auto vk = key->vkCode;

	if (vk == VK_LWIN || vk == VK_RWIN) {
		if (down) {
			if (!winDown) {
				winDown = true;
				winSolo = true;
				swallowedInChord = false;
				chordActive = shellActive();
				if (chordActive) {
					post(true, IDX_SEARCH);
					post(true, IDX_WSNUMBER);
				}
			}
		} else if (winDown) {
			winDown = false;
			if (chordActive) {
				post(false, IDX_WSNUMBER);
				post(false, IDX_SEARCH);
				// Keep Start closed: for a lone press (we open search) and for chords whose
				// other key we swallowed (Windows would otherwise see a lone Win press).
				if (winSolo || swallowedInChord) {
					chordActive = false;
					releaseWinMasked(vk);
					return 1; // the real key-up is replayed after the mask key
				}
			}
			chordActive = false;
		}
		return CallNextHookEx(hook, code, wParam, lParam);
	}

	if (down && winDown && winSolo) {
		winSolo = false;
		if (chordActive) post(true, IDX_INTERRUPT);
	}

	if (!down) {
		if (vk < swallowedDown.size() && swallowedDown[vk]) {
			swallowedDown[vk] = false;
			return 1;
		}
		return CallNextHookEx(hook, code, wParam, lParam);
	}

	auto handled = winDown ? chordActive : (findShellSink() != nullptr && !foregroundIsFullscreen());
	if (!handled) return CallNextHookEx(hook, code, wParam, lParam);

	// Ctrl+Esc opens Start too.
	if (vk == VK_ESCAPE && !winDown && keyHeld(VK_CONTROL) && !keyHeld(VK_MENU) && !keyHeld(VK_SHIFT)) {
		post(true, IDX_SEARCH);
		post(false, IDX_SEARCH);
		swallowedDown[vk] = true;
		return 1;
	}

	if (const auto* s = match(vk, winDown)) {
		post(true, static_cast<LPARAM>(s - SHORTCUTS.data()));
		if (vk < swallowedDown.size()) swallowedDown[vk] = true;
		if (winDown) swallowedInChord = true;
		return 1;
	}

	return CallNextHookEx(hook, code, wParam, lParam);
}

} // namespace

bool install(HWND notifyWindow) {
	notify = notifyWindow;
	hook = SetWindowsHookExW(WH_KEYBOARD_LL, proc, GetModuleHandleW(nullptr), 0);
	if (!hook) {
		log(L"keyboard: SetWindowsHookEx failed (%lu)", GetLastError());
		return false;
	}
	log(L"keyboard: hook installed");
	return true;
}

void uninstall() {
	if (hook) UnhookWindowsHookEx(hook);
	hook = nullptr;
	log(L"keyboard: hook removed");
}

const wchar_t* shortcutName(LPARAM index) {
	switch (index) {
	case IDX_SEARCH: return L"searchToggleRelease";
	case IDX_INTERRUPT: return L"searchToggleReleaseInterrupt";
	case IDX_WSNUMBER: return L"workspaceNumber";
	default:
		if (index >= 0 && static_cast<size_t>(index) < SHORTCUTS.size()) return SHORTCUTS[index].name;
		return nullptr;
	}
}

} // namespace ii::keyboard
