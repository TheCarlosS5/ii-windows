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
} // namespace theme

namespace splash {
void show();               // cover windows (plain colour) over Explorer's desktop while the shell loads
void loadImages();         // then ii's wallpaper on them (decoded after the shell is launched)
void setShellPid(DWORD pid);
void watch();              // fades out once the shell's wallpaper is up (polled by its own timer)
void close();
} // namespace splash

namespace banners {
void hide();    // records, then turns off Windows' own notification banners per app (cheap to repeat)
void restore(); // puts every recorded ShowBanner value back
} // namespace banners

// Undo everything the host may have changed. Safe to call any number of times.
void restoreAll(bool restartExplorer, bool force = false);

namespace keyboard {
// Window that receives shortcut notifications posted from the hook (handled outside the hook).
constexpr UINT WM_II_SHORTCUT = WM_APP + 1; // wParam: 1 pressed / 0 released, lParam: index
bool install(HWND notifyWindow);
void uninstall();
const wchar_t* shortcutName(LPARAM index);
} // namespace keyboard

// The shell (quickshell + ii) side receives shortcuts through WM_COPYDATA on this window.
constexpr const wchar_t* SHELL_SINK_CLASS = L"IiShellShortcutSink";
constexpr ULONG_PTR COPYDATA_PRESSED = 0x49490001;
constexpr ULONG_PTR COPYDATA_RELEASED = 0x49490002;
HWND findShellSink();

} // namespace ii
