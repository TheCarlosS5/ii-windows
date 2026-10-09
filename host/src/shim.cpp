// ii-shim: Windows stand-ins for the small Linux commands illogical-impulse calls.
// One binary, dispatched on its own file name (copied as qalc.exe, xdg-open.exe, ...) or on its
// first argument (ii-shim <command> ...). Settings change only on explicit action commands.
//
//   qalc [-t] <expr>                     evaluate arithmetic, print the result
//   xdg-open <url|path>                  open with the default handler
//   ii-shim reveal <path>               open Explorer and select the exact item
//   notify-send [opts] <summary> [body]  forward a notification to the shell
//   playerctl play-pause|next|previous|play|pause|stop   media keys
//   wpctl set-mute @DEFAULT_SOURCE@|@DEFAULT_SINK@ toggle|1|0
//   loginctl lock-session | ii-shim lock  lock the session
//   ii-shim suspend                      sleep (not hibernate)
//   pidof <name>                         print pids of a process name
//   killall <name>                       end the user's processes with that name
//   ii-shim fetch <https-url> [opts]      HTTPS bytes to stdout or an atomic cache file
//   ii-shim ai-request <request.json>     streaming HTTP/HTTPS POST for AI chat
//   ls [-1] <dir>                        sorted visible file and folder names, one per line
//   ii-shim weather <place|lat,long>      wttr.in weather as ii's three-object JSON
//   ii-shim files <action> ...            desktop file actions through the shell (fileops.cpp)
//   ii-shim vdesk <command> ...            virtual desktops: switch, remove, move windows (vdesk.cpp)

#include "http.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cwctype>
#include <string>
#include <vector>
#include <fcntl.h>
#include <io.h>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
// clang-format off
#include <endpointvolume.h>
#include <mmdeviceapi.h>
#include <powrprof.h>
#include <shellapi.h>
#include <shlobj.h>
#include <tlhelp32.h>
// clang-format on

int switchwall(const std::vector<std::wstring>& args); // switchwall.cpp
int randomwall(const std::vector<std::wstring>& args); // randomwall.cpp
int weather(const std::vector<std::wstring>& args); // weather.cpp
int aiRequest(const std::vector<std::wstring>& args); // airequest.cpp
int cava(const std::vector<std::wstring>& args); // cava.cpp
int ydotool(const std::vector<std::wstring>& args); // ydotool.cpp
int secretTool(const std::vector<std::wstring>& args); // secrettool.cpp
int cliphist(const std::vector<std::wstring>& args); // cliphist.cpp
int hyprpicker(const std::vector<std::wstring>& args); // hyprpicker.cpp
int trans(const std::vector<std::wstring>& args); // trans.cpp
int transShellCommand(const std::wstring& command); // trans.cpp
int nightlightCommand(const std::vector<std::wstring>& args); // sidebar.cpp
int powerCommand(const std::vector<std::wstring>& args);
int systemInfoCommand(const std::vector<std::wstring>& args);
int systemSoundCommand(const std::vector<std::wstring>& args);

namespace {

using Args = std::vector<std::wstring>;

void out(const std::wstring& text) {
	auto size = WideCharToMultiByte(CP_UTF8, 0, text.c_str(), -1, nullptr, 0, nullptr, nullptr);
	std::string utf8(static_cast<size_t>(size), '\0');
	WideCharToMultiByte(CP_UTF8, 0, text.c_str(), -1, utf8.data(), size, nullptr, nullptr);
	std::fputs(utf8.c_str(), stdout);
	std::fputs("\n", stdout);
	std::fflush(stdout);
}

// --- qalc: recursive descent over + - * / % ^, parentheses, functions, constants ----------

struct Parser {
	std::wstring s;
	size_t i = 0;
	bool error = false;

	void skip() {
		while (i < s.size() && std::iswspace(s[i])) ++i;
	}
	bool eat(wchar_t c) {
		skip();
		if (i < s.size() && s[i] == c) {
			++i;
			return true;
		}
		return false;
	}

