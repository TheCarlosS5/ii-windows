// Deterministic spectrum source: no audio device is opened.
#include <windows.h>
#include <cstdio>
#include <string>

int main() {
    wchar_t data[32768] {};
    if (!GetEnvironmentVariableW(L"II_DATA_DIR", data, 32768)) return 1;
    auto marker = std::wstring(data) + L"\\cava-" + std::to_wstring(GetCurrentProcessId()) + L".started";
    auto file = CreateFileW(marker.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, 0, nullptr);
    if (file == INVALID_HANDLE_VALUE) return 2;
    CloseHandle(file);
    for (;;) {
        if (std::printf("10;20;30;40;\n") < 0 || std::fflush(stdout)) return 0;
        Sleep(16);
    }
}
