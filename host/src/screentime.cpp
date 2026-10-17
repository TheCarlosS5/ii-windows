// Screen time: how long each program was in front today, for the "Usage" tab of ii's right sidebar.
//
// Counted once a second (the host's health tick) for the program whose window is in front, only while someone is
// there: input in the last 2 minutes, or something covering the whole screen (a film, a game). Never while the
// session is locked, never for the desktop, the taskbar or ii itself. Store apps count as themselves, not as
// ApplicationFrameHost. Written once a minute to %LOCALAPPDATA%\ii-windows\screentime\YYYY-MM-DD.json:
//   {"date":"2026-10-17","total":5234,"apps":{"brave.exe":3100,"code.exe":1500},     (seconds)
//    "names":{"brave.exe":"Brave Browser"},"paths":{"brave.exe":"C:/.../brave.exe"}}  (file description, for the UI)
// Files older than 30 days are removed. Nothing leaves the PC.
#include "common.h"
#include "jsonlite.h"

#include <wtsapi32.h>

#include <algorithm>
#include <cstdio>
#include <map>
#include <string>
#include <vector>

#pragma comment(lib, "version.lib")

namespace ii::screentime {

namespace {

constexpr DWORD IDLE_LIMIT_MS = 120000;
constexpr int KEEP_DAYS = 30;

bool locked = false;
std::wstring day;                  // YYYY-MM-DD of the counts below
std::map<std::wstring, int> seconds; // exe (lower case) -> seconds today
int sinceWrite = 0;
std::map<DWORD, std::wstring> exeOfPid;
std::map<DWORD, std::wstring> pathOfPid;
struct Program {
	std::wstring name; // the file's description ("Bloc de notas"), else empty
	std::wstring path;
};
std::map<std::wstring, Program> programs; // exe -> what the UI shows

std::wstring describe(const std::wstring& path) {
	DWORD handle = 0;
	auto size = GetFileVersionInfoSizeW(path.c_str(), &handle);
	if (!size) return {};
	std::vector<BYTE> data(size);
	if (!GetFileVersionInfoW(path.c_str(), 0, size, data.data())) return {};
	struct Translation { WORD language, codePage; }* translations = nullptr;
	UINT bytes = 0;
	if (!VerQueryValueW(data.data(), L"\\VarFileInfo\\Translation", reinterpret_cast<void**>(&translations), &bytes)
	    || bytes < sizeof(Translation))
		return {};
	wchar_t key[64];
	swprintf_s(key, L"\\StringFileInfo\\%04x%04x\\FileDescription", translations[0].language, translations[0].codePage);
	wchar_t* text = nullptr;
	UINT chars = 0;
	if (!VerQueryValueW(data.data(), key, reinterpret_cast<void**>(&text), &chars) || chars < 2) return {};
	std::wstring out(text);
	while (!out.empty() && iswspace(out.back())) out.pop_back();
	return out;
}

std::wstring folder() { return dataDir() + L"\\screentime"; }

std::wstring today() {
	SYSTEMTIME t;
	GetLocalTime(&t);
	wchar_t text[16];
	swprintf_s(text, L"%04u-%02u-%02u", t.wYear, t.wMonth, t.wDay);
	return text;
}

std::wstring exeName(DWORD pid) {
	auto it = exeOfPid.find(pid);
	if (it != exeOfPid.end()) return it->second;
	std::wstring name;
	if (auto* process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid)) {
		wchar_t path[MAX_PATH * 2];
		DWORD size = static_cast<DWORD>(_countof(path));
		if (QueryFullProcessImageNameW(process, 0, path, &size)) {
			name.assign(path, size);
			pathOfPid[pid] = name;
			name = name.substr(name.find_last_of(L"\\/") + 1);
			for (auto& c: name) c = static_cast<wchar_t>(towlower(c));
		}
		CloseHandle(process);
	}
	if (exeOfPid.size() > 512) {
		exeOfPid.clear();
		pathOfPid.clear();
	}
	exeOfPid[pid] = name;
	if (!name.empty() && !programs.count(name)) {
		auto& program = programs[name];
		program.path = pathOfPid[pid];
		program.name = describe(program.path);
	}
	return name;
}

// A Store app's frame belongs to ApplicationFrameHost; its content window to the app itself.
BOOL CALLBACK findContent(HWND child, LPARAM data) {
	auto* pid = reinterpret_cast<DWORD*>(data);
	DWORD childPid = 0;
	GetWindowThreadProcessId(child, &childPid);
	if (childPid && childPid != pid[0]) {
		pid[1] = childPid;
		return FALSE;
	}
	return TRUE;
}

std::string utf8(const std::wstring& text) {
	int size = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
	std::string out(static_cast<size_t>(size), '\0');
	WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size, nullptr, nullptr);
	return out;
}

std::string jsonString(const std::wstring& text) {
	std::string out = "\"";
	for (unsigned char c: utf8(text)) {
		if (c == '"' || c == '\\') {
			out += '\\';
			out += static_cast<char>(c);
		} else if (c >= 32) {
			out += static_cast<char>(c);
		}
	}
	return out + '"';
}

// Today's file read back at start, so a restart of ii does not reset the day.
std::wstring wide(const std::string& text) {
	int size = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
	std::wstring out(static_cast<size_t>(size), L'\0');
	MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size);
	return out;
}