	double expr() {
		auto v = term();
		while (true) {
			if (eat(L'+')) v += term();
			else if (eat(L'-')) v -= term();
			else return v;
		}
	}
	double term() {
		auto v = power();
		while (true) {
			if (eat(L'*') || eat(L'×')) v *= power();
			else if (eat(L'/') || eat(L'÷')) v /= power();
			else if (eat(L'%')) v = std::fmod(v, power());
			else return v;
		}
	}
	double power() {
		auto base = unary();
		if (eat(L'^')) return std::pow(base, power()); // right associative
		return base;
	}
	double unary() {
		if (eat(L'-')) return -unary();
		if (eat(L'+')) return unary();
		return primary();
	}
	double primary() {
		skip();
		if (eat(L'(')) {
			auto v = expr();
			if (!eat(L')')) error = true;
			return v;
		}
		if (i < s.size() && (std::iswdigit(s[i]) || s[i] == L'.')) {
			auto start = i;
			while (i < s.size() && (std::iswdigit(s[i]) || s[i] == L'.')) ++i;
			if (i < s.size() && (s[i] == L'e' || s[i] == L'E') && i + 1 < s.size()
			    && (std::iswdigit(s[i + 1]) || s[i + 1] == L'-' || s[i + 1] == L'+'))
			{
				i += 2;
				while (i < s.size() && std::iswdigit(s[i])) ++i;
			}
			return std::wcstod(s.substr(start, i - start).c_str(), nullptr);
		}
		if (i < s.size() && std::iswalpha(s[i])) {
			auto start = i;
			while (i < s.size() && std::iswalnum(s[i])) ++i;
			auto name = s.substr(start, i - start);
			for (auto& c: name) c = static_cast<wchar_t>(std::towlower(c));
			if (name == L"pi") return 3.14159265358979323846;
			if (name == L"e") return 2.71828182845904523536;
			if (!eat(L'(')) {
				error = true;
				return 0;
			}
			auto a = expr();
			if (!eat(L')')) error = true;
			if (name == L"sqrt") return std::sqrt(a);
			if (name == L"sin") return std::sin(a);
			if (name == L"cos") return std::cos(a);
			if (name == L"tan") return std::tan(a);
			if (name == L"asin") return std::asin(a);
			if (name == L"acos") return std::acos(a);
			if (name == L"atan") return std::atan(a);
			if (name == L"ln") return std::log(a);
			if (name == L"log") return std::log10(a);
			if (name == L"exp") return std::exp(a);
			if (name == L"abs") return std::fabs(a);
			if (name == L"floor") return std::floor(a);
			if (name == L"ceil") return std::ceil(a);
			if (name == L"round") return std::round(a);
			error = true;
			return 0;
		}
		error = true;
		return 0;
	}
};

int qalc(const Args& args) {
	std::wstring expression;
	for (const auto& a: args) {
		if (a == L"-t") continue;
		if (!expression.empty()) expression += L' ';
		expression += a;
	}
	Parser p {expression};
	auto value = p.expr();
	p.skip();
	if (p.error || p.i != p.s.size() || std::isnan(value)) return 1;

	wchar_t buf[64];
	if (std::fabs(value - std::round(value)) < 1e-12 && std::fabs(value) < 1e15) {
		swprintf_s(buf, L"%.0f", value);
	} else {
		swprintf_s(buf, L"%.10g", value);
	}
	out(buf);
	return 0;
}

// --- misc -------------------------------------------------------------------------------

int ls(const Args& args) {
	auto offset = !args.empty() && args[0] == L"-1" ? 1u : 0u;
	if (args.size() != offset + 1 || args[offset].empty()) return 1;
	auto path = args[offset];
	if (path.size() > 3 && path[0] == L'/' && path[2] == L':' && std::iswalpha(path[1])) path.erase(0, 1);
	std::replace(path.begin(), path.end(), L'/', L'\\');
	auto attributes = GetFileAttributesW(path.c_str());
	if (attributes == INVALID_FILE_ATTRIBUTES || !(attributes & FILE_ATTRIBUTE_DIRECTORY)) return 1;
	if (path.back() != L'\\') path += L'\\';
	WIN32_FIND_DATAW entry {};
	auto handle = FindFirstFileW((path + L"*").c_str(), &entry);
	if (handle == INVALID_HANDLE_VALUE) return GetLastError() == ERROR_FILE_NOT_FOUND ? 0 : 1;
	std::vector<std::wstring> names;
	do {
		// Exclude both Windows hidden attributes and Linux-style dotfiles.
		if (entry.cFileName[0] != L'.' && !(entry.dwFileAttributes & FILE_ATTRIBUTE_HIDDEN)) names.emplace_back(entry.cFileName);
	} while (FindNextFileW(handle, &entry));
	auto error = GetLastError();
	FindClose(handle);
	if (error != ERROR_NO_MORE_FILES) return 1;
	std::sort(names.begin(), names.end());
	// Ai.qml splits on LF and checks extensions without trimming each name.
	if (_setmode(_fileno(stdout), _O_BINARY) == -1) return 1;
	for (const auto& name: names) out(name);
	return std::ferror(stdout) ? 1 : 0;
}

// qs ...: ii calls Quickshell by its short name (e.g. `qs -p <config> ipc call ...`). The shims
// live in <dist>\bin, Quickshell one level up next to its Qt DLLs.
int qs(const Args& args) {
	wchar_t self[MAX_PATH];
	GetModuleFileNameW(nullptr, self, MAX_PATH);
	std::wstring dir = self;
	dir = dir.substr(0, dir.find_last_of(L'\\'));
	auto exe = dir.substr(0, dir.find_last_of(L'\\')) + L"\\quickshell.exe";

	auto cmd = L"\"" + exe + L"\"";
	for (const auto& a: args) {
		std::wstring quoted = L"\"";
		for (auto c: a) {
			if (c == L'"') quoted += L'\\';
			quoted += c;
		}
		cmd += L" " + quoted + L"\"";
	}

	STARTUPINFOW si {};
	si.cb = sizeof(si);
	PROCESS_INFORMATION pi {};
	if (!CreateProcessW(exe.c_str(), cmd.data(), nullptr, nullptr, TRUE, 0, nullptr, nullptr, &si, &pi)) return 127;
	WaitForSingleObject(pi.hProcess, INFINITE);
	DWORD code = 1;
	GetExitCodeProcess(pi.hProcess, &code);
	CloseHandle(pi.hThread);
	CloseHandle(pi.hProcess);
	return static_cast<int>(code);
}

int xdgOpen(const Args& args) {
	if (args.empty()) return 1;
	auto target = args[0];
	if (target.rfind(L"file://", 0) == 0) target = target.substr(7);
	if (target.size() > 3 && target[0] == L'/' && target[2] == L':') target = target.substr(1);
	auto r = reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr, L"open", target.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
	return r > 32 ? 0 : 1;
}

int reveal(const Args& args) {
	if (args.size() != 1 || args[0].empty()) return 1;
	if (FAILED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) return 1;
	PIDLIST_ABSOLUTE item = nullptr;
	auto result = SHParseDisplayName(args[0].c_str(), nullptr, &item, 0, nullptr);
	if (SUCCEEDED(result)) {
		// With zero child items, this PIDL identifies the item to select in its parent.
		// No Explorer command-line parsing or URL escaping is involved.
		result = SHOpenFolderAndSelectItems(item, 0, nullptr, 0);
	}
	CoTaskMemFree(item);
	CoUninitialize();
	return SUCCEEDED(result) ? 0 : 1;
}

// test -d|-f|-e <path>: ii checks paths this way (e.g. the wallpaper selector).
int test(const Args& args) {
	if (args.size() != 2) return 2;
	auto attributes = GetFileAttributesW(args[1].c_str());
	if (attributes == INVALID_FILE_ATTRIBUTES) return 1;
	auto isDir = (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
	if (args[0] == L"-d") return isDir ? 0 : 1;
	if (args[0] == L"-f") return isDir ? 1 : 0;
	if (args[0] == L"-e") return 0;
	return 2;
}

// bash -c "<command>": ii runs its configurable app commands this way (Config.options.apps.*).
// Deliberately NOT a shell: only a single URI (ms-settings:..., http(s)://...) or a single
// program name is opened. Everything else, including ii's own Linux pipelines, gets 127
// ("command not found") and is never handed to cmd.exe, where it could do something else.

int bash(const Args& args) {
	if (args.size() < 2 || args[0] != L"-c") return 127;
	auto command = args[1];
	auto first = command.find_first_not_of(L" \t\r\n");
	auto last = command.find_last_not_of(L" \t\r\n");
	if (first == std::wstring::npos) return 127;
	command = command.substr(first, last - first + 1);

	// ii's translator runs `trans ...` through bash: literal arguments only (trans.cpp).
	if (command == L"trans" || command.rfind(L"trans ", 0) == 0 || command.rfind(L"trans\t", 0) == 0) {
		return ::transShellCommand(command);
	}

	// Settings passes one script path. Recognize only these two names; never run the script.
	auto script = command;
	auto quoted = script.size() >= 2 && (script.front() == L'"' || script.front() == L'\'') && script.back() == script.front();
	if (quoted) {
		script = script.substr(1, script.size() - 2);
	}
	// FileUtils.trimFileProtocol leaves /C:/... from a file:/// URL.
	if (script.size() > 3 && script[0] == L'/' && script[2] == L':' && std::iswalpha(script[1])) script.erase(0, 1);
	auto slash = script.find_last_of(L"\\/");
	auto name = slash == std::wstring::npos ? script : script.substr(slash + 1);
	if (name == L"random_konachan_wall.sh" || name == L"random_osu_wall.sh") {
		auto forbidden = quoted ? L"\"|<>*?\r\n" : L"\"'`|&;<>$*?\r\n";
		if (script.find_first_of(forbidden) != std::wstring::npos) return 127;
		auto colon = script.find(L':');
		if (colon != std::wstring::npos && (colon != 1 || !std::iswalpha(script[0])
		    || script.find(L':', colon + 1) != std::wstring::npos)) return 127;
		return ::randomwall({name == L"random_konachan_wall.sh" ? L"konachan" : L"osu"});
	}

	// ii's light/dark toggles: `bash -c "switchwall --mode dark --noswitch"`. Run in-process,
	// and only with plain words (flags, a #rrggbb color), never anything a shell would expand.
	if (command.rfind(L"switchwall ", 0) == 0) {
		if (command.find_first_not_of(L"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 #_.-") != std::wstring::npos) {
			return 127;
		}
		Args words;
		size_t start = 0;
		while ((start = command.find_first_not_of(L' ', start)) != std::wstring::npos) {
			auto end = command.find(L' ', start);
			words.push_back(command.substr(start, end - start));
			start = end;
		}
		words.erase(words.begin());
		return ::switchwall(words);
	}

	auto isUri = (command.rfind(L"ms-settings:", 0) == 0 || command.rfind(L"https://", 0) == 0
	              || command.rfind(L"http://", 0) == 0)
	          && command.find_first_of(L" \t\"'`|&;<>$\\") == std::wstring::npos;
	auto isProgram = command.find_first_not_of(L"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
	              == std::wstring::npos;
	if (!isUri && !isProgram) return 127;

	SHELLEXECUTEINFOW info {};
	info.cbSize = sizeof(info);
	info.fMask = SEE_MASK_FLAG_NO_UI; // a missing program is a quiet 127, not an error dialog
	info.lpVerb = L"open";
	info.lpFile = command.c_str();
	info.nShow = SW_SHOWNORMAL;
	return ShellExecuteExW(&info) ? 0 : 127;
}

void sendKey(WORD vk) {
	INPUT in[2] = {};
	in[0].type = INPUT_KEYBOARD;
	in[0].ki.wVk = vk;
	in[1] = in[0];
	in[1].ki.dwFlags = KEYEVENTF_KEYUP;
	SendInput(2, in, sizeof(INPUT));
}

int playerctl(const Args& args) {
	if (args.empty()) return 1;
	const auto& cmd = args[0];
	if (cmd == L"play-pause" || cmd == L"play" || cmd == L"pause") sendKey(VK_MEDIA_PLAY_PAUSE);
	else if (cmd == L"next") sendKey(VK_MEDIA_NEXT_TRACK);
	else if (cmd == L"previous") sendKey(VK_MEDIA_PREV_TRACK);
	else if (cmd == L"stop") sendKey(VK_MEDIA_STOP);
	else return 1;
	return 0;
}

int wpctl(const Args& args) {
	// wpctl set-mute @DEFAULT_SOURCE@ toggle
	if (args.size() < 3 || args[0] != L"set-mute") return 1;
	auto flow = args[1] == L"@DEFAULT_SOURCE@" ? eCapture : eRender;

	if (FAILED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) return 1;
	int rc = 1;
	IMMDeviceEnumerator* enumerator = nullptr;
	IMMDevice* device = nullptr;
	IAudioEndpointVolume* volume = nullptr;
	if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator)))
	    && SUCCEEDED(enumerator->GetDefaultAudioEndpoint(flow, eConsole, &device))
	    && SUCCEEDED(device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL, nullptr, reinterpret_cast<void**>(&volume))))
	{
		BOOL muted = FALSE;
		volume->GetMute(&muted);
		BOOL want = args[2] == L"toggle" ? !muted : (args[2] == L"1" ? TRUE : FALSE);
		volume->SetMute(want, nullptr);
		rc = 0;
	}
	if (volume) volume->Release();
	if (device) device->Release();
	if (enumerator) enumerator->Release();
	CoUninitialize();
	return rc;
}

