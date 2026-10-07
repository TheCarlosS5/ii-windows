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

// %LOCALAPPDATA%\ii-windows (created on demand)
std::wstring dataDir();

// Appends a timestamped line to %LOCALAPPDATA%\ii-windows\host.log
void log(const wchar_t* fmt, ...);

// Restore bookkeeping, stored in %LOCALAPPDATA%\ii-windows\state.ini so the guard
// process and the rescue tools know what to undo even if the host crashed.
namespace state {
int get(const wchar_t* key, int fallback);
void set(const wchar_t* key, int value);
} // namespace state

std::vector<HWND> findTopLevel(const wchar_t* className);
DWORD processIdOf(HWND hwnd);

namespace taskbar {
void hide();          // records the original autohide state, then hides every taskbar
void reapply();       // hides taskbars again (cheap, safe to call often)
void restore();       // shows taskbars and restores the recorded autohide state
bool isTaskbarWindow(HWND hwnd);
} // namespace taskbar

namespace desktop {
void hideIcons();
void reapplyIcons();  // hides the icons again if Explorer recreated them (cheap)
void restoreIcons();
// Win+D: minimize the app windows, and on the next press restore exactly those.
void toggleShowDesktop();
} // namespace desktop

namespace banners {
void hide();    // records, then turns off Windows' own notification banners per app (cheap to repeat)
void restore(); // puts every recorded ShowBanner value back
} // namespace banners

// Undo everything the host may have changed. Safe to call any number of times.
void restoreAll(bool restartExplorer);

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
