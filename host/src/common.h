#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <string>
#include <vector>

namespace ii {

// %LOCALAPPDATA%\ii-windows (created on demand). For tests, II_DATA_DIR overrides it, so a test
// instance never reads or writes the data of the ii that is really running.
std::wstring dataDir();
// Empty for the real instance; for an II_DATA_DIR instance a short stable tag. It is appended to
// the host's mutex and window class so a test host can neither collide with the real one nor be
// closed by the installer/uninstaller that look for it.
std::wstring instanceTag();

// Test switch (II_NO_UI=1): no message boxes, and restoreAll leaves Explorer's taskbar and icons
// alone, so automated tests can run beside a real ii without touching its desktop.
bool noUi();
// A message to the user; logged instead when noUi().
void alertUser(const std::wstring& text);

// A timeline mark for startup measurements (B02): "bench: +<ms> <event> <detail>" in host.log,
// milliseconds on a monotonic clock since this process started. Cheap, a few lines per start;
// tools/dev/bench-startup.ps1 turns them into per-phase distributions.
void bench(const wchar_t* event, const wchar_t* detail = L"");

// Appends a timestamped line to %LOCALAPPDATA%\ii-windows\host.log
void log(const wchar_t* fmt, ...);

// Restore bookkeeping, stored in %LOCALAPPDATA%\ii-windows\state.ini so the guard
// process and the rescue tools know what to undo even if the host crashed.
namespace state {
int get(const wchar_t* key, int fallback);
void set(const wchar_t* key, int value);
// Free-form values (process identities, paths) in their own section of the same file.
std::wstring getText(const wchar_t* section, const wchar_t* key);
void setText(const wchar_t* section, const wchar_t* key, const std::wstring& value);
} // namespace state

// A process, identified well enough that a recycled PID cannot be mistaken for it: the creation
// time and the executable path must both match what was recorded, in the same session.
struct ProcessIdentity {
	DWORD pid = 0;
	ULONGLONG created = 0; // FILETIME of the process creation
	std::wstring path;     // full executable path
};
bool identityOf(DWORD pid, ProcessIdentity& out);
bool sameProcess(const ProcessIdentity& recorded); // still running, same creation time/path/session
// Asks the process's top-level windows to close, waits gracefulMs, then terminates it. Only if
// sameProcess() holds at the moment of the call. Returns true if the process is gone afterwards.
bool terminateIfSame(const ProcessIdentity& target, DWORD gracefulMs);

// What ii-host supervises, recorded in state.ini so the guard and the rescue tools stop exactly
// that shell/host and never another quickshell.exe or ii-host.exe.
namespace instance {
void recordHost();
void recordShell(DWORD pid, const std::wstring& config);
void clearShell();
bool readHost(ProcessIdentity& out);
bool readShell(ProcessIdentity& out, std::wstring* config = nullptr);
// Stops the recorded shell (and nothing else). With no record at all, falls back to processes
// whose executable is exactly fallbackPath. Returns how many were stopped.
int stopShell(const std::wstring& fallbackPath);
// Processes (other than this one, same session) whose executable is exactly exePath.
int stopByExactPath(const std::wstring& exePath, DWORD gracefulMs);
} // namespace instance

std::vector<HWND> findTopLevel(const wchar_t* className);
DWORD processIdOf(HWND hwnd);
bool isExplorerWindow(HWND hwnd);
// Explorer's taskbar. The shell owns a Shell_TrayWnd too (its tray), so never FindWindow it.
HWND explorerTray();

namespace taskbar {
void hide();          // records the original autohide state, then hides every taskbar
void reapply();       // hides taskbars again (cheap, safe to call often)
// Shows taskbars and restores the recorded autohide state. Without force, only if this ii hid
// them (state.ini says so): a run that hides nothing (--no-taskbar) leaves Explorer's taskbar
// alone, and another ii instance's hiding is not undone. The rescue passes force.
void restore(bool force = false);
bool isTaskbarWindow(HWND hwnd);
void conceal(HWND bar); // empty region + hidden (see taskbar.cpp)
} // namespace taskbar

namespace desktop {
void hideIcons();
void reapplyIcons();  // hides the icons again if Explorer recreated them (cheap)
void restoreIcons(bool force = false); // same rule as taskbar::restore
// Win+D: minimize the app windows, and on the next press restore exactly those.
void toggleShowDesktop();
} // namespace desktop

namespace theme {
void start();   // follow ii's palette (dark/light, accent) from now on; records originals first
void apply();   // re-apply if the palette changed (cheap to call often)
void restore(); // puts every recorded value back
void refresh(); // apply again on the next apply() even if the palette did not change (an option changed)
} // namespace theme

namespace windowfx {
// Light transparency for other programs' windows and no loud accent borders (see windowfx.cpp).
void start();          // read the options, watch new windows
void tick();           // once a second: options changed, windows the events missed
void stop();           // give back every window this run touched and stop watching
void restore();        // give back every marked window, from any process (the rescue calls it)
bool accentBorders();  // appearance.windowEffects.accentBorders (default false)
} // namespace windowfx

namespace splash {
void show();               // cover windows (plain colour) over Explorer's desktop while the shell loads
void loadImages();         // (no-op: show() prepares the picture on a worker thread)
void refreshCache();       // re-cache the small blurred wallpaper for the next logon (own thread)
void setShellPid(DWORD pid);
void watch();              // fades out once the shell says its desktop is complete (own timer)
void close();
} // namespace splash

// Host <-> shell health channel (see health.cpp). The shell reports what its services really do;
// the host acts on it, e.g. Windows' notification banners are only switched off while the shell's
// listener is confirmed to be receiving them.
namespace health {
constexpr ULONG_PTR COPYDATA_SERVICE_STATE = 0x49490020;
constexpr int PROTOCOL_VERSION = 1;
constexpr ULONGLONG EXPIRY_MS = 3000; // a heartbeat every 1 s; three missed ones mean failure
struct Status {
	bool operational = false;
	std::wstring reason;
};
void prepareLaunch(HWND hostWindow); // before CreateProcess: the shell inherits the instance id
void shellStarted(DWORD shellPid);   // after: only this process may report
void reset();                        // the shell is gone
bool receive(HWND sender, const void* data, DWORD bytes); // true: handled (accepted or rejected)
Status notifications(ULONGLONG nowMs);
} // namespace health

namespace banners {
void hide();    // records, then turns off Windows' own notification banners per app (cheap to repeat)
void restore(); // puts every recorded ShowBanner value back
} // namespace banners

// Undo everything the host may have changed. Safe to call any number of times.
void restoreAll(bool restartExplorer, bool force = false);

namespace keyboard {
// Window that receives shortcut notifications posted from the hook (handled outside the hook).
constexpr UINT WM_II_SHORTCUT = WM_APP + 1; // wParam: 1 pressed / 0 released, lParam: index
constexpr UINT WM_II_VOLUME = WM_APP + 3;   // wParam: VK_VOLUME_UP / _DOWN / _MUTE (WM_APP + 2 is the shell-exited message in main.cpp)
constexpr UINT WM_II_LONE_WIN = WM_APP + 4; // a lone Win press went to ii's search (WM_APP + 5 is the shell's heartbeat)
bool install(HWND notifyWindow);
void uninstall();
const wchar_t* shortcutName(LPARAM index);
// Outside the hook: refresh what the hook reads (is the shell there, is a game in front) and forget
// held-key state after a lock or session switch. Cheap enough for a window event; also run once a second.
void refreshContext();
void resetState();
// While ii's welcome cover is up the Windows key goes nowhere: Start (or StartAllBack's menu) would
// open above the cover of a desktop that is still loading. Ctrl+Esc too.
void setCoverUp(bool up);
// Opens Windows' own Start menu (an injected Win tap the hook lets through): ii took a lone Win press but could not
// show anything for it, and a key must never be swallowed with nothing on screen.
void openStart();
// The shell beats (or not): ii's Alt+Tab only while it can show it, else Windows' one opens.
void setShellResponsive(bool responsive);
} // namespace keyboard

namespace minanim {
// ii's own minimize animation: Windows' own one off in memory while ii runs (minanim.cpp); restore() applies the
// user's saved setting again (any process: exit, guard, rescue).
void tick();
void restore();
} // namespace minanim

namespace volume {
// A volume key ii took from Windows (keyboard hook): one step up/down, or mute toggle, on the default
// output. Runs on the host thread; ii's own indicator reacts to the change like to any other.
void handleKey(unsigned vk);
} // namespace volume

namespace screentime {
// Once a second: one more second for the program in front (screentime.cpp). Written to disk once a minute.
void tick(DWORD shellPid);
void sessionChanged(WPARAM event); // WM_WTSSESSION_CHANGE: nothing is counted while the session is locked
void write();                      // now (at exit)
} // namespace screentime

// The shell (quickshell + ii) side receives shortcuts through WM_COPYDATA on this window.
constexpr const wchar_t* SHELL_SINK_CLASS = L"IiShellShortcutSink";
constexpr ULONG_PTR COPYDATA_PRESSED = 0x49490001;
constexpr ULONG_PTR COPYDATA_RELEASED = 0x49490002;
HWND findShellSink();

} // namespace ii
