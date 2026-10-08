// ii-host: keeps the Windows shell UI out of the way while ii runs, and always puts it back.
//
//   ii-host.exe [--shell <quickshell.exe> --config <dir|shell.qml>] [--no-taskbar] [--no-icons] [--no-hook]
//                [--keep-banners] [--no-theme]
//   ii-host.exe --rescue [--restart-explorer]   undo everything, from anywhere, any time
//   ii-host.exe --guard <pid>                   (internal) restores if <pid> dies uncleanly
//
// Panic shortcut while running: Ctrl+Alt+Shift+R (restores Windows UI, stops the shell, exits).

#include <string>

#include "common.h"

#include <shellapi.h>
#include <tlhelp32.h>

using namespace ii;

namespace {

constexpr UINT_PTR TIMER_REAPPLY = 1;
constexpr UINT_PTR TIMER_RESTART_SHELL = 2;
constexpr UINT_PTR TIMER_AFTER_EXPLORER = 3;
constexpr int HOTKEY_PANIC = 1;
constexpr UINT WM_II_SHELL_EXITED = WM_APP + 2;

struct Options {
	std::wstring shell;
	std::wstring config;
	bool taskbar = true;
	bool icons = true;
	bool hook = true;
	bool banners = true;
	bool theme = true;
};

Options options;
HWND hostWindow = nullptr;
UINT taskbarCreatedMsg = 0;
HWINEVENTHOOK showHook = nullptr;
HANDLE shellJob = nullptr;
HANDLE shellProcess = nullptr;
HANDLE shellWait = nullptr;
bool shuttingDown = false;
ULONGLONG crashTimes[3] = {};
int crashIndex = 0;

std::wstring selfPath() {
	wchar_t path[MAX_PATH];
	GetModuleFileNameW(nullptr, path, MAX_PATH);
	return path;
}

void killProcessesNamed(const wchar_t* exeName) {
	auto snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
	if (snap == INVALID_HANDLE_VALUE) return;
	PROCESSENTRY32W entry {};
	entry.dwSize = sizeof(entry);
	for (auto ok = Process32FirstW(snap, &entry); ok; ok = Process32NextW(snap, &entry)) {
		if (_wcsicmp(entry.szExeFile, exeName) != 0) continue;
		if (entry.th32ProcessID == GetCurrentProcessId()) continue;
		if (auto* proc = OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE, FALSE, entry.th32ProcessID)) {
			TerminateProcess(proc, 1);
			WaitForSingleObject(proc, 3000);
			CloseHandle(proc);
			log(L"killed %s (%lu)", exeName, entry.th32ProcessID);
		}
	}
	CloseHandle(snap);
}

// --- shell process -------------------------------------------------------------------------

void CALLBACK onShellExit(PVOID, BOOLEAN) { PostMessageW(hostWindow, WM_II_SHELL_EXITED, 0, 0); }

bool startShell() {
	if (options.shell.empty()) return false;

	auto cmd = L"\"" + options.shell + L"\"";
	if (!options.config.empty()) cmd += L" -p \"" + options.config + L"\"";

	auto dir = options.shell.substr(0, options.shell.find_last_of(L"\\/"));

	STARTUPINFOW si {};
	si.cb = sizeof(si); // no STARTF_USESHOWWINDOW: it would hide the shell's first window
	PROCESS_INFORMATION pi {};
	if (!CreateProcessW(
	        nullptr,
	        cmd.data(),
	        nullptr,
	        nullptr,
	        FALSE,
	        CREATE_NO_WINDOW | CREATE_SUSPENDED,
	        nullptr,
	        dir.c_str(),
	        &si,
	        &pi
	    ))
	{
		log(L"shell: CreateProcess failed (%lu): %s", GetLastError(), cmd.c_str());
		return false;
	}

	// The shell dies with the host (kill-on-close job), so a crashed host never leaves an
	// orphaned shell holding appbars.
	if (!shellJob) {
		shellJob = CreateJobObjectW(nullptr, nullptr);
		JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits {};
		limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
		SetInformationJobObject(shellJob, JobObjectExtendedLimitInformation, &limits, sizeof(limits));
	}
	AssignProcessToJobObject(shellJob, pi.hProcess);
	ResumeThread(pi.hThread);
	CloseHandle(pi.hThread);

	shellProcess = pi.hProcess;
	RegisterWaitForSingleObject(&shellWait, shellProcess, onShellExit, nullptr, INFINITE, WT_EXECUTEONLYONCE);
	log(L"shell: started pid %lu: %s", pi.dwProcessId, cmd.c_str());
	return true;
}

void stopShell() {
	if (!shellProcess) return;
	if (shellWait) UnregisterWait(shellWait);
	shellWait = nullptr;
	TerminateProcess(shellProcess, 0);
	WaitForSingleObject(shellProcess, 3000);
	CloseHandle(shellProcess);
	shellProcess = nullptr;
}

// --- apply / restore -----------------------------------------------------------------------