std::vector<DWORD> pidsNamed(std::wstring name) {
	if (name.size() < 4 || _wcsicmp(name.c_str() + name.size() - 4, L".exe") != 0) name += L".exe";
	std::vector<DWORD> pids;
	auto snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
	if (snap == INVALID_HANDLE_VALUE) return pids;
	PROCESSENTRY32W e {};
	e.dwSize = sizeof(e);
	for (auto ok = Process32FirstW(snap, &e); ok; ok = Process32NextW(snap, &e)) {
		if (_wcsicmp(e.szExeFile, name.c_str()) == 0) pids.push_back(e.th32ProcessID);
	}
	CloseHandle(snap);
	return pids;
}

int pidof(const Args& args) {
	if (args.empty()) return 1;
	auto pids = pidsNamed(args.back());
	if (pids.empty()) return 1;
	std::wstring line;
	for (auto pid: pids) line += (line.empty() ? L"" : L" ") + std::to_wstring(pid);
	out(line);
	return 0;
}

int killall(const Args& args) {
	if (args.empty()) return 1;
	auto any = false;
	for (auto pid: pidsNamed(args.back())) {
		// Only processes this user can terminate; system processes refuse the handle.
		if (auto* proc = OpenProcess(PROCESS_TERMINATE, FALSE, pid)) {
			any = TerminateProcess(proc, 1) || any;
			CloseHandle(proc);
		}
	}
	return any ? 0 : 1;
}