void load() {
	seconds.clear();
	auto path = folder() + L"\\" + day + L".json";
	FILE* file = nullptr;
	if (_wfopen_s(&file, path.c_str(), L"rb") || !file) return;
	std::string text;
	char buffer[4096];
	size_t n;
	while ((n = fread(buffer, 1, sizeof(buffer), file)) > 0) text.append(buffer, n);
	fclose(file);
	auto parsed = jsonlite::parse(text);
	if (!parsed.ok || !parsed.value.isObject()) return;
	if (const auto* apps = parsed.value.find("apps"); apps && apps->isObject()) {
		for (const auto& [exe, value]: apps->members) {
			if (value.type == jsonlite::Type::Number && value.asDouble() > 0) seconds[wide(exe)] = static_cast<int>(value.asDouble());
		}
	}
	for (const auto* key: {"names", "paths"}) {
		const auto* object = parsed.value.find(key);
		if (!object || !object->isObject()) continue;
		for (const auto& [exe, value]: object->members) {
			if (value.type != jsonlite::Type::String) continue;
			auto& program = programs[wide(exe)];
			(key[0] == 'n' ? program.name : program.path) = wide(value.text);
		}
	}
}

void removeOld() {
	SYSTEMTIME now;
	GetLocalTime(&now);
	FILETIME nowFt;
	SystemTimeToFileTime(&now, &nowFt);
	ULARGE_INTEGER limit {};
	limit.LowPart = nowFt.dwLowDateTime;
	limit.HighPart = nowFt.dwHighDateTime;
	limit.QuadPart -= static_cast<ULONGLONG>(KEEP_DAYS) * 24 * 3600 * 10000000ULL;
	WIN32_FIND_DATAW found;
	auto pattern = folder() + L"\\????-??-??.json";
	HANDLE find = FindFirstFileW(pattern.c_str(), &found);
	if (find == INVALID_HANDLE_VALUE) return;
	do {
		ULARGE_INTEGER written {};
		written.LowPart = found.ftLastWriteTime.dwLowDateTime;
		written.HighPart = found.ftLastWriteTime.dwHighDateTime;
		if (written.QuadPart < limit.QuadPart) DeleteFileW((folder() + L"\\" + found.cFileName).c_str());
	} while (FindNextFileW(find, &found));
	FindClose(find);
}

} // namespace

void write() {
	if (day.empty()) return;
	CreateDirectoryW(folder().c_str(), nullptr);
	int total = 0;
	std::string apps, names, paths;
	for (auto& [exe, s]: seconds) {
		total += s;
		apps += (apps.empty() ? "" : ",") + jsonString(exe) + ":" + std::to_string(s);
		auto program = programs.find(exe);
		if (program == programs.end()) continue;
		std::wstring path = program->second.path;
		for (auto& c: path) if (c == L'\\') c = L'/';
		if (!program->second.name.empty()) names += (names.empty() ? "" : ",") + jsonString(exe) + ":" + jsonString(program->second.name);
		if (!path.empty()) paths += (paths.empty() ? "" : ",") + jsonString(exe) + ":" + jsonString(path);
	}
	auto text = "{\"date\":\"" + utf8(day) + "\",\"total\":" + std::to_string(total) + ",\"apps\":{" + apps + "},\"names\":{"
	          + names + "},\"paths\":{" + paths + "}}\n";
	auto path = folder() + L"\\" + day + L".json";
	auto temp = path + L".tmp";
	FILE* file = nullptr;
	if (_wfopen_s(&file, temp.c_str(), L"wb") || !file) return;
	fwrite(text.data(), 1, text.size(), file);
	fclose(file);
	MoveFileExW(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING);
}

void sessionChanged(WPARAM event) {
	if (event == WTS_SESSION_LOCK) locked = true;
	else if (event == WTS_SESSION_UNLOCK || event == WTS_SESSION_LOGON) locked = false;
}

void tick(DWORD shellPid) {
	auto now = today();
	if (now != day) {
		if (!day.empty()) write(); // the day that ends keeps what it had
		day = now;
		load();
		removeOld();
	}
	if (++sinceWrite >= 60) {
		sinceWrite = 0;
		write();
	}
	if (locked) return;

	HWND fg = GetForegroundWindow();
	if (!fg) return;
	wchar_t cls[64] {};
	GetClassNameW(fg, cls, 64);
	if (!wcscmp(cls, L"Progman") || !wcscmp(cls, L"WorkerW") || !wcscmp(cls, L"Shell_TrayWnd")
	    || !wcscmp(cls, L"Shell_SecondaryTrayWnd"))
		return;

	DWORD pid = 0;
	GetWindowThreadProcessId(fg, &pid);
	if (!pid || pid == GetCurrentProcessId() || pid == shellPid) return;

	LASTINPUTINFO input {sizeof(input), 0};
	auto idle = GetLastInputInfo(&input) ? GetTickCount() - input.dwTime : 0;
	if (idle > IDLE_LIMIT_MS) {
		// Nobody touching anything: still counted while something covers the whole screen (a film, a game).
		RECT r {};
		MONITORINFO info {};
		info.cbSize = sizeof(info);
		if (!GetWindowRect(fg, &r) || !GetMonitorInfoW(MonitorFromWindow(fg, MONITOR_DEFAULTTONEAREST), &info)) return;
		if (r.left > info.rcMonitor.left || r.top > info.rcMonitor.top || r.right < info.rcMonitor.right
		    || r.bottom < info.rcMonitor.bottom)
			return;
	}

	auto exe = exeName(pid);
	if (exe == L"applicationframehost.exe") {
		DWORD pids[2] = {pid, 0};
		EnumChildWindows(fg, findContent, reinterpret_cast<LPARAM>(pids));
		if (pids[1]) exe = exeName(pids[1]);
	}
	if (exe.empty() || exe == L"lockapp.exe" || exe == L"quickshell.exe") return;
	seconds[exe]++;
}

} // namespace ii::screentime
