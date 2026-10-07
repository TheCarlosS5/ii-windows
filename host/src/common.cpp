#include "common.h"

#include <cstdarg>
#include <cstdio>

#include <shlobj.h>

namespace ii {

std::wstring dataDir() {
	wchar_t* base = nullptr;
	std::wstring dir;
	if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &base))) {
		dir = std::wstring(base) + L"\\ii-windows";
		CoTaskMemFree(base);
	} else {
		dir = L".";
	}
	CreateDirectoryW(dir.c_str(), nullptr);
	return dir;
}

void log(const wchar_t* fmt, ...) {
	static std::wstring path = dataDir() + L"\\host.log";

	wchar_t msg[1024];
	va_list args;
	va_start(args, fmt);
	_vsnwprintf_s(msg, _countof(msg), _TRUNCATE, fmt, args);
	va_end(args);

	SYSTEMTIME t;
	GetLocalTime(&t);
	wchar_t line[1200];
	auto n = swprintf_s(
	    line,
	    L"%04d-%02d-%02d %02d:%02d:%02d.%03d [%lu] %s\r\n",
	    t.wYear,
	    t.wMonth,
	    t.wDay,
	    t.wHour,
	    t.wMinute,
	    t.wSecond,
	    t.wMilliseconds,
	    GetCurrentProcessId(),
	    msg
	);

	auto file = CreateFileW(
	    path.c_str(),
	    FILE_APPEND_DATA,
	    FILE_SHARE_READ | FILE_SHARE_WRITE,
	    nullptr,
	    OPEN_ALWAYS,
	    FILE_ATTRIBUTE_NORMAL,
	    nullptr
	);
	if (file == INVALID_HANDLE_VALUE) return;

	char utf8[3600];
	auto bytes = WideCharToMultiByte(CP_UTF8, 0, line, n, utf8, sizeof(utf8), nullptr, nullptr);
	DWORD written = 0;
	WriteFile(file, utf8, static_cast<DWORD>(bytes), &written, nullptr);
	CloseHandle(file);
}

namespace state {

namespace {
const std::wstring& path() {
	static std::wstring p = dataDir() + L"\\state.ini";
	return p;
}
} // namespace

int get(const wchar_t* key, int fallback) {
	return static_cast<int>(GetPrivateProfileIntW(L"restore", key, fallback, path().c_str()));
}

void set(const wchar_t* key, int value) {
	WritePrivateProfileStringW(L"restore", key, std::to_wstring(value).c_str(), path().c_str());
}

} // namespace state

std::vector<HWND> findTopLevel(const wchar_t* className) {
	std::vector<HWND> result;
	HWND h = nullptr;
	while ((h = FindWindowExW(nullptr, h, className, nullptr)) != nullptr) result.push_back(h);
	return result;
}

DWORD processIdOf(HWND hwnd) {
	DWORD pid = 0;
	GetWindowThreadProcessId(hwnd, &pid);
	return pid;
}

HWND findShellSink() { return FindWindowW(SHELL_SINK_CLASS, nullptr); }

} // namespace ii
