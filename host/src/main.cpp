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
#include "configtool.h"
#include "nightlight.h"
#include "rollout.h"

#include <objbase.h>
#include <shellapi.h>
#include <shlobj.h>
#include <tlhelp32.h>
#include <dxgi1_6.h>
#include <wtsapi32.h>

using namespace ii;


int gpuPolicy(bool quiet); // below wWinMain's helpers
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
// Once a second from a timer on the shell's GUI thread (Quickshell's win32 backend), wParam = its pid. A shell whose
// GUI thread stands still (a graphics driver reset under a heavy game, an endless wait) keeps its process alive, and
// the user is left with neither ii nor a taskbar: only the missing heartbeat tells.
constexpr UINT WM_II_HEARTBEAT = WM_APP + 5;
constexpr ULONGLONG SHELL_HEARTBEAT_TIMEOUT_MS = 5000;
constexpr ULONGLONG SHELL_BUSY_LIMIT_MS = 30000; // silent but using the processor: working, up to this long
// Freezes this close together, with a game in front, mean the game and ii cannot share the machine: wait for the game.
constexpr int SHELL_FROZEN_LIMIT = 3;
constexpr ULONGLONG SHELL_FROZEN_SPAN_MS = 5 * 60 * 1000;
// A shell that is up but has no window on any screen (its windows went with a lost graphics device).
constexpr ULONGLONG SHELL_WINDOWS_LOST_MS = 20000;
constexpr UINT_PTR TIMER_NOTICE_END = 8;
constexpr UINT_PTR TIMER_LONE_WIN = 9;

struct Options {
	std::wstring shell;
	std::wstring config;
	bool taskbar = true;
	bool icons = true;
	bool hook = true;
	bool banners = true;
	bool theme = true;
	bool nightlight = true;
	bool windowfx = true; // light transparency for other programs' windows (windowfx.cpp)
	bool boot = false;
	bool splash = true;
};

Options options;
HWND hostWindow = nullptr;
UINT taskbarCreatedMsg = 0;
HWND knownExplorerTray = nullptr; // the Explorer taskbar window we know of: a different one means Explorer restarted
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
// Heartbeat of the current shell (0: none yet, an older shell or one still loading) and the freeze bookkeeping.
ULONGLONG lastHeartbeat = 0;
ULONGLONG cpuAtHeartbeat = 0; // the GUI thread's processor time at the last heartbeat
bool busyLogged = false;
HANDLE shellThread = nullptr; // the shell's main (GUI) thread, for its processor time
ULONGLONG heartbeatGraceUntil = 0; // after a resume or an unlock the first heartbeat may come late
ULONGLONG frozenTimes[SHELL_FROZEN_LIMIT] = {};
int frozenIndex = 0;
ULONGLONG windowsLostSince = 0;
bool sessionLocked = false;
// The shell froze again and again with this game in front: no new shell until the game ends (or stays away).
// The handle may be missing (an anti-cheat that denies it): then the game is followed by its pid.
bool waitingForGame = false;
HANDLE waitingGame = nullptr;
DWORD waitingGamePid = 0;
ULONGLONG waitingGameCreated = 0; // its creation time, so a reused pid is not taken for the game
ULONGLONG gameAwaySince = 0;
bool noticeShown = false;

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

// --- config.json guard (D01) ---------------------------------------------------------------
// Before the shell starts, a damaged config.json is put aside and the last good one restored;
// once the shell is up (and when it ends cleanly) the current file is remembered as the last good one.
// Isolated test runs (II_DATA_DIR without II_CONFIG_DIR) never look at the real user's config.

std::vector<std::wstring> configNotices; // shown by the shell once it is up

bool configGuardEnabled() {
	wchar_t buffer[8];
	return GetEnvironmentVariableW(L"II_CONFIG_DIR", buffer, 8) > 0 || GetEnvironmentVariableW(L"II_DATA_DIR", buffer, 8) == 0;
}

std::wstring fromUtf8(const std::string& text) {
	if (text.empty()) return {};
	auto n = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
	std::wstring out(static_cast<size_t>(n), L'\0');
	MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), n);
	return out;
}

void guardConfig() {
	if (!configGuardEnabled()) return;
	auto outcome = configtool::guard();
	log(L"config: %s", fromUtf8(outcome.message).c_str());
	for (const auto& d: outcome.details) log(L"config:   %s", fromUtf8(d).c_str());
	if (outcome.userShouldKnow()) configNotices.push_back(fromUtf8(outcome.message));
}

