#pragma once

// The decisions of ii-host's keyboard hook, with no Windows calls in them so they can be tested:
// which keys ii swallows, which it lets through, what it tells the shell, and when a lone Win key
// must be masked so Windows' Start menu stays closed.
//
// The hook callback must stay cheap and must never wait on anything (Windows silently drops a hook
// that is slow). So it only feeds events in here, together with a Context that other code keeps
// up to date outside the hook (is the shell there, is a game in front), and acts on the Result.

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h> // the VK_ constants of the generated table

#include <array>
#include <cstdint>
#include <string>

namespace ii::keyboard {

using Index = intptr_t; // what the host receives with WM_II_SHORTCUT (an LPARAM)

struct Shortcut {
	bool win, ctrl, alt, shift;
	unsigned vk;
	const wchar_t* name;
};

// Generated from shared/actions.json by tools/dev/gen-actions.py (see docs/ATAJOS.md).
inline constexpr Shortcut SHORTCUTS[] = {
#include "shortcuts_table.inc"
};
inline constexpr size_t SHORTCUT_COUNT = sizeof(SHORTCUTS) / sizeof(SHORTCUTS[0]);

// Pseudo shortcuts driven by the Win key itself and by specific keys.
inline constexpr Index IDX_SEARCH = 1000;      // searchToggleRelease: press on Win down, release on up
inline constexpr Index IDX_INTERRUPT = 1001;   // searchToggleReleaseInterrupt: another key while held
inline constexpr Index IDX_WSNUMBER = 1002;    // workspaceNumber: held while Win is down
inline constexpr Index IDX_DESKTOP = 1100;     // + 0..9: Win+number
inline constexpr Index IDX_MOVE = 1110;        // + 0..9: Win+Shift+number
inline constexpr Index IDX_BLOCK = 1200;       // a Win combination that would open a hidden taskbar button
inline constexpr Index IDX_SESSION = 1201;     // Alt+F4 on Explorer's desktop: ii's session menu

const wchar_t* nameOf(Index index);

// What is going on around the keyboard, kept current outside the hook.
struct Context {
	bool shellPresent = false;      // the shell's shortcut sink window exists
	bool yieldToForeground = false; // a game / exclusive fullscreen app is in front: ii's shortcuts step aside
	bool desktopInFront = false;    // Explorer's own desktop is the foreground window (Alt+F4 there opens ii's session menu)
	bool volumeKeys = false;        // ii takes the volume keys (Windows would also show its own volume flyout)
};

struct Post {
	bool pressed;
	Index index;
};

struct Result {
	bool swallow = false;       // do not pass this event on
	bool maskWinRelease = false; // replay this Win key-up behind an unassigned key (no Start menu), and swallow the real one
	unsigned winVk = 0;
	unsigned volumeVk = 0;       // a volume key went down and ii handles it: the host changes the volume
	std::array<Post, 4> posts {};
	int postCount = 0;
	void add(bool pressed, Index index) {
		if (postCount < static_cast<int>(posts.size())) posts[static_cast<size_t>(postCount++)] = {pressed, index};
	}
};

// Is this key physically down right now (GetAsyncKeyState). Used only to heal a lost key-up/down,
// never to read the state of the very key being processed (the system has not updated it yet).
using HeldFn = bool (*)(int vk, void* user);

class Router {
public:
	Router(HeldFn held, void* user): held(held), user(user) {}

	// Feed one key event (not our own replayed input). vk is the Windows virtual-key code.
	Result onKey(unsigned vk, bool down, const Context& context);
	// Forget everything: after a lock, a session switch, a desktop change.
	void reset();

	[[nodiscard]] bool winIsDown() const { return winDown; }

private:
	bool modifier(unsigned vk, bool down); // tracks Ctrl/Alt/Shift; true if vk was one
	void healModifiers();
	Index match(unsigned vk, bool win) const; // index into SHORTCUTS, or -1

	HeldFn held;
	void* user;
	// Own record of the modifiers (left/right separately): the hook sees each event in order.
	bool lctrl = false, rctrl = false, lalt = false, ralt = false, lshift = false, rshift = false;
	bool winDown = false;
	bool winSolo = false;
	bool chordActive = false;       // ii handles this Win chord
	bool swallowedInChord = false;
	std::array<bool, 256> swallowedDown {};
	[[nodiscard]] bool ctrl() const { return lctrl || rctrl; }
	[[nodiscard]] bool alt() const { return lalt || ralt; }
	[[nodiscard]] bool shift() const { return lshift || rshift; }
};

// When do ii's shortcuts step aside for the app in front? Pure decision on facts the host gathers.
enum class FullscreenPolicy { Auto, Geometry, Never };

struct ForegroundFacts {
	bool isShellOrDesktop = false;  // ii's own window, Explorer's desktop, the taskbar
	bool exclusiveFullscreen = false; // Shell says: D3D exclusive fullscreen or presentation mode
	bool coversMonitor = false;
	bool hasCaption = false;        // a title bar: an ordinary window, even a maximized one
	bool maximized = false;
	std::wstring exe;               // lower-case file name of the process, e.g. "chrome.exe"
};

struct ForegroundRules {
	FullscreenPolicy policy = FullscreenPolicy::Auto;
	std::wstring yieldExes; // ';'-separated, lower case: always step aside for these (a game profile)
	std::wstring keepExes;  // ';'-separated, lower case: never step aside for these
	bool windowsVolumeKeys = false; // [audio] volumekeys = windows: leave the volume keys (and Windows' flyout) alone
};

// Auto (default): step aside for exclusive fullscreen / presentation mode and for borderless
// fullscreen windows, except browsers and other apps that are routinely "fullscreen" but where the
// user still wants ii's keys. A maximized window with a title bar never makes ii step aside.
// Geometry (the old behaviour): any window covering the monitor. Never: ii's shortcuts always work.
bool shouldYield(const ForegroundFacts& facts, const ForegroundRules& rules);

} // namespace ii::keyboard
