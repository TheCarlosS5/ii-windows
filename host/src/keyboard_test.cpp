// U02/P12: the keyboard hook's decisions (keyrouter.cpp), tested without a keyboard. Feeds the key
// sequences that matter and checks what is swallowed, what the shell is told, and when Start is masked.
#include <cstdio>
#include <string>

#include "keyrouter.h"

#include <windows.h>

using namespace ii::keyboard;

namespace {
int checks = 0;
int failures = 0;
void check(bool ok, const char* what) {
	++checks;
	if (!ok) {
		++failures;
		std::printf("FAIL: %s\n", what);
	}
}

// Which keys the "system" says are physically down (for healing lost key-ups).
bool g_down[256] {};
bool held(int vk, void*) { return vk >= 0 && vk < 256 && g_down[vk]; }

struct Keyboard {
	Router router {held, nullptr};
	Context context {true, false, false};

	Result press(unsigned vk) {
		g_down[vk] = true;
		return router.onKey(vk, true, context);
	}
	Result release(unsigned vk) {
		g_down[vk] = false;
		return router.onKey(vk, false, context);
	}
};

bool posted(const Result& r, Index index, bool pressed) {
	for (int i = 0; i < r.postCount; ++i) {
		if (r.posts[static_cast<size_t>(i)].index == index && r.posts[static_cast<size_t>(i)].pressed == pressed) return true;
	}
	return false;
}

bool postedName(const Result& r, const wchar_t* name) {
	for (int i = 0; i < r.postCount; ++i) {
		auto* n = nameOf(r.posts[static_cast<size_t>(i)].index);
		if (n && std::wstring(n) == name && r.posts[static_cast<size_t>(i)].pressed) return true;
	}
	return false;
}

void resetKeys() {
	for (auto& d: g_down) d = false;
}
} // namespace