int notifySend(const Args& args) {
	// Collect options the shell understands; forward as
	// "app\x1fsummary\x1fbody\x1ficon\x1furgency\x1ftimeout\x1ftransient".
	std::wstring app = L"ii-windows", icon, urgency = L"normal", timeout, transient = L"0";
	std::vector<std::wstring> positional;
	for (size_t i = 0; i < args.size(); ++i) {
		const auto& a = args[i];
		auto value = [&](const std::wstring& flag) -> std::wstring {
			if (a.rfind(flag + L"=", 0) == 0) return a.substr(flag.size() + 1);
			if (a == flag && i + 1 < args.size()) return args[++i];
			return L"";
		};
		if (a.rfind(L"-a", 0) == 0 || a.rfind(L"--app-name", 0) == 0) {
			app = value(a.rfind(L"--", 0) == 0 ? L"--app-name" : L"-a");
		} else if (a.rfind(L"-i", 0) == 0 || a.rfind(L"--icon", 0) == 0) {
			icon = value(a.rfind(L"--", 0) == 0 ? L"--icon" : L"-i");
		} else if (a.rfind(L"-u", 0) == 0 || a.rfind(L"--urgency", 0) == 0) {
			urgency = value(a.rfind(L"--", 0) == 0 ? L"--urgency" : L"-u");
		} else if (a.rfind(L"-t", 0) == 0 || a.rfind(L"--expire-time", 0) == 0) {
			timeout = value(a.rfind(L"--", 0) == 0 ? L"--expire-time" : L"-t");
		} else if (a == L"-e" || a == L"--transient") {
			transient = L"1";
		} else if (a.rfind(L"-", 0) == 0) {
			// -h/-c and friends take a value; skip it when given separately.
			if (a.find(L'=') == std::wstring::npos && i + 1 < args.size()) ++i;
		} else {
			positional.push_back(a);
		}
	}
	if (positional.empty()) return 1;

	auto payload = app + L'\x1f' + positional[0] + L'\x1f' + (positional.size() > 1 ? positional[1] : L"")
	             + L'\x1f' + icon + L'\x1f' + urgency + L'\x1f' + timeout + L'\x1f' + transient;
	auto* sink = FindWindowW(L"IiShellNotificationSink", nullptr);
	if (!sink) return 1;
	COPYDATASTRUCT data {};
	data.dwData = 0x49490010; // notification
	data.cbData = static_cast<DWORD>((payload.size() + 1) * sizeof(wchar_t));
	data.lpData = payload.data();
	DWORD_PTR result = 0;
	SendMessageTimeoutW(sink, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG, 2000, &result);
	return 0;
}

