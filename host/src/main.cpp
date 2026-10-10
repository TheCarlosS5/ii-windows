// ii-host: keeps the Windows shell UI out of the way while ii runs, and always puts it back.
//
//   ii-host.exe [--shell <quickshell.exe> --config <dir|shell.qml>] [--no-taskbar] [--no-icons] [--no-hook]
//                [--keep-banners] [--no-theme] [--no-nightlight] [--boot]
//   --boot: started at logon. High priority while the shell loads, taskbar checked every 200 ms,
//           and a cover with ii's wallpaper until the shell's own is up (Explorer's never shows).
//   ii-host.exe --rescue [--restart-explorer]   undo everything, from anywhere, any time
//   ii-host.exe --guard <pid>                   (internal) restores if <pid> dies uncleanly
//
// Panic shortcut while running: Ctrl+Alt+Shift+R (restores Windows UI, stops the shell, exits).

#include <algorithm>
#include <string>
#include <vector>

#include "common.h"
#include "nightlight.h"

#include <objbase.h>
#include <shellapi.h>
#include <shlobj.h>
#include <tlhelp32.h>

using namespace ii;

namespace {

constexpr UINT_PTR TIMER_REAPPLY = 1;
constexpr UINT_PTR TIMER_RESTART_SHELL = 2;
constexpr UINT_PTR TIMER_AFTER_EXPLORER = 3;
constexpr UINT_PTR TIMER_BOOT_FAST = 4;
constexpr UINT_PTR TIMER_BOOT_END = 5;
constexpr UINT_PTR TIMER_WATCHDOG = 6;
constexpr UINT_PTR TIMER_HEALTH = 7;
// Proposed defaults (TASKS_ii_windows 9.7), to be tuned with the B02 measurements: the shell
// must show its wallpaper within this long; the very first start compiles the QML and gets more.
constexpr ULONGLONG SHELL_READY_TIMEOUT_MS = 45000;
constexpr ULONGLONG SHELL_READY_TIMEOUT_COLD_MS = 90000;
// After the first monitor has its wallpaper, the others get this long before the shell counts as
// ready with some monitors missing (logged, and their covers go instead of waiting for ever).
constexpr ULONGLONG SHELL_PARTIAL_READY_MS = 10000;
constexpr ULONGLONG SHELL_HUNG_TIMEOUT_MS = 20000;
constexpr int SHELL_STUCK_RESTARTS = 3;
constexpr int SHELL_LAUNCH_ATTEMPTS = 3; // CreateProcess failures in a row before giving up
constexpr UINT BOOT_FAST_MS = 200;
constexpr UINT BOOT_FAST_FOR_MS = 30000;
constexpr UINT BOOT_HIGH_PRIORITY_MS = 60000;
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
	bool nightlight = true;
	bool boot = false;
	bool splash = true;
};

Options options;
HWND hostWindow = nullptr;
UINT taskbarCreatedMsg = 0;
HWINEVENTHOOK showHook = nullptr;
HANDLE shellJob = nullptr;
HANDLE shellProcess = nullptr;
HANDLE shellWait = nullptr;
bool shuttingDown = false;
bool guardReady = false;
bool booting = false;
HANDLE guardProcess = nullptr;
ULONGLONG crashTimes[3] = {};
// Watchdog: a shell that never shows its wallpaper, or stops responding, is restarted; with the
// taskbar and icons hidden, a stuck shell would leave the user in front of a black screen.
DWORD shellPid = 0;
ULONGLONG shellStartedAt = 0;
bool shellReady = false;
ULONGLONG shellHungSince = 0;
int stuckRestarts = 0;
int crashIndex = 0;
int launchFailures = 0;
// The Windows UI (taskbar, icons) is hidden by us right now. Everything that re-hides it (timers,
// the Explorer hook) is gated by this, so a failed start can give the desktop back and stay out
// of the way until the shell is really up.
bool uiHidden = false;
// Where the host is in its life; every transition is logged, which makes a stuck start readable.
enum class Phase { Preparing, Launching, AwaitingReady, Active, Restoring, Recovered, Failed };
Phase phase = Phase::Preparing;
// When the shell was first seen covering some monitors but not all (partial readiness).
ULONGLONG partialSince = 0;
bool coldStart = false;   // no compiled QML cache yet: the first start is slow, give it longer
bool slowLogged = false;
std::vector<bool> monitorMarked; // per monitor: its first covered moment was written to the timeline
// The host itself ended the shell (stuck or hung): its exit is not a crash for the crash counter,
// the stuck-restart counter already limits those.
bool endedByWatchdog = false;
// Windows' own notification banners are switched off right now. Only while the shell's listener
// is confirmed to be receiving notifications (health channel); never on the shell's mere existence.
bool bannersSuppressed = false;

