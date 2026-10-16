#include "keyrouter.h"

#include <windows.h>

#include <algorithm>

namespace ii::keyboard {

const wchar_t* nameOf(Index index) {
	switch (index) {
	case IDX_SEARCH: return L"searchToggleRelease";
	case IDX_INTERRUPT: return L"searchToggleReleaseInterrupt";
	case IDX_WSNUMBER: return L"workspaceNumber";
	case IDX_BLOCK: return L"@block";
	case IDX_SESSION: return L"sessionToggle";
	default:
		if (index >= IDX_DESKTOP && index < IDX_DESKTOP + 10) {
			static const wchar_t* desktops[] = {
			    L"hl:workspace 1", L"hl:workspace 2", L"hl:workspace 3", L"hl:workspace 4", L"hl:workspace 5",
			    L"hl:workspace 6", L"hl:workspace 7", L"hl:workspace 8", L"hl:workspace 9", L"hl:workspace 10",
			};
			return desktops[index - IDX_DESKTOP];
		}
		if (index >= IDX_MOVE && index < IDX_MOVE + 10) {
			static const wchar_t* moves[] = {
			    L"hl:movetoworkspacesilent 1", L"hl:movetoworkspacesilent 2", L"hl:movetoworkspacesilent 3",
			    L"hl:movetoworkspacesilent 4", L"hl:movetoworkspacesilent 5", L"hl:movetoworkspacesilent 6",
			    L"hl:movetoworkspacesilent 7", L"hl:movetoworkspacesilent 8", L"hl:movetoworkspacesilent 9",
			    L"hl:movetoworkspacesilent 10",
			};
			return moves[index - IDX_MOVE];
		}
		if (index >= 0 && static_cast<size_t>(index) < SHORTCUT_COUNT) return SHORTCUTS[static_cast<size_t>(index)].name;
		return nullptr;
	}
}

void Router::reset() {
	lctrl = rctrl = lalt = ralt = lshift = rshift = false;
	winDown = winSolo = chordActive = swallowedInChord = false;
	swallowedDown.fill(false);
}

// Left and right variants arrive as VK_LCONTROL etc. in a low-level hook.
bool Router::modifier(unsigned vk, bool down) {
	switch (vk) {
	case VK_LCONTROL: lctrl = down; return true;
	case VK_RCONTROL: rctrl = down; return true;
	case VK_CONTROL: lctrl = down; return true;
	case VK_LMENU: lalt = down; return true;
	case VK_RMENU: ralt = down; return true;
	case VK_MENU: lalt = down; return true;
	case VK_LSHIFT: lshift = down; return true;
	case VK_RSHIFT: rshift = down; return true;
	case VK_SHIFT: lshift = down; return true;
	default: return false;
	}
}

// A key-up we never saw (secure desktop, a session switch, a skipped hook call) would leave a
// modifier "down" for ever. Before reading modifiers for a real key, trust the system if it says
// the modifier is up. (Not used for the key being processed: its async state is not updated yet.)
void Router::healModifiers() {
	if (!held) return;
	if ((lctrl || rctrl) && !held(VK_LCONTROL, user) && !held(VK_RCONTROL, user)) lctrl = rctrl = false;
	if ((lalt || ralt) && !held(VK_LMENU, user) && !held(VK_RMENU, user)) lalt = ralt = false;
	if ((lshift || rshift) && !held(VK_LSHIFT, user) && !held(VK_RSHIFT, user)) lshift = rshift = false;
}

Index Router::match(unsigned vk, bool win) const {
	for (size_t i = 0; i < SHORTCUT_COUNT; ++i) {
		const auto& s = SHORTCUTS[i];
		if (s.vk == vk && s.win == win && s.ctrl == ctrl() && s.alt == alt() && s.shift == shift()) return static_cast<Index>(i);
	}
	return -1;
}

Result Router::onKey(unsigned vk, bool down, const Context& context) {
	Result r;

	// The volume keys: ii changes the volume itself and shows its own indicator. If Windows saw the key
	// it would change the volume too and show its flyout next to ii's. Both the press and the release
	// are swallowed; with no shell (or a game in front) Windows keeps the keys.
	if ((vk == VK_VOLUME_UP || vk == VK_VOLUME_DOWN || vk == VK_VOLUME_MUTE) && context.volumeKeys && context.shellPresent
	    && !context.yieldToForeground) {
		if (down) r.volumeVk = vk;
		r.swallow = true;
		return r;
	}

	if (vk == VK_LWIN || vk == VK_RWIN) {
		if (down) {
			if (!winDown) {
				winDown = true;
				winSolo = true;
				swallowedInChord = false;
				chordActive = context.shellPresent && !context.yieldToForeground;
				if (chordActive) {
					r.add(true, IDX_SEARCH);
					r.add(true, IDX_WSNUMBER);
				}
			}
		} else if (winDown) {
			winDown = false;
			if (chordActive) {
				r.add(false, IDX_WSNUMBER);
				r.add(false, IDX_SEARCH);
				// Keep Start closed: for a lone press (ii opens search) and for chords whose other key
				// ii swallowed (Windows would otherwise see a lone Win press).
				if (winSolo || swallowedInChord) {
					chordActive = false;
					r.maskWinRelease = true;
					r.winVk = vk;
					r.swallow = true; // the real key-up is replayed after the mask key
					return r;
				}
			}
			chordActive = false;
		}
		return r;
	}

	auto isModifier = modifier(vk, down);

	// A Win key-up can get lost (secure desktop, a virtual desktop switch, a skipped hook call).
	// Then every later key would count as Win+key and open panels while typing: trust the real key
	// state over ours.
	if (down && winDown && held && !held(VK_LWIN, user) && !held(VK_RWIN, user)) {
		winDown = false;
		chordActive = false;
		winSolo = false;
	}
	// The same for Ctrl/Alt/Shift, but only for real keys: the async state of the modifier being
	// pressed right now has not been updated by the time the hook sees it.
	if (down && !isModifier) healModifiers();

	// Any other key while Win is held (a modifier too) means it was not a lone press.
	if (down && winDown && winSolo) {
		winSolo = false;
		if (chordActive) r.add(true, IDX_INTERRUPT);
	}
	if (isModifier) return r; // modifiers always go through

	if (!down) {
		if (vk < swallowedDown.size() && swallowedDown[vk]) {
			swallowedDown[vk] = false;
			r.swallow = true;
		}
		return r;
	}

	auto handled = winDown ? chordActive : (context.shellPresent && !context.yieldToForeground);
	if (!handled) return r;

	// Win+number: desktops (IDX_DESKTOP). With Ctrl/Alt Windows would use the hidden taskbar's buttons.
	if (winDown && vk >= '0' && vk <= '9') {
		auto n = vk == '0' ? 9 : static_cast<Index>(vk - '1');
		r.add(true, ctrl() || alt() ? IDX_BLOCK : shift() ? IDX_MOVE + n : IDX_DESKTOP + n);
		swallowedDown[vk] = true;
		swallowedInChord = true;
		r.swallow = true;
		return r;
	}

	// Alt+F4 with Explorer's own desktop in front shows Windows' "Shut Down Windows" dialog.
	if (vk == VK_F4 && !winDown && alt() && !ctrl() && !shift() && context.desktopInFront) {
		r.add(true, IDX_SESSION);
		r.add(false, IDX_SESSION);
		swallowedDown[vk] = true;
		r.swallow = true;
		return r;
	}

	// Ctrl+Esc opens Start too.
	if (vk == VK_ESCAPE && !winDown && ctrl() && !alt() && !shift()) {
		r.add(true, IDX_SEARCH);
		r.add(false, IDX_SEARCH);
		swallowedDown[vk] = true;
		r.swallow = true;
		return r;
	}

	if (auto found = match(vk, winDown); found >= 0) {
		r.add(true, found);
		if (vk < swallowedDown.size()) swallowedDown[vk] = true;
		if (winDown) swallowedInChord = true;
		r.swallow = true;
		return r;
	}
	return r;
}

namespace {

bool listed(const std::wstring& list, const std::wstring& exe) {
	if (exe.empty() || list.empty()) return false;
	size_t start = 0;
	while (start <= list.size()) {
		auto end = list.find(L';', start);
		auto item = list.substr(start, end == std::wstring::npos ? std::wstring::npos : end - start);
		if (!item.empty() && item == exe) return true;
		if (end == std::wstring::npos) break;
		start = end + 1;
	}
	return false;
}

// Apps that are routinely "fullscreen" (F11, a video) where ii's keys are still wanted.
const wchar_t* const KEEP_BY_DEFAULT = L"chrome.exe;msedge.exe;firefox.exe;brave.exe;opera.exe;vivaldi.exe;arc.exe;zen.exe;librewolf.exe;explorer.exe";

} // namespace

bool shouldYield(const ForegroundFacts& facts, const ForegroundRules& rules) {
	if (facts.isShellOrDesktop) return false;
	if (listed(rules.keepExes, facts.exe)) return false;
	if (listed(rules.yieldExes, facts.exe)) return true;
	switch (rules.policy) {
	case FullscreenPolicy::Never: return false;
	case FullscreenPolicy::Geometry: return facts.coversMonitor;
	case FullscreenPolicy::Auto:
		if (facts.exclusiveFullscreen) return true;
		if (listed(KEEP_BY_DEFAULT, facts.exe)) return false;
		return facts.coversMonitor && !facts.hasCaption && !facts.maximized;
	}
	return false;
}

} // namespace ii::keyboard
