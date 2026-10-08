// ydotool for Windows (ii-shim): the on-screen keyboard and "superpaste" press keys through it.
//
//   ydotool key [--key-delay N] <code>:<1|0> ...   Linux input key codes, pressed (1) / released (0)
//   ydotool type [--key-delay N] <text>            types the text (Unicode)
//
// Linux key codes 1-83 are the PC's set-1 scan codes; the others map to extended (E0) scan codes.
// Keys go through SendInput as scan codes, like a real keyboard, so Windows (and ii-host's
// shortcut hook) treat them as typed. Releases of keys that are not down are skipped: ii releases
// all 249 codes at once, and a lone Windows-key release could open Start.

#include <algorithm>
#include <string>
#include <vector>

#include <windows.h>

namespace {

struct Scan {
	WORD code = 0;
	bool extended = false;
};

Scan scanOf(int key) {
	if (key >= 1 && key <= 83) return {static_cast<WORD>(key), false};
	switch (key) {
	case 86: return {0x56, false}; // the extra key on ISO keyboards (<>)
	case 87: return {0x57, false}; // F11
	case 88: return {0x58, false}; // F12
	case 96: return {0x1C, true};  // keypad Enter
	case 97: return {0x1D, true};  // right Ctrl
	case 98: return {0x35, true};  // keypad /
	case 99: return {0x37, true};  // Print Screen
	case 100: return {0x38, true}; // right Alt (AltGr)
	case 102: return {0x47, true}; // Home
	case 103: return {0x48, true}; // Up
	case 104: return {0x49, true}; // Page Up
	case 105: return {0x4B, true}; // Left
	case 106: return {0x4D, true}; // Right
	case 107: return {0x4F, true}; // End
	case 108: return {0x50, true}; // Down
	case 109: return {0x51, true}; // Page Down
	case 110: return {0x52, true}; // Insert
	case 111: return {0x53, true}; // Delete
	case 113: return {0x20, true}; // Mute
	case 114: return {0x2E, true}; // Volume down
	case 115: return {0x30, true}; // Volume up
	case 125: return {0x5B, true}; // left Windows key
	case 126: return {0x5C, true}; // right Windows key
	case 127: return {0x5D, true}; // Menu
	default: return {};
	}
}

bool isDown(Scan scan) {
	auto vk = MapVirtualKeyW(scan.extended ? (0xE000u | scan.code) : scan.code, MAPVK_VSC_TO_VK_EX);
	return vk != 0 && (GetAsyncKeyState(static_cast<int>(vk)) & 0x8000) != 0;
}

INPUT keyInput(Scan scan, bool down) {
	INPUT in {};
	in.type = INPUT_KEYBOARD;
	in.ki.wScan = scan.code;
	in.ki.dwFlags = KEYEVENTF_SCANCODE | (scan.extended ? KEYEVENTF_EXTENDEDKEY : 0) | (down ? 0 : KEYEVENTF_KEYUP);
	return in;
}

void send(std::vector<INPUT>& inputs, int delayMs) {
	if (inputs.empty()) return;
	if (delayMs <= 0) {
		SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT));
		return;
	}
	for (auto& in: inputs) {
		SendInput(1, &in, sizeof(INPUT));
		Sleep(static_cast<DWORD>(delayMs));
	}
}

} // namespace

int ydotool(const std::vector<std::wstring>& args) {
	if (args.empty()) return 2;
	auto command = args[0];
	int delay = 0;
	std::vector<std::wstring> rest;
	for (size_t i = 1; i < args.size(); ++i) {
		if ((args[i] == L"--key-delay" || args[i] == L"-d") && i + 1 < args.size()) delay = _wtoi(args[++i].c_str());
		else if (args[i].rfind(L"--key-delay=", 0) == 0) delay = _wtoi(args[i].c_str() + 12);
		else rest.push_back(args[i]);
	}

	std::vector<INPUT> inputs;
	if (command == L"key") {
		std::vector<int> pressed; // keys this command presses: their release always goes out
		for (const auto& item: rest) {
			auto colon = item.find(L':');
			if (colon == std::wstring::npos) continue;
			auto key = _wtoi(item.substr(0, colon).c_str());
			auto scan = scanOf(key);
			if (scan.code == 0) continue;
			auto down = _wtoi(item.c_str() + colon + 1) != 0;
			auto pressedHere = std::find(pressed.begin(), pressed.end(), key) != pressed.end();
			if (down) pressed.push_back(key);
			else if (!pressedHere && !isDown(scan)) continue;
			inputs.push_back(keyInput(scan, down));
		}
	} else if (command == L"type") {
		std::wstring text;
		for (const auto& word: rest) text += (text.empty() ? L"" : L" ") + word;
		for (auto ch: text) {
			for (auto up: {false, true}) {
				INPUT in {};
				in.type = INPUT_KEYBOARD;
				in.ki.wScan = ch;
				in.ki.dwFlags = KEYEVENTF_UNICODE | (up ? KEYEVENTF_KEYUP : 0);
				inputs.push_back(in);
			}
		}
	} else {
		return 2;
	}
	send(inputs, delay);
	return 0;
}

