#include "common.h"

#include <cstdarg>
#include <cstdio>

#include <shlobj.h>
#include <tlhelp32.h>

namespace ii {

namespace {
std::wstring dataDirOverride() {
	wchar_t buffer[MAX_PATH];
	auto n = GetEnvironmentVariableW(L"II_DATA_DIR", buffer, MAX_PATH);
	if (n == 0 || n >= MAX_PATH) return {};
	return buffer;
}
} // namespace

std::wstring instanceTag() {
	auto dir = dataDirOverride();
	if (dir.empty()) return {};
	// FNV-1a of the folder: stable, short, valid inside a mutex name and a window class.
	unsigned long long h = 1469598103934665603ULL;
	for (auto c: dir) h = (h ^ static_cast<unsigned long long>(towlower(c))) * 1099511628211ULL;
	wchar_t tag[24];
	swprintf_s(tag, L"-t%08llx", h & 0xffffffffULL);
	return tag;
}

std::wstring dataDir() {
	if (auto forced = dataDirOverride(); !forced.empty()) {
		// Test instance: any folder, created with its parents.
		SHCreateDirectoryExW(nullptr, forced.c_str(), nullptr);
		return forced;
	}
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

std::wstring getText(const wchar_t* section, const wchar_t* key) {
	wchar_t buffer[2048] {};
	GetPrivateProfileStringW(section, key, L"", buffer, _countof(buffer), path().c_str());
	return buffer;
}

void setText(const wchar_t* section, const wchar_t* key, const std::wstring& value) {
	WritePrivateProfileStringW(section, key, value.empty() ? nullptr : value.c_str(), path().c_str());
}

} // namespace state

bool identityOf(DWORD pid, ProcessIdentity& out) {
	auto* process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
	if (!process) return false;
	bool ok = false;
	FILETIME created {};
	FILETIME exitTime {};
	FILETIME kernel {};
	FILETIME user {};
	wchar_t path[32768];
	DWORD size = _countof(path);
	DWORD exitCode = 0;
	if (GetExitCodeProcess(process, &exitCode) && exitCode == STILL_ACTIVE && GetProcessTimes(process, &created, &exitTime, &kernel, &user)
	    && QueryFullProcessImageNameW(process, 0, path, &size))
	{
		out.pid = pid;
		out.created = (static_cast<ULONGLONG>(created.dwHighDateTime) << 32) | created.dwLowDateTime;
		out.path.assign(path, size);
		ok = true;
	}
	CloseHandle(process);
	return ok;
}

bool sameProcess(const ProcessIdentity& recorded) {
	if (recorded.pid == 0 || recorded.created == 0 || recorded.path.empty()) return false;
	ProcessIdentity now;
	if (!identityOf(recorded.pid, now)) return false;
	if (now.created != recorded.created || _wcsicmp(now.path.c_str(), recorded.path.c_str()) != 0) return false;
	DWORD theirs = 0;
	DWORD ours = 0;
	return ProcessIdToSessionId(recorded.pid, &theirs) && ProcessIdToSessionId(GetCurrentProcessId(), &ours) && theirs == ours;
}

namespace {
struct CloseRequest {
	DWORD pid;
	int posted;
};

BOOL CALLBACK postCloseToProcessWindows(HWND hwnd, LPARAM data) {
	auto* request = reinterpret_cast<CloseRequest*>(data); // NOLINT
	DWORD pid = 0;
	GetWindowThreadProcessId(hwnd, &pid);
	if (pid == request->pid) {
		PostMessageW(hwnd, WM_CLOSE, 0, 0);
		++request->posted;
	}
	return TRUE;
}
} // namespace

bool terminateIfSame(const ProcessIdentity& target, DWORD gracefulMs) {
	if (!sameProcess(target)) return false;
	auto* process = OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, target.pid);
	if (!process) return false;
	// Re-check against the handle we now hold: a PID recycled between the check and the open
	// would show a different creation time here.
	FILETIME created {};
	FILETIME ignored {};
	if (!GetProcessTimes(process, &created, &ignored, &ignored, &ignored)
	    || ((static_cast<ULONGLONG>(created.dwHighDateTime) << 32) | created.dwLowDateTime) != target.created)
	{
		CloseHandle(process);
		return false;
	}
	if (gracefulMs > 0) {
		CloseRequest request {target.pid, 0};
		EnumWindows(postCloseToProcessWindows, reinterpret_cast<LPARAM>(&request)); // NOLINT
		if (request.posted > 0 && WaitForSingleObject(process, gracefulMs) == WAIT_OBJECT_0) {
			CloseHandle(process);
			return true;
		}
	}
	TerminateProcess(process, 1);
	auto gone = WaitForSingleObject(process, 3000) == WAIT_OBJECT_0;
	CloseHandle(process);
	return gone;
}