void applyAll() {
	if (options.taskbar) taskbar::hide();
	if (options.icons) desktop::hideIcons();
	if (options.banners) banners::hide();
	if (options.theme) theme::start();
}

void shutdown(int code) {
	if (shuttingDown) return;
	shuttingDown = true;
	log(L"shutdown (%d)", code);

	if (showHook) UnhookWinEvent(showHook);
	keyboard::uninstall();
	UnregisterHotKey(hostWindow, HOTKEY_PANIC);
	stopShell();
	restoreAll(false);
	state::set(L"hostClean", 1);
	PostQuitMessage(code);
}

void CALLBACK onObjectShown(HWINEVENTHOOK, DWORD, HWND hwnd, LONG idObject, LONG, DWORD, DWORD) {
	if (shuttingDown || idObject != OBJID_WINDOW || !hwnd) return;
	if (options.taskbar && taskbar::isTaskbarWindow(hwnd)) ShowWindow(hwnd, SW_HIDE);
}

void watchExplorer() {
	if (showHook) UnhookWinEvent(showHook);
	auto* tray = explorerTray();
	auto pid = tray ? processIdOf(tray) : 0;
	// Out-of-context: nothing is injected into Explorer.
	showHook = SetWinEventHook(EVENT_OBJECT_SHOW, EVENT_OBJECT_SHOW, nullptr, onObjectShown, pid, 0, WINEVENT_OUTOFCONTEXT);
}

void dispatchShortcut(WPARAM pressed, LPARAM index) {
	auto* name = keyboard::shortcutName(index);
	if (name && name[0] == L'@') {
		if (pressed && wcscmp(name, L"@showDesktop") == 0) desktop::toggleShowDesktop();
		return;
	}
	auto* sink = findShellSink();
	if (!name || !sink) return;

	COPYDATASTRUCT data {};
	data.dwData = pressed ? COPYDATA_PRESSED : COPYDATA_RELEASED;
	data.cbData = static_cast<DWORD>((wcslen(name) + 1) * sizeof(wchar_t));
	data.lpData = const_cast<wchar_t*>(name);
	DWORD_PTR result = 0;
	SendMessageTimeoutW(sink, WM_COPYDATA, reinterpret_cast<WPARAM>(hostWindow), reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG, 250, &result);
}

void onShellExited() {
	if (!shellProcess || shuttingDown) return;
	DWORD code = 0;
	GetExitCodeProcess(shellProcess, &code);
	CloseHandle(shellProcess);
	shellProcess = nullptr;
	shellWait = nullptr;
	log(L"shell: exited with code %lu", code);

	if (code == 0) {
		shutdown(0); // the shell quit on purpose
		return;
	}

	auto now = GetTickCount64();
	crashTimes[crashIndex++ % 3] = now;
	auto oldest = crashTimes[crashIndex % 3];
	if (crashIndex >= 3 && now - oldest < 60000) {
		log(L"shell: crashed 3 times in a minute, giving up");
		shutdown(2);
		MessageBoxW(nullptr, L"La shell de ii se cerró varias veces seguidas.\nSe restauró la barra de tareas y el escritorio de Windows.\n\nRegistro: %LOCALAPPDATA%\\ii-windows", L"ii-windows", MB_OK | MB_ICONWARNING | MB_TOPMOST);
		return;
	}

	SetTimer(hostWindow, TIMER_RESTART_SHELL, 1000, nullptr);
}

LRESULT CALLBACK wndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
	if (msg == taskbarCreatedMsg && taskbarCreatedMsg != 0) {
		// ii's own tray also broadcasts this so apps re-announce their icons: only a new
		// Explorer taskbar window means Explorer really restarted.
		static HWND knownTray = nullptr;
		auto* tray = explorerTray();
		if (tray && tray == knownTray) return 0;
		knownTray = tray;
		log(L"explorer (re)started, reapplying");
		SetTimer(hwnd, TIMER_AFTER_EXPLORER, 1500, nullptr);
		return 0;
	}

	switch (msg) {
	case keyboard::WM_II_SHORTCUT: dispatchShortcut(wParam, lParam); return 0;
	case WM_II_SHELL_EXITED: onShellExited(); return 0;
	case WM_HOTKEY:
		if (wParam == HOTKEY_PANIC) {
			log(L"panic hotkey");
			shutdown(3);
		}
		return 0;
	case WM_TIMER:
		if (wParam == TIMER_REAPPLY) {
			if (options.taskbar) taskbar::reapply();
			if (options.icons) desktop::reapplyIcons();
			// Apps that send their first toast get a settings key then; catch those too.
			if (options.banners) banners::hide();
			// Wallpaper changes rewrite ii's palette; Windows follows.
			if (options.theme) theme::apply();
		} else if (wParam == TIMER_RESTART_SHELL) {
			KillTimer(hwnd, TIMER_RESTART_SHELL);
			startShell();
		} else if (wParam == TIMER_AFTER_EXPLORER) {
			KillTimer(hwnd, TIMER_AFTER_EXPLORER);
			watchExplorer();
			applyAll();
		}
		return 0;
	case WM_QUERYENDSESSION:
		// Put Windows' UI back before Explorer saves its settings for the logoff.
		log(L"session ending, restoring");
		restoreAll(false);
		return TRUE;
	case WM_ENDSESSION:
		if (wParam) shutdown(0);
		else applyAll(); // logoff cancelled
		return 0;
	case WM_CLOSE: shutdown(0); return 0;
	default: return DefWindowProcW(hwnd, msg, wParam, lParam);
	}
}