struct MonitorCover {
	RECT rect {};
	bool covered = false;
};

const wchar_t* phaseName(Phase p) {
	switch (p) {
	case Phase::Preparing: return L"preparing";
	case Phase::Launching: return L"launching";
	case Phase::AwaitingReady: return L"awaiting-ready";
	case Phase::Active: return L"active";
	case Phase::Restoring: return L"restoring";
	case Phase::Recovered: return L"recovered";
	case Phase::Failed: return L"failed";
	}
	return L"?";
}

void setPhase(Phase next, const wchar_t* why = L"") {
	if (next == phase) return;
	log(L"phase: %s -> %s%s%s", phaseName(phase), phaseName(next), why[0] ? L" : " : L"", why);
	phase = next;
}

std::wstring selfPath() {
	wchar_t path[MAX_PATH];
	GetModuleFileNameW(nullptr, path, MAX_PATH);
	return path;
}

std::wstring selfDir() {
	auto path = selfPath();
	return path.substr(0, path.find_last_of(L"\\/"));
}

// No compiled QML yet (quickshell/cache/by-shell): the first start takes a lot longer.
bool coldQmlCache() {
	wchar_t* base = nullptr;
	auto cold = true;
	if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &base))) {
		cold = GetFileAttributesW((std::wstring(base) + L"\\quickshell\\cache\\by-shell").c_str()) == INVALID_FILE_ATTRIBUTES;
	}
	CoTaskMemFree(base);
	return cold;
}

// Tests can shorten the readiness timeout (II_TEST_READY_TIMEOUT_MS); a real run uses the constants.
ULONGLONG readyTimeoutMs() {
	wchar_t value[16];
	if (GetEnvironmentVariableW(L"II_TEST_READY_TIMEOUT_MS", value, _countof(value)) > 0) {
		auto ms = _wcstoui64(value, nullptr, 10);
		if (ms >= 500) return ms;
	}
	return coldStart ? SHELL_READY_TIMEOUT_COLD_MS : SHELL_READY_TIMEOUT_MS;
}

// Windows' banners go off only while the shell's listener is confirmed (permission granted,
// subscribed, heartbeat fresh), and come back the moment it is not: permission denied or revoked,
// a stopped or hung shell, an unknown protocol, another shell's messages. A first start where
// the listener is not ready yet therefore keeps Windows' banners as the working channel.
void evaluateBanners() {
	if (!options.banners || shuttingDown) {
		if (bannersSuppressed) {
			banners::restore();
			bannersSuppressed = false;
		}
		return;
	}
	auto status = health::notifications(GetTickCount64());
	if (status.operational) {
		if (!bannersSuppressed) log(L"banners: Windows' own switched off (%s)", status.reason.c_str());
		bannersSuppressed = true;
		banners::hide(); // cheap to repeat: apps that send their first toast later get caught
	} else if (bannersSuppressed) {
		log(L"banners: Windows' own back on (%s)", status.reason.c_str());
		banners::restore();
		bannersSuppressed = false;
	}
}

UINT watchdogMs() {
	wchar_t value[16];
	if (GetEnvironmentVariableW(L"II_TEST_WATCHDOG_MS", value, _countof(value)) > 0) {
		auto ms = _wcstoui64(value, nullptr, 10);
		if (ms >= 100) return static_cast<UINT>(ms);
	}
	return 5000;
}

// --- shell process -------------------------------------------------------------------------

void CALLBACK onShellExit(PVOID, BOOLEAN) { PostMessageW(hostWindow, WM_II_SHELL_EXITED, 0, 0); }