namespace instance {

namespace {
constexpr const wchar_t* SECTION = L"instance";

void record(const wchar_t* prefix, const ProcessIdentity& id) {
	auto key = [&](const wchar_t* part) { return std::wstring(prefix) + part; };
	state::setText(SECTION, key(L"Pid").c_str(), std::to_wstring(id.pid));
	state::setText(SECTION, key(L"Created").c_str(), std::to_wstring(id.created));
	state::setText(SECTION, key(L"Path").c_str(), id.path);
}

bool read(const wchar_t* prefix, ProcessIdentity& out) {
	auto key = [&](const wchar_t* part) { return std::wstring(prefix) + part; };
	auto pid = state::getText(SECTION, key(L"Pid").c_str());
	auto created = state::getText(SECTION, key(L"Created").c_str());
	auto path = state::getText(SECTION, key(L"Path").c_str());
	if (pid.empty() || created.empty() || path.empty()) return false;
	out.pid = static_cast<DWORD>(_wcstoui64(pid.c_str(), nullptr, 10));
	out.created = _wcstoui64(created.c_str(), nullptr, 10);
	out.path = path;
	return out.pid != 0 && out.created != 0;
}
} // namespace

void recordHost() {
	ProcessIdentity self;
	if (identityOf(GetCurrentProcessId(), self)) record(L"host", self);
}

void recordShell(DWORD pid, const std::wstring& config) {
	ProcessIdentity id;
	if (!identityOf(pid, id)) return;
	record(L"shell", id);
	state::setText(SECTION, L"shellConfig", config);
}

void clearShell() {
	for (auto* part: {L"shellPid", L"shellCreated", L"shellPath", L"shellConfig"}) state::setText(SECTION, part, L"");
}

bool readHost(ProcessIdentity& out) { return read(L"host", out); }

bool readShell(ProcessIdentity& out, std::wstring* config) {
	if (!read(L"shell", out)) return false;
	if (config) *config = state::getText(SECTION, L"shellConfig");
	return true;
}

int stopByExactPath(const std::wstring& exePath, DWORD gracefulMs) {
	if (exePath.empty()) return 0;
	int stopped = 0;
	auto snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
	if (snap == INVALID_HANDLE_VALUE) return 0;
	PROCESSENTRY32W entry {};
	entry.dwSize = sizeof(entry);
	for (auto ok = Process32FirstW(snap, &entry); ok; ok = Process32NextW(snap, &entry)) {
		if (entry.th32ProcessID == GetCurrentProcessId()) continue;
		ProcessIdentity candidate;
		if (!identityOf(entry.th32ProcessID, candidate) || _wcsicmp(candidate.path.c_str(), exePath.c_str()) != 0) continue;
		if (!sameProcess(candidate)) continue; // another session
		log(L"stopping %lu: its executable is exactly %s", candidate.pid, exePath.c_str());
		if (terminateIfSame(candidate, gracefulMs)) ++stopped;
	}
	CloseHandle(snap);
	return stopped;
}

int stopShell(const std::wstring& fallbackPath) {
	int stopped = 0;
	ProcessIdentity shell;
	if (readShell(shell)) {
		if (sameProcess(shell)) {
			log(L"stopping the recorded shell (%lu)", shell.pid);
			if (terminateIfSame(shell, 1500)) ++stopped;
		} else {
			log(L"recorded shell %lu is not running any more (or the PID was reused): not touching it", shell.pid);
		}
		clearShell();
		return stopped;
	}
	// No record at all (the host died before writing it, or it is an older version): only a
	// process whose executable is exactly this installation's shell, in this session. Never
	// "any quickshell.exe".
	return stopByExactPath(fallbackPath, 1500);
}

} // namespace instance

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

bool isExplorerWindow(HWND hwnd) {
	bool explorer = false;
	if (auto* process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processIdOf(hwnd))) {
		wchar_t path[MAX_PATH];
		DWORD size = MAX_PATH;
		if (QueryFullProcessImageNameW(process, 0, path, &size)) {
			std::wstring name(path, size);
			name = name.substr(name.find_last_of(L'\\') + 1);
			explorer = _wcsicmp(name.c_str(), L"explorer.exe") == 0;
		}
		CloseHandle(process);
	}
	return explorer;
}

HWND explorerTray() {
	for (auto* tray: findTopLevel(L"Shell_TrayWnd")) {
		if (isExplorerWindow(tray)) return tray;
	}
	return nullptr;
}

HWND findShellSink() { return FindWindowW(SHELL_SINK_CLASS, nullptr); }

} // namespace ii
