#include "recovery.h"
#include "common.h"

namespace ii::recovery {
namespace {
HWND window = nullptr;
HWND listener = nullptr;
bool decided = false;
void choose(WPARAM choice) {
    close();
    PostMessageW(listener, WM_II_COVER, choice, 0);
}
LRESULT CALLBACK procedure(HWND hwnd, UINT message, WPARAM w, LPARAM l) {
    if (message == WM_COMMAND && HIWORD(w) == BN_CLICKED) {
        if (LOWORD(w) == 100) choose(3); // normal
        else if (LOWORD(w) == 101) choose(1); // safe
        else if (LOWORD(w) == 102 || LOWORD(w) == IDCANCEL) choose(2); // not today
        return 0;
    }
    if (message == WM_TIMER) { choose(3); return 0; }
    if (message == WM_CLOSE) { choose(2); return 0; }
    return DefWindowProcW(hwnd, message, w, l);
}
}

void showIfNeeded(HWND host) {
    if (decided || window || state::get(L"lastSessionTrouble", 0) != 1) return;
    listener = host;
    auto instance = GetModuleHandleW(nullptr);
    WNDCLASSW wc {};
    wc.lpfnWndProc = procedure; wc.hInstance = instance; wc.lpszClassName = L"IiRecoveryChoices";
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW); wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    RegisterClassW(&wc);
    auto spanish = PRIMARYLANGID(GetUserDefaultUILanguage()) == LANG_SPANISH;
    auto* monitor = MonitorFromWindow(host, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO info {}; info.cbSize = sizeof(info); GetMonitorInfoW(monitor, &info);
    const int width = 560, height = 165;
    window = CreateWindowExW(WS_EX_TOPMOST | WS_EX_CONTROLPARENT, wc.lpszClassName,
        spanish ? L"Recuperación de ii-windows" : L"ii-windows recovery",
        WS_CAPTION | WS_SYSMENU, info.rcWork.left + (info.rcWork.right - info.rcWork.left - width) / 2,
        info.rcWork.top + (info.rcWork.bottom - info.rcWork.top - height) / 2, width, height,
        nullptr, nullptr, instance, nullptr);
    if (!window) { log(L"recovery: could not create choices window (%lu)", GetLastError()); return; }
    auto font = GetStockObject(DEFAULT_GUI_FONT);
    auto label = CreateWindowW(L"STATIC", spanish ? L"La última vez ii tuvo problemas. ¿Cómo quieres iniciarlo?"
        : L"Last time ii had trouble. How would you like to start it?", WS_CHILD | WS_VISIBLE,
        16, 18, 520, 40, window, nullptr, instance, nullptr);
    SendMessageW(label, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    const wchar_t* labels[] = {spanish ? L"Iniciar normalmente" : L"Start normally", spanish ? L"Modo seguro" : L"Safe mode", spanish ? L"Hoy no" : L"Not today"};
    for (int i = 0; i < 3; ++i) {
        auto button = CreateWindowW(L"BUTTON", labels[i], WS_CHILD | WS_VISIBLE | WS_TABSTOP | (i == 0 ? BS_DEFPUSHBUTTON : BS_PUSHBUTTON),
            16 + i * 176, 76, 166, 30, window, reinterpret_cast<HMENU>(static_cast<INT_PTR>(i + 100)), instance, nullptr);
        SendMessageW(button, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    }
    // The original cover offered these choices for nine seconds. Compilation can run meanwhile.
    SetTimer(window, 1, 9000, nullptr);
    ShowWindow(window, SW_SHOW); SetForegroundWindow(window); SetFocus(GetDlgItem(window, 100));
    log(L"recovery: choices available independently of the loading cover");
}

bool pending() { return window != nullptr; }
bool dispatch(MSG& message) { return window && IsDialogMessageW(window, &message); }
void close() {
    if (!window) return;
    decided = true;
    KillTimer(window, 1); DestroyWindow(window); window = nullptr;
}
}