std::wstring baseName(const std::wstring& path) {
	auto slash = path.find_last_of(L"\\/");
	auto name = slash == std::wstring::npos ? path : path.substr(slash + 1);
	auto dot = name.find_last_of(L'.');
	if (dot != std::wstring::npos) name = name.substr(0, dot);
	for (auto& c: name) c = static_cast<wchar_t>(std::towlower(c));
	return name;
}

} // namespace

// capture.cpp
int screenshot(const std::vector<std::wstring>& args);
int crop(const std::vector<std::wstring>& args);
int ocrFile(const std::vector<std::wstring>& args);
// switchwall.cpp
int switchwall(const std::vector<std::wstring>& args);
int thumbnail(const std::vector<std::wstring>& args);
int magick(const std::vector<std::wstring>& args);
int vdesk(const std::vector<std::wstring>& args);
// fileops.cpp
int filesCommand(const std::vector<std::wstring>& args);

int brightnessCommand(const std::wstring& command, const std::vector<std::wstring>& args);

int wmain(int argc, wchar_t** argv) {
	auto command = baseName(argv[0]);
	Args args(argv + 1, argv + argc);
	if (command == L"ii-shim") {
		if (args.empty()) return 2;
		command = args[0];
		args.erase(args.begin());
	}

	if (command == L"qalc") return qalc(args);
	if (command == L"ddcutil" || command == L"brightnessctl" || command == L"brightness-win" || command == L"_brightness-worker") return brightnessCommand(command, args);
	if (command == L"xdg-open") return xdgOpen(args);
	if (command == L"reveal") return reveal(args);
	if (command == L"files") return filesCommand(args);
	if (command == L"bash") return bash(args);
	if (command == L"qs") return qs(args);
	if (command == L"screenshot") return screenshot(args);
	if (command == L"crop") return crop(args);
	if (command == L"switchwall") return switchwall(args);
	if (command == L"randomwall") return randomwall(args);
	if (command == L"fetch") return fetch(args);
	if (command == L"ai-request") return aiRequest(args);
	if (command == L"ls") return ls(args);
	if (command == L"weather") return weather(args);
	if (command == L"cava") return cava(args);
	if (command == L"nightlight") return nightlightCommand(args);
	if (command == L"power") return powerCommand(args);
	if (command == L"system-info") return systemInfoCommand(args);
	if (command == L"system-sound") return systemSoundCommand(args);
	if (command == L"test") return test(args);
	if (command == L"thumbnail") return thumbnail(args);
	if (command == L"magick") return magick(args);
	if (command == L"vdesk") return vdesk(args);
	if (command == L"ocr") return ocrFile(args);
	if (command == L"notify-send") return notifySend(args);
	if (command == L"playerctl") return playerctl(args);
	if (command == L"wpctl") return wpctl(args);
	if (command == L"pidof") return pidof(args);
	if (command == L"ydotool") return ydotool(args);
	if (command == L"secret-tool") return secretTool(args);
	if (command == L"cliphist") return cliphist(args);
	if (command == L"hyprpicker") return hyprpicker(args);
	if (command == L"trans") return trans(args);
	if (command == L"killall" || command == L"pkill") return killall(args);
	if (command == L"lock" || (command == L"loginctl" && !args.empty() && args[0] == L"lock-session")) {
		return LockWorkStation() ? 0 : 1;
	}
	if (command == L"suspend") {
		// Leave a trace: an unexpected sleep must be explainable from ii's own log.
		SYSTEM_POWER_STATUS power {};
		GetSystemPowerStatus(&power);
		wchar_t* base = nullptr;
		if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &base))) {
			auto path = std::wstring(base) + L"\\ii-windows\\host.log";
			if (auto* f = _wfopen(path.c_str(), L"a, ccs=UTF-8")) {
				SYSTEMTIME t;
				GetLocalTime(&t);
				fwprintf(f, L"%04d-%02d-%02d %02d:%02d:%02d.%03d [%lu] ii-shim suspend: AC %d, battery %d%%, reason %s\n",
				    t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond, t.wMilliseconds, GetCurrentProcessId(),
				    power.ACLineStatus, power.BatteryLifePercent, args.empty() ? L"session menu" : args[0].c_str());
				fclose(f);
			}
		}
		CoTaskMemFree(base);
		return SetSuspendState(FALSE, FALSE, FALSE) ? 0 : 1;
	}
	return 2;
}