int main() {
	// 1. A lone Win press opens search and masks the key-up, so Start stays closed.
	{
		resetKeys();
		Keyboard k;
		auto down = k.press(VK_LWIN);
		check(!down.swallow && posted(down, IDX_SEARCH, true) && posted(down, IDX_WSNUMBER, true), "Win down: passes, tells the shell the search key is held");
		auto up = k.release(VK_LWIN);
		check(up.swallow && up.maskWinRelease && up.winVk == VK_LWIN, "lone Win up: masked, the real key-up is swallowed");
		check(posted(up, IDX_SEARCH, false), "and the shell is told the search key was released");
	}

	// 2. Win+S: swallowed; Start is masked afterwards because ii took a key of the chord.
	{
		resetKeys();
		Keyboard k;
		k.press(VK_LWIN);
		auto s = k.press('S');
		check(s.swallow && postedName(s, L"searchToggle") && posted(s, IDX_INTERRUPT, true), "Win+S: swallowed, searchToggle, and the lone-Win search is interrupted");
		check(k.release('S').swallow, "the key-up of a swallowed key is swallowed too");
		auto up = k.release(VK_LWIN);
		check(up.maskWinRelease, "Win up after an ii chord is masked (no Start)");
	}

	// 3. Win+Z (not ours): passes, Windows keeps it, Start is NOT masked.
	{
		resetKeys();
		Keyboard k;
		k.press(VK_LWIN);
		auto z = k.press('Z');
		check(!z.swallow && posted(z, IDX_INTERRUPT, true), "Win+Z passes through, and interrupts the lone-Win search");
		k.release('Z');
		check(!k.release(VK_LWIN).maskWinRelease, "and Windows' own Win+Z leaves Win-up alone");
	}

	// 4. Win+number: desktops; with Shift moves; with Ctrl/Alt is blocked.
	{
		resetKeys();
		Keyboard k;
		k.press(VK_LWIN);
		auto three = k.press('3');
		check(three.swallow && posted(three, IDX_DESKTOP + 2, true), "Win+3 -> desktop 3");
		k.release('3');
		auto zero = k.press('0');
		check(posted(zero, IDX_DESKTOP + 9, true), "Win+0 -> desktop 10");
		k.release('0');
		k.press(VK_LSHIFT);
		check(posted(k.press('2'), IDX_MOVE + 1, true), "Win+Shift+2 moves the window to desktop 2");
		k.release('2');
		k.release(VK_LSHIFT);
		k.press(VK_LCONTROL);
		check(posted(k.press('4'), IDX_BLOCK, true), "Win+Ctrl+4 is blocked (it would open a hidden taskbar button)");
	}

	// 5. The new bindings of U02 and Print.
	{
		resetKeys();
		Keyboard k;
		k.press(VK_LWIN);
		check(postedName(k.press('I'), L"settingsOpen"), "Win+I -> ii settings");
		k.release('I');
		check(postedName(k.press('R'), L"searchToggle"), "Win+R -> ii search");
		k.release('R');
		check(postedName(k.press('T'), L"overviewWorkspacesToggle"), "Win+T -> window overview (no longer swallowed for nothing)");
		k.release('T');
		check(postedName(k.press('X'), L"sessionToggle"), "Win+X -> ii session menu");
		k.release('X');
		k.release(VK_LWIN);
		auto print = k.press(VK_SNAPSHOT);
		check(print.swallow && postedName(print, L"regionScreenshot"), "Print Screen -> region screenshot");
	}

	// 6. Combos without Win; modifiers tracked, left and right.
	{
		resetKeys();
		Keyboard k;
		k.press(VK_RCONTROL);
		k.press(VK_RMENU);
		auto end = k.press(VK_END);
		check(end.swallow && postedName(end, L"sessionToggle"), "Ctrl+Alt+End with the right-hand keys -> session menu");
		k.release(VK_END);
		k.release(VK_RMENU);
		auto plainEnd = k.press(VK_END);
		check(!plainEnd.swallow, "End with only Ctrl held passes");
	}

	// 7. Alt+F4 on Explorer's desktop opens the session menu; elsewhere it passes.
	{
		resetKeys();
		Keyboard k;
		k.press(VK_LMENU);
		check(!k.press(VK_F4).swallow, "Alt+F4 over an app passes");
		k.release(VK_F4);
		k.context.desktopInFront = true;
		auto f4 = k.press(VK_F4);
		check(f4.swallow && posted(f4, IDX_SESSION, true), "Alt+F4 over the desktop -> ii's session menu");
	}

	// 8. Ctrl+Esc opens search.
	{
		resetKeys();
		Keyboard k;
		k.press(VK_LCONTROL);
		auto esc = k.press(VK_ESCAPE);
		check(esc.swallow && posted(esc, IDX_SEARCH, true) && posted(esc, IDX_SEARCH, false), "Ctrl+Esc -> search");
	}

	// 9. The shell is not there: nothing is touched.
	{
		resetKeys();
		Keyboard k;
		k.context.shellPresent = false;
		auto win = k.press(VK_LWIN);
		check(win.postCount == 0, "no shell: the Win key tells nobody anything");
		check(!k.press('S').swallow, "no shell: Win+S is Windows'");
		check(!k.release(VK_LWIN).maskWinRelease, "no shell: Start opens as usual");
		check(!k.press(VK_SNAPSHOT).swallow, "no shell: Print Screen is Windows'");
	}

	// 10. A game is in front: ii's shortcuts step aside.
	{
		resetKeys();
		Keyboard k;
		k.context.yieldToForeground = true;
		auto win = k.press(VK_LWIN);
		check(win.postCount == 0 && !win.swallow, "yielding: Win down is not ii's");
		check(!k.press('S').swallow, "yielding: Win+S passes");
		check(!k.release(VK_LWIN).maskWinRelease, "yielding: Win up is not masked (Windows gets its Start key back)");
		check(!k.press(VK_SNAPSHOT).swallow, "yielding: Print Screen passes");
	}

	// 11. Our own replay never reaches the router (keyboard.cpp filters it); a lost key-up heals.
	{
		resetKeys();
		Keyboard k;
		k.press(VK_LWIN);
		g_down[VK_LWIN] = false; // the key-up never arrived
		auto s = k.press('S');   // so this S is a plain S
		check(!s.swallow, "after a lost Win key-up the next key is a plain key");
		check(!k.router.winIsDown(), "and the router no longer thinks Win is down");
		// the same for a stuck Ctrl
		resetKeys();
		Keyboard k2;
		k2.press(VK_LCONTROL);
		g_down[VK_LCONTROL] = false;
		auto end = k2.press(VK_END);
		check(!end.swallow, "a Ctrl whose key-up was lost does not turn End into Ctrl+...");
	}

	// 12. A modifier pressed after Win counts as 'not a lone Win press'.
	{
		resetKeys();
		Keyboard k;
		k.press(VK_LWIN);
		auto ctrl = k.press(VK_LCONTROL);
		check(!ctrl.swallow && posted(ctrl, IDX_INTERRUPT, true), "Win then Ctrl: passes and interrupts the search");
		k.release(VK_LCONTROL);
		check(!k.release(VK_LWIN).maskWinRelease, "so releasing Win does not open search");
	}

	// 13. Every shortcut of the table matches itself and only itself.
	{
		int n = 0;
		for (size_t i = 0; i < SHORTCUT_COUNT; ++i) {
			resetKeys();
			Keyboard k;
			const auto& s = SHORTCUTS[i];
			if (s.win) k.press(VK_LWIN);
			if (s.ctrl) k.press(VK_LCONTROL);
			if (s.alt) k.press(VK_LMENU);
			if (s.shift) k.press(VK_LSHIFT);
			auto r = k.press(s.vk);
			if (r.swallow && posted(r, static_cast<Index>(i), true)) ++n;
			else std::printf("  table entry %zu (%ls) did not match itself\n", i, s.name);
		}
		check(n == static_cast<int>(SHORTCUT_COUNT), "every entry of the generated table is reachable");
	}

	// 14. Reset forgets everything.
	{
		resetKeys();
		Keyboard k;
		k.press(VK_LWIN);
		k.press(VK_LCONTROL);
		k.router.reset();
		check(!k.router.winIsDown(), "reset clears the Win state");
	}

	// 15. Volume keys: ii takes them (press and release) so Windows shows no flyout of its own.
	{
		resetKeys();
		Keyboard k;
		k.context.volumeKeys = true;
		auto up = k.press(VK_VOLUME_UP);
		check(up.swallow && up.volumeVk == VK_VOLUME_UP, "volume up press: swallowed and handed to the host");
		check(k.release(VK_VOLUME_UP).swallow, "volume up release: swallowed too");
		auto mute = k.press(VK_VOLUME_MUTE);
		check(mute.swallow && mute.volumeVk == VK_VOLUME_MUTE, "mute press: swallowed and handed to the host");
		auto repeat = k.press(VK_VOLUME_DOWN);
		check(repeat.swallow && repeat.volumeVk == VK_VOLUME_DOWN && repeat.postCount == 0, "volume down: one step, nothing posted to the shell");

		Keyboard off;
		check(!off.press(VK_VOLUME_UP).swallow, "option off (default): Windows keeps the volume keys");
		Keyboard noShell;
		noShell.context.volumeKeys = true;
		noShell.context.shellPresent = false;
		check(!noShell.press(VK_VOLUME_UP).swallow && noShell.press(VK_VOLUME_UP).volumeVk == 0, "no shell: Windows keeps the volume keys");
		Keyboard game;
		game.context.volumeKeys = true;
		game.context.yieldToForeground = true;
		check(!game.press(VK_VOLUME_DOWN).swallow, "a game in front: Windows keeps the volume keys");
	}

	// ---- Which foreground makes ii step aside ----------------------------------------------
	{
		ForegroundRules rules;
		ForegroundFacts maximizedBrowser;
		maximizedBrowser.coversMonitor = true; // with the taskbar hidden a maximized window covers the monitor
		maximizedBrowser.hasCaption = true;
		maximizedBrowser.maximized = true;
		maximizedBrowser.exe = L"chrome.exe";
		check(!shouldYield(maximizedBrowser, rules), "a maximized browser does NOT make ii step aside (Win never falls back to Start)");

		ForegroundFacts maximizedApp = maximizedBrowser;
		maximizedApp.exe = L"code.exe";
		check(!shouldYield(maximizedApp, rules), "nor does any maximized window with a title bar");

		ForegroundFacts borderlessGame;
		borderlessGame.coversMonitor = true;
		borderlessGame.exe = L"somegame.exe";
		check(shouldYield(borderlessGame, rules), "a borderless fullscreen game makes ii step aside");

		ForegroundFacts browserF11 = borderlessGame;
		browserF11.exe = L"msedge.exe";
		check(!shouldYield(browserF11, rules), "a browser in F11 does not");

		ForegroundFacts exclusive;
		exclusive.exclusiveFullscreen = true;
		exclusive.exe = L"anything.exe";
		check(shouldYield(exclusive, rules), "exclusive fullscreen / presentation mode always does");

		ForegroundFacts desktop;
		desktop.isShellOrDesktop = true;
		desktop.coversMonitor = true;
		check(!shouldYield(desktop, rules), "ii's own windows and Explorer's desktop never do");

		ForegroundRules profile;
		profile.yieldExes = L"mygame.exe;other.exe";
		ForegroundFacts windowedGame;
		windowedGame.exe = L"mygame.exe";
		windowedGame.hasCaption = true;
		check(shouldYield(windowedGame, profile), "a program named in [yield] always does, even windowed");
		profile.keepExes = L"somegame.exe";
		check(!shouldYield(borderlessGame, profile), "a program named in [keep] never does");

		ForegroundRules geometry;
		geometry.policy = FullscreenPolicy::Geometry;
		check(shouldYield(maximizedBrowser, geometry), "policy 'geometry' is the old behaviour: anything covering the monitor");
		ForegroundRules never;
		never.policy = FullscreenPolicy::Never;
		check(!shouldYield(exclusive, never), "policy 'never': ii's keys always work");
		ForegroundRules neverButListed = never;
		neverButListed.yieldExes = L"mygame.exe";
		check(shouldYield(windowedGame, neverButListed), "an explicit [yield] entry is more specific than policy 'never' and wins");
	}

	std::printf("keyrouter: %d checks, %d failed\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
