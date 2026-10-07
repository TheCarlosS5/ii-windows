// ii-shim: Windows stand-ins for the small Linux commands illogical-impulse calls.
// One binary, dispatched on its own file name (copied as qalc.exe, xdg-open.exe, ...) or on its
// first argument (ii-shim <command> ...). Nothing here touches system settings.
//
//   qalc [-t] <expr>                     evaluate arithmetic, print the result
//   xdg-open <url|path>                  open with the default handler
//   notify-send [opts] <summary> [body]  forward a notification to the shell
//   playerctl play-pause|next|previous|play|pause|stop   media keys
//   wpctl set-mute @DEFAULT_SOURCE@|@DEFAULT_SINK@ toggle|1|0
//   loginctl lock-session | ii-shim lock  lock the session
//   ii-shim suspend                      sleep (not hibernate)
//   pidof <name>                         print pids of a process name
//   killall <name>                       end the user's processes with that name

#include <cmath>
#include <cstdio>
#include <cwctype>
#include <string>
#include <vector>

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
#include <tlhelp32.h>
// clang-format on

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

int xdgOpen(const Args& args) {
	if (args.empty()) return 1;
	auto target = args[0];
	if (target.rfind(L"file://", 0) == 0) target = target.substr(7);
	if (target.size() > 3 && target[0] == L'/' && target[2] == L':') target = target.substr(1);
	auto r = reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr, L"open", target.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
	return r > 32 ? 0 : 1;
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

int wmain(int argc, wchar_t** argv) {
	auto command = baseName(argv[0]);
	Args args(argv + 1, argv + argc);
	if (command == L"ii-shim") {
		if (args.empty()) return 2;
		command = args[0];
		args.erase(args.begin());
	}

	if (command == L"qalc") return qalc(args);
	if (command == L"xdg-open") return xdgOpen(args);
	if (command == L"notify-send") return notifySend(args);
	if (command == L"playerctl") return playerctl(args);
	if (command == L"wpctl") return wpctl(args);
	if (command == L"pidof") return pidof(args);
	if (command == L"killall" || command == L"pkill") return killall(args);
	if (command == L"lock" || (command == L"loginctl" && !args.empty() && args[0] == L"lock-session")) {
		return LockWorkStation() ? 0 : 1;
	}
	if (command == L"suspend") return SetSuspendState(FALSE, FALSE, FALSE) ? 0 : 1;
	return 2;
}