bool startShell() {
	if (options.shell.empty()) return false;

	auto cmd = L"\"" + options.shell + L"\"";
	if (!options.config.empty()) cmd += L" -p \"" + options.config + L"\"";

	auto dir = options.shell.substr(0, options.shell.find_last_of(L"\\/"));

	setPhase(Phase::Launching);
	if (GetFileAttributesW(options.shell.c_str()) == INVALID_FILE_ATTRIBUTES) {
		log(L"shell: executable not found (%lu): %s", GetLastError(), options.shell.c_str());
		return false;
	}

	health::prepareLaunch(hostWindow); // the shell inherits the instance id and where to report
	STARTUPINFOW si {};
	si.cb = sizeof(si); // no STARTF_USESHOWWINDOW: it would hide the shell's first window
	PROCESS_INFORMATION pi {};
	if (!CreateProcessW(
	        nullptr,
	        cmd.data(),
	        nullptr,
	        nullptr,
	        FALSE,
	        CREATE_NO_WINDOW | CREATE_SUSPENDED | (booting ? HIGH_PRIORITY_CLASS : 0),
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
	shellPid = pi.dwProcessId;
	shellStartedAt = GetTickCount64();
	shellReady = false;
	shellHungSince = 0;
	partialSince = 0;
	slowLogged = false;
	monitorMarked.clear();
	launchFailures = 0;
	instance::recordShell(shellPid, options.config);
	health::shellStarted(shellPid);
	bench(L"shell-launched");
	// Until the shell is up, look often (cheap): a ready shell is noticed within 250 ms and the
	// splash is not kept waiting for the 5 s housekeeping tick.
	SetTimer(hostWindow, TIMER_WATCHDOG, std::min<UINT>(250, watchdogMs()), nullptr);
	splash::setShellPid(pi.dwProcessId);
	RegisterWaitForSingleObject(&shellWait, shellProcess, onShellExit, nullptr, INFINITE, WT_EXECUTEONLYONCE);
	setPhase(Phase::AwaitingReady, L"shell process started");
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
	instance::clearShell();
	health::reset();
	evaluateBanners();
}

// --- apply / restore -----------------------------------------------------------------------

void applyAll() {
	uiHidden = true;
	if (options.taskbar) taskbar::hide();
	if (options.icons) desktop::hideIcons();
	// Banners are not touched here: see evaluateBanners().
	if (options.theme) theme::start();
}

// Gives Explorer's taskbar and desktop icons back without ending the host: used while a shell
// that never came up is restarted, so a stuck start leaves a usable desktop instead of a black one.
void exposeExplorer(const wchar_t* why) {
	if (!uiHidden) return;
	log(L"giving Explorer back while the shell is restarted: %s", why);
	uiHidden = false;
	splash::close();
	taskbar::restore();
	desktop::restoreIcons();
}

// The one rollback path: normal exit, error exit and the panic key all go through here, and it is
// safe to run twice. It does not post WM_QUIT, so a message box can still be shown afterwards.
void restoreAndStop(int code) {
	if (shuttingDown) return;
	shuttingDown = true;
	setPhase(Phase::Restoring, code == 0 ? L"normal stop" : L"error stop");
	log(L"shutdown (%d)", code);

	if (showHook) UnhookWinEvent(showHook);
	keyboard::uninstall();
	UnregisterHotKey(hostWindow, HOTKEY_PANIC);
	KillTimer(hostWindow, TIMER_RESTART_SHELL);
	stopShell();
	splash::close();
	restoreAll(false);
	uiHidden = false;
	state::set(L"hostClean", 1);
	setPhase(code == 0 ? Phase::Recovered : Phase::Failed);
}

void shutdown(int code) {
	restoreAndStop(code);
	PostQuitMessage(code);
}

// The shell cannot be started (or kept up): everything is put back first, then the user is told
// once. The message box runs after the restore and before WM_QUIT (a posted WM_QUIT would close
// the box at once).
void abortLaunch(const wchar_t* why) {
	log(L"giving up: %s", why);
	restoreAndStop(2);
	std::wstring text = L"ii no pudo mantener su shell.\nSe restauró la barra de tareas y el escritorio de Windows.\n\nMotivo: ";
	text += why;
	text += L"\nRegistro: %LOCALAPPDATA%\\ii-windows\\host.log";
	alertUser(text);
	PostQuitMessage(2);
}

// A launch that failed (CreateProcess): retry a few times with growing pauses, then give up and
// restore. Never loops forever between a black screen and a cover.
void scheduleLaunchRetry(const wchar_t* why) {
	++launchFailures;
	if (launchFailures >= SHELL_LAUNCH_ATTEMPTS) {
		wchar_t text[256];
		swprintf_s(text, L"%s (%d intentos)", why, launchFailures);
		abortLaunch(text);
		return;
	}
	auto delay = 1000u << (launchFailures - 1);
	log(L"shell: launch failed (%s), attempt %d of %d, retrying in %u ms", why, launchFailures, SHELL_LAUNCH_ATTEMPTS, delay);
	SetTimer(hostWindow, TIMER_RESTART_SHELL, delay, nullptr);
}

void CALLBACK onObjectShown(HWINEVENTHOOK, DWORD, HWND hwnd, LONG idObject, LONG, DWORD, DWORD) {
	if (shuttingDown || !uiHidden || idObject != OBJID_WINDOW || !hwnd) return;
	if (options.taskbar && taskbar::isTaskbarWindow(hwnd)) taskbar::conceal(hwnd);
}

void watchExplorer() {
	if (showHook) UnhookWinEvent(showHook);
	auto* tray = explorerTray();
	auto pid = tray ? processIdOf(tray) : 0;
	// Out-of-context: nothing is injected into Explorer.
	showHook = SetWinEventHook(EVENT_OBJECT_SHOW, EVENT_OBJECT_SHOW, nullptr, onObjectShown, pid, 0, WINEVENT_OUTOFCONTEXT);
}

void sendToShell(const wchar_t* name, bool pressed);

// Win+Q: close the app in front the way Alt+F4 does (SC_CLOSE: it may still ask to save).
// Never ii's own surfaces or the taskbar; on the desktop it opens ii's session menu instead.
void closeForegroundWindow() {
	auto* fg = GetForegroundWindow();
	if (!fg) return;
	DWORD pid = 0;
	GetWindowThreadProcessId(fg, &pid);
	if (pid == shellPid || pid == GetCurrentProcessId()) return;
	wchar_t cls[64] {};
	GetClassNameW(fg, cls, 64);
	if (wcscmp(cls, L"Progman") == 0 || wcscmp(cls, L"WorkerW") == 0) {
		sendToShell(L"sessionToggle", true);
		sendToShell(L"sessionToggle", false);
		return;
	}
	if (wcscmp(cls, L"Shell_TrayWnd") == 0 || wcscmp(cls, L"Shell_SecondaryTrayWnd") == 0) return;
	PostMessageW(fg, WM_SYSCOMMAND, SC_CLOSE, 0);
}

void sendToShell(const wchar_t* name, bool pressed) {
	auto* sink = findShellSink();
	if (!sink) return;
	COPYDATASTRUCT data {};
	data.dwData = pressed ? COPYDATA_PRESSED : COPYDATA_RELEASED;
	data.cbData = static_cast<DWORD>((wcslen(name) + 1) * sizeof(wchar_t));
	data.lpData = const_cast<wchar_t*>(name);
	DWORD_PTR result = 0;
	SendMessageTimeoutW(sink, WM_COPYDATA, reinterpret_cast<WPARAM>(hostWindow), reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG, 250, &result);
}

void dispatchShortcut(WPARAM pressed, LPARAM index) {
	auto* name = keyboard::shortcutName(index);
	if (name && name[0] == L'@') {
		if (pressed && wcscmp(name, L"@showDesktop") == 0) desktop::toggleShowDesktop();
		if (pressed && wcscmp(name, L"@closeWindow") == 0) closeForegroundWindow();
		if (pressed && wcscmp(name, L"@colorPicker") == 0) {
			// ii's color picker (Super+Shift+C on Linux): ii-shim hyprpicker, next to the shell.
			auto dir = options.shell.substr(0, options.shell.find_last_of(L"\\/"));
			auto cmd = L"\"" + dir + L"\\bin\\hyprpicker.exe\" -a";
			STARTUPINFOW si {};
			si.cb = sizeof(si);
			PROCESS_INFORMATION pi {};
			if (CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
				AllowSetForegroundWindow(pi.dwProcessId);
				CloseHandle(pi.hThread);
				CloseHandle(pi.hProcess);
			}
		}
		if (pressed && wcscmp(name, L"@restartShell") == 0) {
			// ii's "reload widgets" (Ctrl+Super+R on Linux): a fresh shell process.
			log(L"shell: restart requested");
			stopShell();
			if (!startShell()) scheduleLaunchRetry(L"no se pudo lanzar el shell");
		}
		return;
	}
	if (name) sendToShell(name, pressed != 0);
}

struct ShellWindows {
	DWORD pid = 0;
	// Per monitor: does a visible window of the shell cover the whole screen? Readiness is
	// judged per screen, so one incidental window does not stand for all of them.
	std::vector<MonitorCover> monitors;
	bool hung = false;
	HWND any = nullptr; // one of its windows, to ping

	size_t covered() const {
		size_t n = 0;
		for (const auto& m: monitors) n += m.covered ? 1 : 0;
		return n;
	}
};

BOOL CALLBACK collectMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
	MONITORINFO info {};
	info.cbSize = sizeof(info);
	if (GetMonitorInfoW(monitor, &info)) reinterpret_cast<std::vector<MonitorCover>*>(data)->push_back({info.rcMonitor, false}); // NOLINT
	return TRUE;
}

BOOL CALLBACK inspectShellWindow(HWND hwnd, LPARAM data) {
	auto* found = reinterpret_cast<ShellWindows*>(data); // NOLINT
	DWORD pid = 0;
	GetWindowThreadProcessId(hwnd, &pid);
	if (pid != found->pid) return TRUE;
	if (!found->any) found->any = hwnd;
	if (IsHungAppWindow(hwnd)) found->hung = true;
	if (IsWindowVisible(hwnd)) {
		RECT r {};
		GetWindowRect(hwnd, &r);
		for (auto& m: found->monitors) {
			if (r.left <= m.rect.left && r.top <= m.rect.top && r.right >= m.rect.right && r.bottom >= m.rect.bottom) m.covered = true;
		}
	}
	return TRUE;
}

bool foregroundIsFullscreenApp() {
	auto* fg = GetForegroundWindow();
	if (!fg) return false;
	DWORD pid = 0;
	GetWindowThreadProcessId(fg, &pid);
	if (pid == shellPid || pid == GetCurrentProcessId()) return false;
	// Windows' own desktop also covers the screen: not a game.
	wchar_t cls[64] {};
	GetClassNameW(fg, cls, 64);
	if (wcscmp(cls, L"Progman") == 0 || wcscmp(cls, L"WorkerW") == 0 || wcscmp(cls, L"Shell_TrayWnd") == 0) return false;
	RECT r {};
	GetWindowRect(fg, &r);
	MONITORINFO info {};
	info.cbSize = sizeof(info);
	return GetMonitorInfoW(MonitorFromWindow(fg, MONITOR_DEFAULTTONEAREST), &info) && r.left <= info.rcMonitor.left
	    && r.top <= info.rcMonitor.top && r.right >= info.rcMonitor.right && r.bottom >= info.rcMonitor.bottom;
}

void restartStuckShell(const wchar_t* why) {
	log(L"shell: %s, restarting it", why);
	if (++stuckRestarts > SHELL_STUCK_RESTARTS) {
		wchar_t text[160];
		swprintf_s(text, L"la shell se quedó colgada %d veces seguidas", SHELL_STUCK_RESTARTS);
		abortLaunch(text);
		return;
	}
	// A shell that never showed anything: give Explorer back while the next one starts, instead
	// of keeping the user in front of a cover for another round. It is hidden again when the
	// new shell is really up (onShellReady).
	if (!shellReady) exposeExplorer(why);
	shellHungSince = 0;
	endedByWatchdog = true;
	TerminateProcess(shellProcess, 1); // onShellExited starts a new one
}

void onShellReady(ULONGLONG now, size_t covered, size_t total) {
	shellReady = true;
	stuckRestarts = 0;
	bench(covered < total ? L"ready-partial" : L"ready");
	SetTimer(hostWindow, TIMER_WATCHDOG, watchdogMs(), nullptr); // back to the slow housekeeping tick
	setPhase(Phase::Active, L"shell is up");
	if (covered < total) {
		log(L"shell: ready after %llu ms with %zu of %zu monitors showing it (the rest never did)", now - shellStartedAt, covered, total);
	} else {
		log(L"shell: ready after %llu ms on %zu monitor(s)", now - shellStartedAt, total);
	}
	// A retry gave the desktop back: now that ii is really there, take it again.
	if (!uiHidden && !shuttingDown) {
		log(L"shell: hiding Windows' UI again");
		applyAll();
	}
}

void watchShell() {
	if (!shellProcess || shuttingDown) return;
	ShellWindows found;
	found.pid = shellPid;
	EnumDisplayMonitors(nullptr, nullptr, collectMonitor, reinterpret_cast<LPARAM>(&found.monitors)); // NOLINT
	EnumWindows(inspectShellWindow, reinterpret_cast<LPARAM>(&found)); // NOLINT
	// IsHungAppWindow skips tool/layered windows like the shell's: ask one directly.
	DWORD_PTR result = 0;
	if (!found.hung && found.any && !SendMessageTimeoutW(found.any, WM_NULL, 0, 0, SMTO_ABORTIFHUNG | SMTO_BLOCK, 1000, &result)) {
		found.hung = true;
	}
	auto now = GetTickCount64();
	if (!shellReady) {
		if (monitorMarked.size() != found.monitors.size()) monitorMarked.assign(found.monitors.size(), false);
		for (size_t i = 0; i < found.monitors.size(); ++i) {
			if (found.monitors[i].covered && !monitorMarked[i]) {
				monitorMarked[i] = true;
				bench(L"monitor-covered", std::to_wstring(i).c_str());
			}
		}
		if (!slowLogged && now - shellStartedAt > 15000) {
			slowLogged = true;
			log(L"shell: still starting after 15 s (%zu of %zu monitors covered)", found.covered(), found.monitors.size());
		}
		auto timeout = readyTimeoutMs();
		// Only until the wallpaper first shows: later the shell hides itself for fullscreen games.
		if (found.covered() > 0 && !found.hung) {
			if (found.covered() == found.monitors.size()) {
				onShellReady(now, found.covered(), found.monitors.size());
			} else if (partialSince == 0) {
				partialSince = now;
			} else if (now - partialSince > SHELL_PARTIAL_READY_MS) {
				onShellReady(now, found.covered(), found.monitors.size());
			}
		} else if (foregroundIsFullscreenApp()) {
			// A game in front: the shell steps aside for it, so no wallpaper is expected yet.
			shellStartedAt = now;
		} else if (now - shellStartedAt > timeout) {
			wchar_t text[96];
			swprintf_s(text, L"no wallpaper %llu s after starting", timeout / 1000);
			restartStuckShell(text);
		}
		return;
	}
	if (!found.hung) {
		shellHungSince = 0;
	} else if (shellHungSince == 0) {
		shellHungSince = now;
	} else if (now - shellHungSince > SHELL_HUNG_TIMEOUT_MS) {
		restartStuckShell(L"not responding for 20 s");
	}
}

void onShellExited() {
	if (!shellProcess || shuttingDown) return;
	DWORD code = 0;
	GetExitCodeProcess(shellProcess, &code);
	CloseHandle(shellProcess);
	shellProcess = nullptr;
	shellWait = nullptr;
	instance::clearShell();
	health::reset();
	evaluateBanners();
	log(L"shell: exited with code %lu (%s)", code, shellReady ? L"after it was up" : L"before it was up");
	nightlight::restore();
	if (options.nightlight) nightlight::start(guardReady);

	if (code == 0) {
		shutdown(0); // the shell quit on purpose
		return;
	}

	if (endedByWatchdog) {
		endedByWatchdog = false;
		SetTimer(hostWindow, TIMER_RESTART_SHELL, 1000, nullptr);
		return;
	}

	auto now = GetTickCount64();
	crashTimes[crashIndex++ % 3] = now;
	auto oldest = crashTimes[crashIndex % 3];
	if (crashIndex >= 3 && now - oldest < 60000) {
		abortLaunch(L"la shell se cerró varias veces seguidas");
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
	case WM_COPYDATA: {
		const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lParam);
		if (!shuttingDown && data && data->dwData == nightlight::COPYDATA)
			return nightlight::receive(data->lpData, data->cbData);
		if (!shuttingDown && data && data->dwData == health::COPYDATA_SERVICE_STATE) {
			health::receive(reinterpret_cast<HWND>(wParam), data->lpData, data->cbData); // NOLINT
			evaluateBanners();
			return TRUE;
		}
		return 0;
	}
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
			if (guardReady && guardProcess && WaitForSingleObject(guardProcess, 0) == WAIT_OBJECT_0) {
				guardReady = false;
				nightlight::restore(); // no tint without a live crash-recovery process
				log(L"nightlight disabled: guard exited");
			}
			nightlight::tick();
			if (uiHidden) {
				if (options.taskbar) taskbar::reapply();
				if (options.icons) desktop::reapplyIcons();
			}
			// Wallpaper changes rewrite ii's palette; Windows follows.
			if (options.theme) theme::apply();
		} else if (wParam == TIMER_RESTART_SHELL) {
			KillTimer(hwnd, TIMER_RESTART_SHELL);
			if (!shuttingDown && !startShell()) scheduleLaunchRetry(L"no se pudo lanzar el shell");
		} else if (wParam == TIMER_HEALTH) {
			evaluateBanners();
		} else if (wParam == TIMER_WATCHDOG) {
			watchShell();
		} else if (wParam == TIMER_BOOT_FAST) {
			// Explorer is still starting: hide its taskbar (and icons) as soon as they appear.
			if (uiHidden && options.taskbar) taskbar::reapply();
			if (uiHidden && options.icons) desktop::reapplyIcons();
			static ULONGLONG fastUntil = GetTickCount64() + BOOT_FAST_FOR_MS;
			if (GetTickCount64() > fastUntil) KillTimer(hwnd, TIMER_BOOT_FAST);
		} else if (wParam == TIMER_BOOT_END) {
			KillTimer(hwnd, TIMER_BOOT_END);
			booting = false;
			// Back to normal: games must not compete with the shell.
			SetPriorityClass(GetCurrentProcess(), NORMAL_PRIORITY_CLASS);
			if (shellProcess) SetPriorityClass(shellProcess, NORMAL_PRIORITY_CLASS);
			log(L"boot: priority back to normal");
		} else if (wParam == TIMER_AFTER_EXPLORER) {
			KillTimer(hwnd, TIMER_AFTER_EXPLORER);
			watchExplorer();
			// A start that gave the desktop back stays out of it until the shell is up.
			if (uiHidden || shellReady || options.shell.empty()) applyAll();
		}
		return 0;
	case WM_QUERYENDSESSION:
		// Put Windows' UI back before Explorer saves its settings for the logoff.
		log(L"session ending, restoring");
		uiHidden = false;
		restoreAll(false);
		return TRUE;
	case WM_ENDSESSION:
		if (wParam) shutdown(0);
		else { // logoff cancelled
			applyAll();
			if (options.nightlight) nightlight::start(guardReady);
		}
		return 0;
	case WM_CLOSE: shutdown(0); return 0;
	default: return DefWindowProcW(hwnd, msg, wParam, lParam);
	}
}