void spawnGuard() {
	auto cmd = L"\"" + selfPath() + L"\" --guard " + std::to_wstring(GetCurrentProcessId());
	STARTUPINFOW si {};
	si.cb = sizeof(si);
	PROCESS_INFORMATION pi {};
	// Breakaway so the guard outlives a job that kills the host.
	if (CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW | CREATE_BREAKAWAY_FROM_JOB, nullptr, nullptr, &si, &pi)
	    || CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi))
	{
		CloseHandle(pi.hThread);
		CloseHandle(pi.hProcess);
		log(L"guard started (%lu)", pi.dwProcessId);
	} else {
		log(L"guard: CreateProcess failed (%lu)", GetLastError());
	}
}

int runHost() {
	auto* mutex = CreateMutexW(nullptr, TRUE, L"Local\\ii-windows-host");
	if (GetLastError() == ERROR_ALREADY_EXISTS) {
		log(L"another ii-host is running");
		return 1;
	}

	WNDCLASSW wc {};
	wc.lpfnWndProc = wndProc;
	wc.hInstance = GetModuleHandleW(nullptr);
	wc.lpszClassName = L"IiHostWindow";
	RegisterClassW(&wc);
	// A real (hidden) top-level window: message-only windows miss the TaskbarCreated broadcast.
	hostWindow = CreateWindowExW(WS_EX_TOOLWINDOW, wc.lpszClassName, L"ii-host", WS_POPUP, 0, 0, 0, 0, nullptr, nullptr, wc.hInstance, nullptr);
	taskbarCreatedMsg = RegisterWindowMessageW(L"TaskbarCreated");
	ChangeWindowMessageFilterEx(hostWindow, taskbarCreatedMsg, MSGFLT_ALLOW, nullptr);

	state::set(L"hostClean", 0);
	spawnGuard();

	if (!RegisterHotKey(hostWindow, HOTKEY_PANIC, MOD_CONTROL | MOD_ALT | MOD_SHIFT | MOD_NOREPEAT, 'R')) {
		log(L"panic hotkey Ctrl+Alt+Shift+R unavailable (%lu)", GetLastError());
	}

	applyAll();
	watchExplorer();
	SetTimer(hostWindow, TIMER_REAPPLY, 2000, nullptr);
	if (options.hook) keyboard::install(hostWindow);
	startShell();

	MSG msg;
	int code = 0;
	while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
		TranslateMessage(&msg);
		DispatchMessageW(&msg);
	}
	code = static_cast<int>(msg.wParam);

	if (!shuttingDown) shutdown(code);
	ReleaseMutex(mutex);
	log(L"host exit %d", code);
	return code;
}

int runGuard(DWORD pid) {
	auto* proc = OpenProcess(SYNCHRONIZE, FALSE, pid);
	if (!proc) return 1;
	WaitForSingleObject(proc, INFINITE);
	CloseHandle(proc);

	if (state::get(L"hostClean", 1) == 0) {
		log(L"guard: host %lu died without cleaning up, restoring Windows UI", pid);
		killProcessesNamed(L"quickshell.exe");
		restoreAll(false);
		state::set(L"hostClean", 1);
	}
	return 0;
}

int runRescue(bool restartExplorer) {
	log(L"rescue requested");
	killProcessesNamed(L"ii-host.exe");
	killProcessesNamed(L"quickshell.exe");
	restoreAll(restartExplorer);
	state::set(L"hostClean", 1);
	return 0;
}

} // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
	int argc = 0;
	auto** argv = CommandLineToArgvW(GetCommandLineW(), &argc);

	bool rescue = false;
	bool restartExplorer = false;
	DWORD guardPid = 0;

	for (int i = 1; i < argc; ++i) {
		std::wstring a = argv[i];
		auto next = [&]() -> std::wstring { return i + 1 < argc ? argv[++i] : L""; };
		if (a == L"--shell") options.shell = next();
		else if (a == L"--config") options.config = next();
		else if (a == L"--no-taskbar") options.taskbar = false;
		else if (a == L"--no-icons") options.icons = false;
		else if (a == L"--no-hook") options.hook = false;
		else if (a == L"--keep-banners") options.banners = false;
		else if (a == L"--no-theme") options.theme = false;
		else if (a == L"--rescue" || a == L"--restore") rescue = true;
		else if (a == L"--restart-explorer") restartExplorer = true;
		else if (a == L"--guard") guardPid = static_cast<DWORD>(_wtoi(next().c_str()));
	}
	LocalFree(argv);

	if (guardPid) return runGuard(guardPid);
	if (rescue) return runRescue(restartExplorer);
	return runHost();
}
