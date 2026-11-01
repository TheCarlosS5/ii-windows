#include "keyrouter.h"

#include <windows.h>

#include <algorithm>
#include <atomic>
#include <cwctype>
#include <memory>
#include <mutex>

namespace ii::keyboard {

// --- the table in use (plan 2026-10-31, E16) ------------------------------------------------------------------------
namespace {

std::atomic<const std::vector<Shortcut>*> currentTable {nullptr};

const std::vector<Shortcut>& defaultTable() {
	static const std::vector<Shortcut> table(std::begin(DEFAULT_SHORTCUTS), std::end(DEFAULT_SHORTCUTS));
	return table;
}

std::wstring lower(std::wstring text) {
	for (auto& c: text) c = static_cast<wchar_t>(std::towlower(c));
	return text;
}

std::wstring trim(const std::wstring& text) {
	auto begin = text.find_first_not_of(L" \t");
	if (begin == std::wstring::npos) return {};
	auto end = text.find_last_not_of(L" \t");
	return text.substr(begin, end - begin + 1);
}

// Keys that may stand without Ctrl/Alt/Win: typing never produces them.
bool specialKey(unsigned vk) {
	return (vk >= VK_F1 && vk <= VK_F24) || vk == VK_SNAPSHOT || vk == VK_PAUSE || vk == VK_SCROLL;
}

unsigned keyCode(const std::wstring& name) {
	if (name.size() == 1) {
		auto c = static_cast<wchar_t>(std::towupper(name[0]));
		if ((c >= L'A' && c <= L'Z') || (c >= L'0' && c <= L'9')) return c;
		switch (c) {
		case L'.': return VK_OEM_PERIOD;
		case L',': return VK_OEM_COMMA;
		case L'/': return VK_OEM_2;
		case L'-': return VK_OEM_MINUS;
		case L'=': return VK_OEM_PLUS;
		case L';': return VK_OEM_1;
		case L'\'': return VK_OEM_7;
		case L'`': return VK_OEM_3;
		case L'[': return VK_OEM_4;
		case L']': return VK_OEM_6;
		case L'\\': return VK_OEM_5;
		default: return 0;
		}
	}
	if (name.size() >= 2 && name.size() <= 3 && name[0] == L'f') {
		auto n = _wtoi(name.c_str() + 1);
		if (n >= 1 && n <= 24) return VK_F1 + static_cast<unsigned>(n) - 1;
	}
	static const std::pair<const wchar_t*, unsigned> named[] = {
	    {L"tab", VK_TAB}, {L"space", VK_SPACE}, {L"enter", VK_RETURN}, {L"escape", VK_ESCAPE}, {L"esc", VK_ESCAPE},
	    {L"delete", VK_DELETE}, {L"del", VK_DELETE}, {L"insert", VK_INSERT}, {L"home", VK_HOME}, {L"end", VK_END},
	    {L"pageup", VK_PRIOR}, {L"pagedown", VK_NEXT}, {L"up", VK_UP}, {L"down", VK_DOWN}, {L"left", VK_LEFT},
	    {L"right", VK_RIGHT}, {L"print", VK_SNAPSHOT}, {L"printscreen", VK_SNAPSHOT}, {L"pause", VK_PAUSE},
	    {L"scrolllock", VK_SCROLL}, {L"period", VK_OEM_PERIOD}, {L"comma", VK_OEM_COMMA}, {L"slash", VK_OEM_2},
	    {L"minus", VK_OEM_MINUS}, {L"plus", VK_OEM_PLUS}, {L"backspace", VK_BACK},
	};
	for (const auto& [n, vk]: named)
		if (name == n) return vk;
	return 0;
}

} // namespace

ShortcutTable shortcuts() {
	const auto* table = currentTable.load(std::memory_order_acquire);
	if (!table) table = &defaultTable();
	return {table->data(), table->size()};
}

bool parseCombo(const std::wstring& text, Shortcut& out) {
	auto value = lower(trim(text));
	if (value.empty()) return false;
	bool win = false, ctrl = false, alt = false, shift = false;
	unsigned vk = 0;
	size_t start = 0;
	while (start <= value.size()) {
		auto plus = value.find(L'+', start);
		// "ctrl++" (the plus key itself): a '+' right after a separator is the key.
		if (plus == start && plus != std::wstring::npos) plus = value.find(L'+', start + 1);
		auto part = trim(value.substr(start, plus == std::wstring::npos ? std::wstring::npos : plus - start));
		if (part == L"win" || part == L"super" || part == L"meta") win = true;
		else if (part == L"ctrl" || part == L"control") ctrl = true;
		else if (part == L"alt") alt = true;
		else if (part == L"shift") shift = true;
		else {
			auto code = part == L"+" ? static_cast<unsigned>(VK_OEM_PLUS) : keyCode(part);
			if (code == 0 || vk != 0) return false; // unknown, or a second key
			vk = code;
		}
		if (plus == std::wstring::npos) break;
		start = plus + 1;
	}
	if (vk == 0) return false;
	if (!win && !ctrl && !alt && !specialKey(vk)) return false; // it would take normal typing
	out.win = win;
	out.ctrl = ctrl;
	out.alt = alt;
	out.shift = shift;
	out.vk = vk;
	return true;
}

size_t applyOverrides(const std::vector<std::pair<std::wstring, std::wstring>>& overrides, std::vector<std::wstring>* problems) {
	auto table = std::make_unique<std::vector<Shortcut>>(defaultTable());
	size_t applied = 0;
	auto problem = [&](const std::wstring& text) {
		if (problems) problems->push_back(text);
	};
	for (const auto& [rawId, rawCombo]: overrides) {
		auto id = lower(trim(rawId));
		auto combo = lower(trim(rawCombo));
		auto first = std::find_if(table->begin(), table->end(), [&](const Shortcut& s) { return id == s.id; });
		if (first == table->end()) {
			problem(id + L": no such action (or it cannot be changed)");
			continue;
		}
		if (combo == L"off" || combo == L"none") {
			table->erase(std::remove_if(table->begin(), table->end(), [&](const Shortcut& s) { return id == s.id; }), table->end());
			++applied;
			continue;
		}
		Shortcut keys {};
		if (!parseCombo(combo, keys)) {
			problem(id + L": \"" + combo + L"\" is not a combination ii can take");
			continue;
		}
		auto taken = std::find_if(table->begin(), table->end(), [&](const Shortcut& s) {
			return id != s.id && s.win == keys.win && s.ctrl == keys.ctrl && s.alt == keys.alt && s.shift == keys.shift && s.vk == keys.vk;
		});
		if (taken != table->end()) {
			problem(id + L": \"" + combo + L"\" is already " + taken->id);
			continue;
		}
		first->win = keys.win;
		first->ctrl = keys.ctrl;
		first->alt = keys.alt;
		first->shift = keys.shift;
		first->vk = keys.vk;
		// The action's other combinations go: it now has the one chosen.
		auto keep = &*first;
		table->erase(std::remove_if(table->begin(), table->end(), [&](const Shortcut& s) { return &s != keep && id == s.id; }), table->end());
		++applied;
	}
	// Old tables stay alive: the hook thread may be reading one right now (a few hundred bytes per change).
	static std::mutex lock;
	static std::vector<std::unique_ptr<std::vector<Shortcut>>> kept;
	std::lock_guard guard(lock);
	currentTable.store(table.get(), std::memory_order_release);
	kept.push_back(std::move(table));
	return applied;
}

const wchar_t* nameOf(Index index) {
	switch (index) {
	case IDX_SEARCH: return L"searchToggleRelease";
	case IDX_INTERRUPT: return L"searchToggleReleaseInterrupt";
	case IDX_WSNUMBER: return L"workspaceNumber";
	case IDX_BLOCK: return L"@block";
	case IDX_SESSION: return L"sessionToggle";
	case IDX_SWITCH_NEXT: return L"windowSwitcherNext";
	case IDX_SWITCH_PREV: return L"windowSwitcherPrevious";
	case IDX_SWITCH_PICK: return L"windowSwitcherPick";
	case IDX_SWITCH_CANCEL: return L"windowSwitcherCancel";
	case IDX_MEDIA_PLAY: return L"mediaPlayPause";
	case IDX_MEDIA_NEXT: return L"mediaNext";
	case IDX_MEDIA_PREV: return L"mediaPrevious";
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
		auto table = shortcuts();
		if (index >= 0 && static_cast<size_t>(index) < table.count) return table[static_cast<size_t>(index)].name;
		return nullptr;
	}
}

void Router::reset() {
	lctrl = rctrl = lalt = ralt = lshift = rshift = false;
	winDown = winSolo = chordActive = swallowedInChord = false;
	switching = maskAltUp = false;
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
	auto table = shortcuts();
	for (size_t i = 0; i < table.count; ++i) {
		const auto& s = table[i];
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

	// The media keys, opted in: ii's player and pill, not Windows' flyout. Off by default: with several players
	// Windows' own handling is the safer one.
	if ((vk == VK_MEDIA_PLAY_PAUSE || vk == VK_MEDIA_NEXT_TRACK || vk == VK_MEDIA_PREV_TRACK) && context.mediaKeys && context.shellPresent
	    && !context.yieldToForeground) {
		if (down) r.add(true, vk == VK_MEDIA_PLAY_PAUSE ? IDX_MEDIA_PLAY : vk == VK_MEDIA_NEXT_TRACK ? IDX_MEDIA_NEXT : IDX_MEDIA_PREV);
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
					r.loneWin = winSolo;
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

	// ii's Alt+Tab. Letting go of Alt (of both) picks the window shown. The app in front saw Alt go down but not the
	// Tab, so a bare Alt release would open its menu bar: after a Tab ii took, that release is masked like a Win one.
	if (isModifier && !down && (vk == VK_LMENU || vk == VK_RMENU || vk == VK_MENU) && !alt()) {
		if (switching) {
			switching = false;
			r.add(true, IDX_SWITCH_PICK);
		}
		if (maskAltUp) {
			maskAltUp = false;
			r.maskAltRelease = true;
			r.altVk = vk;
			r.swallow = true; // the real key-up is replayed after the mask key
		}
		if (r.postCount > 0 || r.swallow) return r;
	}
	if (switching && down && !isModifier && !alt()) {
		// Alt is up but its release never came (secure desktop, a lost event): the switcher must not stay open.
		switching = false;
		maskAltUp = false;
		r.add(true, IDX_SWITCH_CANCEL);
	}
	if (switching && down && !isModifier) {
		Index step = -1;
		if (vk == VK_TAB) step = shift() ? IDX_SWITCH_PREV : IDX_SWITCH_NEXT;
		else if (vk == VK_LEFT) step = IDX_SWITCH_PREV;
		else if (vk == VK_RIGHT) step = IDX_SWITCH_NEXT;
		else if (vk == VK_ESCAPE || vk == VK_RETURN) {
			switching = false;
			step = vk == VK_ESCAPE ? IDX_SWITCH_CANCEL : IDX_SWITCH_PICK;
		}
		if (step >= 0) {
			r.add(true, step);
			swallowedDown[vk] = true;
			r.swallow = true;
			return r;
		}
	}
	if (!switching && down && vk == VK_TAB && alt() && !ctrl() && !winDown && context.shellPresent && context.shellResponsive
	    && !context.yieldToForeground) {
		switching = true;
		maskAltUp = true;
		r.add(true, shift() ? IDX_SWITCH_PREV : IDX_SWITCH_NEXT);
		swallowedDown[VK_TAB] = true;
		r.swallow = true;
		return r;
	}

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

bool shouldUnhook(const ForegroundFacts& facts, const ForegroundRules& rules) {
	if (facts.isShellOrDesktop || facts.exe.empty()) return false;
	if (listed(rules.unhookExes, facts.exe)) return true;
	return !listed(rules.unhookExes, L"nodefaults") && listed(UNHOOK_BY_DEFAULT, facts.exe);
}

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