bool spawnGuard() {
	auto cmd = L"\"" + selfPath() + L"\" --guard " + std::to_wstring(GetCurrentProcessId());
	STARTUPINFOW si {};
	si.cb = sizeof(si);
	PROCESS_INFORMATION pi {};
	// Breakaway so the guard outlives a job that kills the host.
	if (CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW | CREATE_BREAKAWAY_FROM_JOB, nullptr, nullptr, &si, &pi)
	    || CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi))
	{
		CloseHandle(pi.hThread);
		guardProcess = pi.hProcess;
		log(L"guard started (%lu)", pi.dwProcessId);
		return true;
	} else {
		log(L"guard: CreateProcess failed (%lu)", GetLastError());
	}
	return false;
}

int runHost() {
	// A test instance (II_DATA_DIR) has its own mutex and window class, so it neither collides
	// with the real ii nor receives the close the installer sends to it.
	auto tag = instanceTag();
	auto* mutex = CreateMutexW(nullptr, TRUE, (L"Local\\ii-windows-host" + tag).c_str());
	if (GetLastError() == ERROR_ALREADY_EXISTS) {
		log(L"another ii-host is running");
		return 1;
	}

	// Nothing is hidden before the shell can at least be found: a missing executable must not
	// cost the user their taskbar.
	if (!options.shell.empty() && GetFileAttributesW(options.shell.c_str()) == INVALID_FILE_ATTRIBUTES) {
		log(L"shell executable not found (%lu), starting nothing: %s", GetLastError(), options.shell.c_str());
		std::wstring text = L"ii no pudo iniciarse: no se encuentra la shell.\nNo se ha cambiado nada en Windows.\n\n" + options.shell;
		alertUser(text);
		return 1;
	}

	auto className = L"IiHostWindow" + tag;
	WNDCLASSW wc {};
	wc.lpfnWndProc = wndProc;
	wc.hInstance = GetModuleHandleW(nullptr);
	wc.lpszClassName = className.c_str();
	RegisterClassW(&wc);
	// A real (hidden) top-level window: message-only windows miss the TaskbarCreated broadcast.
	hostWindow = CreateWindowExW(WS_EX_TOOLWINDOW, wc.lpszClassName, L"ii-host", WS_POPUP, 0, 0, 0, 0, nullptr, nullptr, wc.hInstance, nullptr);
	taskbarCreatedMsg = RegisterWindowMessageW(L"TaskbarCreated");
	ChangeWindowMessageFilterEx(hostWindow, taskbarCreatedMsg, MSGFLT_ALLOW, nullptr);

	// Never throttled as background work on battery (the keyboard hook lives here).
	PROCESS_POWER_THROTTLING_STATE throttling {};
	throttling.Version = PROCESS_POWER_THROTTLING_CURRENT_VERSION;
	throttling.ControlMask = PROCESS_POWER_THROTTLING_EXECUTION_SPEED;
	throttling.StateMask = 0;
	SetProcessInformation(GetCurrentProcess(), ProcessPowerThrottling, &throttling, sizeof(throttling));

	state::set(L"hostClean", 0);
	coldStart = coldQmlCache();
	setPhase(Phase::Preparing, options.shell.empty() ? L"no shell requested" : L"shell requested");
	instance::recordHost();
	bench(L"host-ready-to-launch");
	guardReady = spawnGuard();

	if (!RegisterHotKey(hostWindow, HOTKEY_PANIC, MOD_CONTROL | MOD_ALT | MOD_SHIFT | MOD_NOREPEAT, 'R')) {
		log(L"panic hotkey Ctrl+Alt+Shift+R unavailable (%lu)", GetLastError());
	}

	if (options.boot) {
		booting = true;
		SetPriorityClass(GetCurrentProcess(), HIGH_PRIORITY_CLASS);
		SetTimer(hostWindow, TIMER_BOOT_FAST, BOOT_FAST_MS, nullptr);
		SetTimer(hostWindow, TIMER_BOOT_END, BOOT_HIGH_PRIORITY_MS, nullptr);
		log(L"boot: high priority, fast taskbar checks, splash");
	}

	// A cover until the shell's own wallpaper is up: the windows first (plain colour), the shell
	// right after, and only then the wallpaper image is decoded, so the shell is not kept waiting
	// for it.
	if (options.splash) splash::show();
	applyAll();
	if (options.shell.empty()) setPhase(Phase::Active, L"no shell to wait for");
	else if (!startShell()) scheduleLaunchRetry(L"no se pudo lanzar el shell");
	if (options.splash) splash::loadImages();
	// Everything below (gamma ramps through GDI, the hook thread) can take a moment and the
	// shell's load doesn't depend on it.
	if (options.nightlight) nightlight::start(guardReady);
	watchExplorer();
	SetTimer(hostWindow, TIMER_REAPPLY, 2000, nullptr);
	SetTimer(hostWindow, TIMER_WATCHDOG, watchdogMs(), nullptr);
	SetTimer(hostWindow, TIMER_HEALTH, 1000, nullptr); // heartbeat expiry is judged on the host's own clock
	if (options.hook) keyboard::install(hostWindow);

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
		// Only the shell this host recorded (it is normally already gone with the host's job).
		instance::stopShell(selfDir() + L"\\quickshell\\quickshell.exe");
		restoreAll(false);
		state::set(L"hostClean", 1);
	}
	return 0;
}