void rememberGoodConfig() {
	if (!configGuardEnabled()) return;
	auto outcome = configtool::keepGood();
	if (outcome.action == configtool::Outcome::Action::Saved || outcome.action == configtool::Outcome::Action::NotSaved) log(L"config: %s", fromUtf8(outcome.message).c_str());
}

// The shell's notification sink is a window of the shell itself; the same message ii-shim notify-send uses.
void tellUserThroughShell(const std::wstring& summary, const std::wstring& body) {
	if (noUi()) {
		log(L"config: (no UI) %s", summary.c_str());
		return;
	}
	auto* sink = FindWindowW(L"IiShellNotificationSink", nullptr);
	if (!sink) return;
	const wchar_t sep = 0x1f; // the field separator ii-shim notify-send uses
	std::wstring payload = std::wstring(L"ii-windows") + sep + summary + sep + body + sep + sep + L"critical" + sep + sep + L"0";
	COPYDATASTRUCT data {};
	data.dwData = 0x49490010;
	data.cbData = static_cast<DWORD>((payload.size() + 1) * sizeof(wchar_t));
	data.lpData = payload.data();
	DWORD_PTR result = 0;
	SendMessageTimeoutW(sink, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG, 2000, &result);
}

void deliverConfigNotices() {
	for (const auto& notice: configNotices) tellUserThroughShell(L"ii: your settings file was checked", notice);
	configNotices.clear();
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

	guardConfig(); // a damaged config.json must not be what the shell starts from
	health::prepareLaunch(hostWindow); // the shell inherits the instance id and where to report
	// Nobody edits an installed config: Quickshell watching its ~600 QML files (and their folders) for a
	// live reload only cost start-up time and watcher threads. II_WATCH_QML=1 keeps it, for development.
	if (!GetEnvironmentVariableW(L"II_WATCH_QML", nullptr, 0)) SetEnvironmentVariableW(L"QS_DISABLE_FILE_WATCHER", L"1");
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
	if (shellThread) CloseHandle(shellThread);
	shellThread = pi.hThread; // kept: its processor time tells a busy GUI thread from a frozen one

	shellProcess = pi.hProcess;
	shellPid = pi.dwProcessId;
	shellStartedAt = GetTickCount64();
	shellReady = false;
	shellHungSince = 0;
	lastHeartbeat = 0;
	windowsLostSince = 0;
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

void removeNotice(); // the host's own Windows notification (a frozen shell), below

// Logs a step that kept the host's message loop busy (it also runs the readiness check and the keyboard).
struct SlowStep {
	const wchar_t* name;
	ULONGLONG started = GetTickCount64();
	explicit SlowStep(const wchar_t* n): name(n) {}
	~SlowStep() {
		auto took = GetTickCount64() - started;
		if (took >= 150) log(L"slow: %s took %llu ms", name, took);
	}
};

void applyAll() {
	uiHidden = true;
	bench(L"apply-begin");
	if (options.taskbar) { SlowStep s(L"taskbar::hide"); taskbar::hide(); }
	if (options.icons) { SlowStep s(L"desktop::hideIcons"); desktop::hideIcons(); }
	// Banners are not touched here: see evaluateBanners().
	if (options.theme) { SlowStep s(L"theme::start"); theme::start(); }
	if (options.windowfx) { SlowStep s(L"windowfx::start"); windowfx::start(); }
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
	removeNotice();
	if (waitingGame) CloseHandle(waitingGame);
	waitingGame = nullptr;
	waitingForGame = false;
	if (code == 0 && shellReady) rememberGoodConfig(); // a clean end: what the shell last wrote is good
	splash::close();
	windowfx::stop();
	restoreAll(false);
	uiHidden = false;
	state::set(L"hostClean", 1);
	setPhase(code == 0 ? Phase::Recovered : Phase::Failed);
}

void shutdown(int code) {
	screentime::write(); // the minutes since the last write
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

// II_TEST_FULLSCREEN=1: tests act as if a game filled the screen, without putting one on the tester's desktop.
bool testFullscreen() {
	static const bool on = GetEnvironmentVariableW(L"II_TEST_FULLSCREEN", nullptr, 0) > 0;
	return on;
}

bool foregroundIsFullscreenApp() {
	if (testFullscreen()) return true;
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

// A game rather than any window that fills the screen: exclusive fullscreen, or borderless and covering the monitor
// without being a maximized window with a title bar (the same rule the keyboard uses to step aside).
bool gameInFront() {
	if (testFullscreen()) return true;
	if (!foregroundIsFullscreenApp()) return false;
	auto* fg = GetForegroundWindow();
	QUERY_USER_NOTIFICATION_STATE state {};
	if (SUCCEEDED(SHQueryUserNotificationState(&state)) && (state == QUNS_RUNNING_D3D_FULL_SCREEN || state == QUNS_PRESENTATION_MODE)) return true;
	auto style = GetWindowLongPtrW(fg, GWL_STYLE);
	return (style & WS_CAPTION) != WS_CAPTION && !IsZoomed(fg);
}

void restartStuckShell(const wchar_t* why) {
	log(L"shell: %s, restarting it", why);
	if (++stuckRestarts > SHELL_STUCK_RESTARTS) {
		wchar_t text[160];
		swprintf_s(text, L"la shell se quedó colgada %d veces seguidas", SHELL_STUCK_RESTARTS);
		abortLaunch(text);
		return;
	}
	// Give Explorer back while the next one starts, instead of keeping the user in front of a cover (or of a
	// frozen ii with no taskbar) for another round. It is hidden again when the new shell is really up (onShellReady).
	exposeExplorer(why);
	shellHungSince = 0;
	endedByWatchdog = true;
	TerminateProcess(shellProcess, 1); // onShellExited starts a new one
}

ULONGLONG heartbeatTimeoutMs() {
	wchar_t value[16];
	if (GetEnvironmentVariableW(L"II_TEST_HEARTBEAT_MS", value, _countof(value)) > 0) {
		auto ms = _wcstoui64(value, nullptr, 10);
		if (ms >= 500) return ms;
	}
	return SHELL_HEARTBEAT_TIMEOUT_MS;
}

// What is in front, for the log of a freeze: game.exe "Title" (exclusive fullscreen).
std::wstring describeForeground(DWORD& pid) {
	pid = 0;
	auto* fg = GetForegroundWindow();
	if (!fg) return L"(nothing)";
	GetWindowThreadProcessId(fg, &pid);
	std::wstring exe = L"?";
	if (auto* process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid)) {
		wchar_t path[MAX_PATH * 2];
		DWORD size = static_cast<DWORD>(_countof(path));
		if (QueryFullProcessImageNameW(process, 0, path, &size)) {
			exe.assign(path, size);
			exe = exe.substr(exe.find_last_of(L"\\/") + 1);
		}
		CloseHandle(process);
	}
	wchar_t title[128] {};
	GetWindowTextW(fg, title, _countof(title));
	QUERY_USER_NOTIFICATION_STATE state {};
	auto exclusive = SUCCEEDED(SHQueryUserNotificationState(&state)) && (state == QUNS_RUNNING_D3D_FULL_SCREEN || state == QUNS_PRESENTATION_MODE);
	return exe + L" \"" + title + L"\"" + (exclusive ? L" (exclusive fullscreen)" : foregroundIsFullscreenApp() ? L" (covers the screen)" : L"");
}

// A Windows notification from the host itself (the shell, and its notifications, are gone at that moment). The icon
// goes after half a minute.
void showNotice(const wchar_t* title, const wchar_t* text) {
	log(L"notice: %s: %s", title, text);
	if (noUi()) return;
	NOTIFYICONDATAW nid {};
	nid.cbSize = sizeof(nid);
	nid.hWnd = hostWindow;
	nid.uID = 1;
	nid.uFlags = NIF_ICON | NIF_TIP | NIF_INFO;
	nid.hIcon = LoadIconW(nullptr, IDI_INFORMATION);
	nid.dwInfoFlags = NIIF_INFO;
	wcsncpy_s(nid.szTip, L"ii-windows", _TRUNCATE);
	wcsncpy_s(nid.szInfoTitle, title, _TRUNCATE);
	wcsncpy_s(nid.szInfo, text, _TRUNCATE);
	if (noticeShown) Shell_NotifyIconW(NIM_DELETE, &nid);
	noticeShown = Shell_NotifyIconW(NIM_ADD, &nid) != FALSE;
	if (noticeShown) SetTimer(hostWindow, TIMER_NOTICE_END, 30000, nullptr);
}

void removeNotice() {
	if (!noticeShown) return;
	NOTIFYICONDATAW nid {};
	nid.cbSize = sizeof(nid);
	nid.hWnd = hostWindow;
	nid.uID = 1;
	Shell_NotifyIconW(NIM_DELETE, &nid);
	noticeShown = false;
}

// The shell is alive but frozen (or lost its windows). In this order: Windows' taskbar, icons and banners come back
// at once, then exactly the process this host started is ended (its handle, not a name or a PID), and a new one
// starts, unless it keeps freezing.
void onShellFrozen(const wchar_t* why) {
	if (!shellProcess || shuttingDown) return;
	auto now = GetTickCount64();
	DWORD fgPid = 0;
	auto front = describeForeground(fgPid);
	auto game = gameInFront();
	// II_TEST_GAME_PID: the process tests use as the game in front.
	wchar_t testGame[16];
	if (GetEnvironmentVariableW(L"II_TEST_GAME_PID", testGame, _countof(testGame)) > 0) fgPid = static_cast<DWORD>(_wtoi(testGame));
	log(L"hang: %s; in front: %s; shell up for %llu s", why, front.c_str(), (now - shellStartedAt) / 1000);
	exposeExplorer(why);
	if (bannersSuppressed) {
		banners::restore();
		bannersSuppressed = false;
	}
	frozenTimes[frozenIndex++ % SHELL_FROZEN_LIMIT] = now;
	auto repeated = frozenIndex >= SHELL_FROZEN_LIMIT && now - frozenTimes[frozenIndex % SHELL_FROZEN_LIMIT] < SHELL_FROZEN_SPAN_MS;
	if (repeated && !game) {
		abortLaunch(L"la shell se congeló varias veces seguidas");
		return;
	}
	lastHeartbeat = 0;
	shellHungSince = 0;
	windowsLostSince = 0;
	endedByWatchdog = true;
	if (repeated) {
		waitingForGame = true;
		// II_TEST_GAME_NO_HANDLE: tests stand for an anti-cheat that denies the handle.
		waitingGame = GetEnvironmentVariableW(L"II_TEST_GAME_NO_HANDLE", nullptr, 0) > 0 ? nullptr : OpenProcess(SYNCHRONIZE, FALSE, fgPid);
		waitingGamePid = fgPid;
		ProcessIdentity identity;
		waitingGameCreated = identityOf(fgPid, identity) ? identity.created : 0;
		if (!waitingGame) log(L"hang: no handle on the game (%lu): following it by its pid", GetLastError());
		gameAwaySince = 0;
		log(L"hang: %d freezes in a few minutes with a game in front: ii waits until it ends", SHELL_FROZEN_LIMIT);
		showNotice(L"ii se pausó mientras juegas",
		           L"La interfaz de ii se congeló varias veces con este juego. Tienes la barra de Windows; ii vuelve sola cuando cierres el juego.");
	}
	TerminateProcess(shellProcess, 1); // onShellExited starts a new one (or not, while waitingForGame)
}

// CPU time (100 ns units) the shell's GUI thread (its main thread) has used so far.
ULONGLONG shellGuiCpu() {
	FILETIME created, exited, kernel, user;
	if (!shellThread || !GetThreadTimes(shellThread, &created, &exited, &kernel, &user)) return 0;
	auto value = [](const FILETIME& f) { return (static_cast<ULONGLONG>(f.dwHighDateTime) << 32) | f.dwLowDateTime; };
	return value(kernel) + value(user);
}

// Once a second, on the host's clock. A silent GUI thread that is busy (loading QML on a slow PC, compiling a page
// opened for the first time) is not frozen: it gets up to SHELL_BUSY_LIMIT_MS. One that stands still, waiting on a
// graphics driver or on anything else, uses no processor time and is acted on after the timeout.
void checkHeartbeat() {
	if (!shellProcess || shuttingDown || !shellReady || waitingForGame || lastHeartbeat == 0) return;
	auto now = GetTickCount64();
	if (now < heartbeatGraceUntil) return;
	auto silent = now - lastHeartbeat;
	if (silent < heartbeatTimeoutMs()) return;
	// 100 ns units over ms of silence: more than a quarter of a core on average counts as working.
	auto busy = (shellGuiCpu() - cpuAtHeartbeat) / 10000 > silent / 4;
	if (busy && silent < SHELL_BUSY_LIMIT_MS) {
		if (!busyLogged) log(L"shell: GUI thread silent for %llu ms but working (processor time rising): waiting", silent);
		busyLogged = true;
		return;
	}
	wchar_t text[128];
	swprintf_s(text, L"the shell's GUI thread has been silent for %llu ms%s", silent, busy ? L" (busy all along)" : L"");
	onShellFrozen(text);
}

// Without a handle: is the game's pid still in the process list, and still the same process (creation time)?
// A process snapshot needs no access to the game itself.
bool gameStillRunning() {
	auto* snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
	if (snapshot == INVALID_HANDLE_VALUE) return true; // cannot tell: keep waiting (it also ends after a minute away)
	PROCESSENTRY32W entry {};
	entry.dwSize = sizeof(entry);
	auto found = false;
	for (auto ok = Process32FirstW(snapshot, &entry); ok; ok = Process32NextW(snapshot, &entry)) {
		if (entry.th32ProcessID == waitingGamePid) {
			found = true;
			break;
		}
	}
	CloseHandle(snapshot);
	if (!found) return false;
	ProcessIdentity identity;
	return waitingGameCreated == 0 || !identityOf(waitingGamePid, identity) || identity.created == waitingGameCreated;
}

// While ii waits for a game: a new shell once the game has ended, or has not been in front for a minute.
void checkWaitingGame() {
	if (!waitingForGame || shuttingDown) return;
	auto now = GetTickCount64();
	auto ended = waitingGame ? WaitForSingleObject(waitingGame, 0) == WAIT_OBJECT_0 : !gameStillRunning();
	auto away = processIdOf(GetForegroundWindow()) != waitingGamePid;
	if (!away) gameAwaySince = 0;
	else if (gameAwaySince == 0) gameAwaySince = now;
	if (!ended && !(gameAwaySince && now - gameAwaySince > 60000)) return;
	log(L"hang: the game %s, starting ii again", ended ? L"ended" : L"has been away for a minute");
	if (waitingGame) CloseHandle(waitingGame);
	waitingGame = nullptr;
	waitingForGame = false;
	waitingGamePid = 0;
	frozenIndex = 0;
	for (auto& t: frozenTimes) t = 0;
	removeNotice();
	if (!shellProcess) SetTimer(hostWindow, TIMER_RESTART_SHELL, 500, nullptr);
}

// A lone Win press went to ii's search. Over a window that fills its screen (a game ii's shortcuts did not step aside
// for) or with a shell that stopped beating, ii may be unable to show anything: if no window of the shell has come
// to the front shortly after, Windows' own Start opens instead. A key is never swallowed with nothing on screen.
// A launcher-like window of the shell is on screen: visible, always on top and covering a whole monitor (the
// overview). Windows may refuse it the foreground over a game while it is plainly showing.
bool shellLauncherVisible() {
	if (!shellPid) return false;
	struct Search {
		DWORD pid;
		bool found = false;
	} search {shellPid};
	EnumWindows(
	    [](HWND hwnd, LPARAM data) -> BOOL {
		    auto* s = reinterpret_cast<Search*>(data); // NOLINT
		    if (processIdOf(hwnd) != s->pid || !IsWindowVisible(hwnd) || !(GetWindowLongW(hwnd, GWL_EXSTYLE) & WS_EX_TOPMOST)) return TRUE;
		    RECT r {};
		    MONITORINFO info {};
		    info.cbSize = sizeof(info);
		    if (GetWindowRect(hwnd, &r) && GetMonitorInfoW(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &info) && r.left <= info.rcMonitor.left
		        && r.top <= info.rcMonitor.top && r.right >= info.rcMonitor.right && r.bottom >= info.rcMonitor.bottom)
		    {
			    s->found = true;
			    return FALSE;
		    }
		    return TRUE;
	    },
	    reinterpret_cast<LPARAM>(&search) // NOLINT
	);
	return search.found;
}

void onLoneWin() {
	if (shuttingDown) return;
	auto* fg = GetForegroundWindow();
	if (shellPid && processIdOf(fg) == shellPid) return; // ii is in front: this press closes its search
	if (shellLauncherVisible()) return;                   // its search shows (without the foreground): this press closes it
	auto now = GetTickCount64();
	auto silent = !shellProcess || (lastHeartbeat != 0 && now - lastHeartbeat > 2000);
	if (!silent && !foregroundIsFullscreenApp()) return;
	SetTimer(hostWindow, TIMER_LONE_WIN, silent ? 50 : 700, nullptr);
}

void onLoneWinTimeout() {
	KillTimer(hostWindow, TIMER_LONE_WIN);
	if (shuttingDown || (shellPid && processIdOf(GetForegroundWindow()) == shellPid)) return;
	if (shellLauncherVisible()) {
		log(L"keyboard: ii's search shows over the window in front (without the foreground): no Start");
		return;
	}
	DWORD pid = 0;
	auto front = describeForeground(pid);
	log(L"keyboard: ii did not show for the Win key over %s: Windows' Start instead", front.c_str());
	keyboard::openStart();
}

void onShellReady(ULONGLONG now, size_t covered, size_t total) {
	shellReady = true;
	stuckRestarts = 0;
	lastHeartbeat = 0; // judged from the first heartbeat after this: the load before it may have kept the GUI thread busy
	bench(covered < total ? L"ready-partial" : L"ready");
	// A freshly installed version is "pending" until its host says it works; tell the launcher.
	if (rollout::markVerified(selfDir())) log(L"runtime: this version is now verified");
	SetTimer(hostWindow, TIMER_WATCHDOG, watchdogMs(), nullptr); // back to the slow housekeeping tick
	setPhase(Phase::Active, L"shell is up");
	rememberGoodConfig(); // once per start, after it came up: not on every change
	deliverConfigNotices();
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

// The "are you alive" ping is asynchronous: SendMessageTimeout waited up to 250 ms on every tick while the
// shell was busy loading, and the host's thread (the welcome cover's animation, the panic key...) stood
// still meanwhile. The answer now arrives through pong() in the host's message loop.
ULONGLONG pingSentAt = 0;
ULONGLONG pongAt = 0;
DWORD pingPid = 0;
HWND pingWindow = nullptr;
bool pingPending = false;

VOID CALLBACK pong(HWND, UINT, ULONG_PTR pid, LRESULT) {
	if (static_cast<DWORD>(pid) != pingPid) return; // an answer from a shell that is gone
	pingPending = false;
	pongAt = GetTickCount64();
}

void watchShell() {
	if (!shellProcess || shuttingDown) return;
	if (!shellReady) bench(L"watch-tick");
	ShellWindows found;
	found.pid = shellPid;
	EnumDisplayMonitors(nullptr, nullptr, collectMonitor, reinterpret_cast<LPARAM>(&found.monitors)); // NOLINT
	EnumWindows(inspectShellWindow, reinterpret_cast<LPARAM>(&found)); // NOLINT
	// IsHungAppWindow skips tool/layered windows like the shell's: ask one directly.
	auto now = GetTickCount64();
	// Unanswered for this long = not responding (shorter while it comes up, as the old blocking wait was).
	const ULONGLONG pingMs = shellReady ? 1000 : 250;
	// A new shell, or the window asked has closed since (its answer will never come): ask again.
	if (pingPid != shellPid || (pingPending && !IsWindow(pingWindow))) {
		pingPid = shellPid;
		pingPending = false;
	}
	if (pingPending && now - pingSentAt > pingMs) found.hung = true;
	if (!pingPending && found.any && SendMessageCallbackW(found.any, WM_NULL, 0, 0, pong, shellPid)) {
		pingPending = true;
		pingSentAt = now;
		pingWindow = found.any;
	}
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
	// Up, answering, but no window on any screen while nothing fullscreen is in front: its windows went (a lost
	// graphics device) and the user sees Explorer's bare desktop with no taskbar.
	if (found.covered() == 0 && !found.monitors.empty() && !sessionLocked && !foregroundIsFullscreenApp() && now >= heartbeatGraceUntil) {
		if (windowsLostSince == 0) windowsLostSince = now;
		else if (now - windowsLostSince > SHELL_WINDOWS_LOST_MS) {
			onShellFrozen(L"no window of the shell on any screen for 20 s");
			return;
		}
	} else {
		windowsLostSince = 0;
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
		if (!waitingForGame) SetTimer(hostWindow, TIMER_RESTART_SHELL, 1000, nullptr);
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
		auto* tray = explorerTray();
		if (tray && tray == knownExplorerTray) return 0;
		knownExplorerTray = tray;
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
	case keyboard::WM_II_VOLUME: volume::handleKey(static_cast<unsigned>(wParam)); return 0;
	case keyboard::WM_II_LONE_WIN: onLoneWin(); return 0;
	case WM_II_SHELL_EXITED: onShellExited(); return 0;
	case WM_II_HEARTBEAT:
		if (shellProcess && static_cast<DWORD>(wParam) == shellPid) {
			lastHeartbeat = GetTickCount64();
			cpuAtHeartbeat = shellGuiCpu();
			busyLogged = false;
		}
		return 0;
	case WM_POWERBROADCAST:
		// Asleep, nothing beats; awake, the shell needs a moment before its timers run again.
		if (wParam == PBT_APMSUSPEND) heartbeatGraceUntil = ~0ULL;
		else if (wParam == PBT_APMRESUMEAUTOMATIC || wParam == PBT_APMRESUMESUSPEND) {
			heartbeatGraceUntil = GetTickCount64() + 15000;
			windowsLostSince = 0;
		}
		return TRUE;
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
			{ SlowStep s(L"nightlight::tick"); nightlight::tick(); }
			if (uiHidden) {
				if (options.taskbar) { SlowStep s(L"taskbar::reapply"); taskbar::reapply(); }
				if (options.icons) { SlowStep s(L"desktop::reapplyIcons"); desktop::reapplyIcons(); }
			}
			// Wallpaper changes rewrite ii's palette; Windows follows.
			if (options.theme) { SlowStep s(L"theme::apply"); theme::apply(); }
		} else if (wParam == TIMER_RESTART_SHELL) {
			KillTimer(hwnd, TIMER_RESTART_SHELL);
			if (!shuttingDown && !startShell()) scheduleLaunchRetry(L"no se pudo lanzar el shell");
		} else if (wParam == TIMER_HEALTH) {
			{ SlowStep s(L"evaluateBanners"); evaluateBanners(); }
			// The next logon's welcome cover uses a small blurred copy of the wallpaper (own thread).
			if (shellReady && options.splash) splash::refreshCache();
			if (options.windowfx && uiHidden) { SlowStep s(L"windowfx::tick"); windowfx::tick(); }
			if (options.hook) { SlowStep s(L"keyboard::refreshContext"); keyboard::refreshContext(); } // reconcile what the hook reads (shell, foreground, shortcuts.ini)
			screentime::tick(shellPid); // the "Usage" tab of the right sidebar
			checkHeartbeat();
			checkWaitingGame();
		} else if (wParam == TIMER_WATCHDOG) {
			SlowStep s(L"watchShell");
			watchShell();
		} else if (wParam == TIMER_BOOT_FAST) {
			// Explorer is still starting: hide its taskbar (and icons) as soon as they appear.
			if (uiHidden && options.taskbar) { SlowStep s(L"boot taskbar::reapply"); taskbar::reapply(); }
			if (uiHidden && options.icons) { SlowStep s(L"boot desktop::reapplyIcons"); desktop::reapplyIcons(); }
			static ULONGLONG fastUntil = GetTickCount64() + BOOT_FAST_FOR_MS;
			if (GetTickCount64() > fastUntil) KillTimer(hwnd, TIMER_BOOT_FAST);
		} else if (wParam == TIMER_BOOT_END) {
			KillTimer(hwnd, TIMER_BOOT_END);
			booting = false;
			// Back to normal: games must not compete with the shell.
			SetPriorityClass(GetCurrentProcess(), NORMAL_PRIORITY_CLASS);
			if (shellProcess) SetPriorityClass(shellProcess, NORMAL_PRIORITY_CLASS);
			log(L"boot: priority back to normal");
		} else if (wParam == TIMER_LONE_WIN) {
			onLoneWinTimeout();
		} else if (wParam == TIMER_NOTICE_END) {
			KillTimer(hwnd, TIMER_NOTICE_END);
			removeNotice();
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
	case WM_WTSSESSION_CHANGE:
		// Lock, unlock, console/remote switch: a key-up may have been lost on the secure desktop.
		log(L"session change %llu: key state reset", static_cast<unsigned long long>(wParam));
		if (wParam == WTS_SESSION_LOCK) sessionLocked = true;
		if (wParam == WTS_SESSION_UNLOCK) {
			sessionLocked = false;
			heartbeatGraceUntil = GetTickCount64() + 10000;
			windowsLostSince = 0;
		}
		screentime::sessionChanged(wParam);
		if (options.hook) {
			keyboard::resetState();
			keyboard::refreshContext();
		}
		return 0;
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
		return 17; // the launcher knows this one: nothing failed, there is simply already a host
	}

	// Nothing is hidden before the shell can at least be found: a missing executable must not
	// cost the user their taskbar.
	if (!options.shell.empty() && GetFileAttributesW(options.shell.c_str()) == INVALID_FILE_ATTRIBUTES) {
		log(L"shell executable not found (%lu), starting nothing: %s", GetLastError(), options.shell.c_str());
		std::wstring text = L"ii no pudo iniciarse: no se encuentra la shell.\nNo se ha cambiado nada en Windows.\n\n" + options.shell;
		alertUser(text);
		return 1;
	}

	// The welcome cover first of all (at logon every millisecond the desktop shows unfinished counts);
	// it is only windows, and it goes as soon as anything below fails (exposeExplorer, restoreAndStop).
	if (options.splash) splash::show();

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
	// The taskbar that is there already: the shell's own tray broadcasts TaskbarCreated as it starts, and that
	// was taken for an Explorer restart (everything applied a second time a second after start).
	knownExplorerTray = explorerTray();

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
	gpuPolicy(false); // the GPUs in the log: the first thing to look at in a report of stalls
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

	applyAll();
	if (options.shell.empty()) setPhase(Phase::Active, L"no shell to wait for");
	else if (!startShell()) scheduleLaunchRetry(L"no se pudo lanzar el shell");
	// Everything below (gamma ramps through GDI, the hook thread) can take a moment and the
	// shell's load doesn't depend on it.
	if (options.nightlight) nightlight::start(guardReady);
	watchExplorer();
	SetTimer(hostWindow, TIMER_REAPPLY, 2000, nullptr);
	// The fast tick startShell() set while the shell comes up must stay: this line used to put the slow 5 s
	// housekeeping tick on top of it, so the shell was only noticed as ready ~5 s after launch even when its
	// wallpaper had been up for 2.
	SetTimer(hostWindow, TIMER_WATCHDOG, (shellProcess && !shellReady) ? std::min<UINT>(250, watchdogMs()) : watchdogMs(), nullptr);
	SetTimer(hostWindow, TIMER_HEALTH, 1000, nullptr); // heartbeat expiry is judged on the host's own clock
	if (options.hook) keyboard::install(hostWindow);
	WTSRegisterSessionNotification(hostWindow, NOTIFY_FOR_THIS_SESSION);

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

// Which GPU ii should draw on (asked by the installer, logged at every start). Windows' "power saving"
// preference is only right when the power-saving GPU is the one driving the screen (laptops: the
// integrated GPU has the panel). On a desktop with a graphics card and the integrated GPU switched on,
// it made ii draw on a GPU with no screen and Windows copied every frame across: animations and the
// wallpaper stalled, colours changed late. The same happened the other way on gaming laptops: an external
// monitor (wired to the NVIDIA GPU) or a MUX switch in "dedicated GPU" mode puts the main screen on the big
// GPU while ii drew on the integrated one. So ii draws on the GPU that drives the main screen.
// Exit 10 = power saving GPU, 12 = high performance GPU, 11 = leave it to Windows (one GPU, or unknown).
int gpuPolicy(bool quiet) {
	IDXGIFactory6* factory = nullptr;
	if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) return 11;
	int adapters = 0;
	int primaryOn = -1; // index (in power-saving order) of the GPU with the main screen
	for (UINT i = 0;; ++i) {
		IDXGIAdapter1* adapter = nullptr;
		if (factory->EnumAdapterByGpuPreference(i, DXGI_GPU_PREFERENCE_MINIMUM_POWER, IID_PPV_ARGS(&adapter)) != S_OK) break;
		DXGI_ADAPTER_DESC1 desc {};
		adapter->GetDesc1(&desc);
		if (!(desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)) {
			int screens = 0;
			bool primary = false;
			IDXGIOutput* output = nullptr;
			for (UINT o = 0; adapter->EnumOutputs(o, &output) == S_OK; ++o) {
				DXGI_OUTPUT_DESC od {};
				MONITORINFO info {};
				info.cbSize = sizeof(info);
				if (SUCCEEDED(output->GetDesc(&od)) && od.AttachedToDesktop) {
					++screens;
					if (GetMonitorInfoW(od.Monitor, &info) && (info.dwFlags & MONITORINFOF_PRIMARY)) primary = true;
				}
				output->Release();
				output = nullptr;
			}
			if (primary && primaryOn < 0) primaryOn = adapters;
			if (!quiet) log(L"gpu: %s (%s, %d screen(s)%s, %llu MB)", desc.Description, adapters == 0 ? L"power saving" : L"other", screens,
			                primary ? L", the main one" : L"", static_cast<unsigned long long>(desc.DedicatedVideoMemory / (1024 * 1024)));
			++adapters;
		}
		adapter->Release();
	}
	factory->Release();
	if (adapters < 2 || primaryOn < 0) return 11;
	return primaryOn == 0 ? 10 : 12;
}

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
		else if (a == L"--no-windowfx") options.windowfx = false;
		else if (a == L"--boot") options.boot = true;
		else if (a == L"--no-splash") options.splash = false;
		else if (a == L"--rescue" || a == L"--restore") rescue = true;
		else if (a == L"--restart-explorer") restartExplorer = true;
		else if (a == L"--guard") guardPid = static_cast<DWORD>(_wtoi(next().c_str()));
		else if (a == L"--gpu-policy") return gpuPolicy(true);
	}
	LocalFree(argv);

	if (guardPid) return runGuard(guardPid);
	if (rescue) return runRescue(restartExplorer);
	return runHost();
}