// Stops the recorded host (it restores on a normal close) and shell, then restores everything
// itself. Another quickshell.exe, or another ii-host.exe from elsewhere, is never touched.
int runRescue(bool restartExplorer) {
	log(L"rescue requested");
	ProcessIdentity host;
	if (instance::readHost(host)) {
		if (host.pid != GetCurrentProcessId() && sameProcess(host)) {
			log(L"rescue: stopping the recorded host (%lu)", host.pid);
			terminateIfSame(host, 3000);
		} else {
			log(L"rescue: recorded host %lu is gone (or its PID was reused): not touching it", host.pid);
		}
	} else {
		// A host from before records existed: the one running this very executable.
		instance::stopByExactPath(selfPath(), 3000);
	}
	instance::stopShell(selfDir() + L"\\quickshell\\quickshell.exe");
	restoreAll(restartExplorer, true); // the rescue puts back what the state file says, unconditionally
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
		else if (a == L"--no-nightlight") options.nightlight = false;
		else if (a == L"--boot") options.boot = true;
		else if (a == L"--no-splash") options.splash = false;
		else if (a == L"--rescue" || a == L"--restore") rescue = true;
		else if (a == L"--restart-explorer") restartExplorer = true;
		else if (a == L"--guard") guardPid = static_cast<DWORD>(_wtoi(next().c_str()));
	}
	LocalFree(argv);

	if (guardPid) return runGuard(guardPid);
	if (rescue) return runRescue(restartExplorer);
	return runHost();
}
