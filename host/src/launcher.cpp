// ii-launcher: the one stable entry point of an installation (shortcuts, the logon task and the Run
// key all start this). It reads current.txt, starts ii-host from the active version's folder and,
// while that version is still "pending" (never confirmed to work), stays to see the outcome: if the
// host exits without the version being verified, or does not verify within the timeout, the
// launcher records why and starts the previous version instead. A version that has proved itself
// ("verified") is started and the launcher exits at once.
//
//   ii-launcher.exe [ii-host arguments]      --shell/--config default to the active version's own
//
// Exit code: 0 started (or fell back and started the previous version), 1 nothing could be started.
// Diagnostics: launcher.log and last-failure.txt next to the exe.

#include <windows.h>

#include <shellapi.h>

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <string>

#include "rollout.h"

using namespace ii;

namespace {

constexpr DWORD VERIFY_TIMEOUT_DEFAULT_MS = 180000; // a cold first start compiles the QML; it can be slow
constexpr int MAX_ATTEMPTS = 3;             // launches of one pending version before it is dropped
constexpr DWORD EXIT_ALREADY_RUNNING = 17;  // ii-host: another host owns this desktop

std::wstring root;

// II_LAUNCHER_VERIFY_TIMEOUT_MS shortens the wait in tests; a real run uses the default.
DWORD verifyTimeoutMs() {
	wchar_t value[16];
	if (GetEnvironmentVariableW(L"II_LAUNCHER_VERIFY_TIMEOUT_MS", value, _countof(value)) > 0) {
		auto ms = _wtoi(value);
		if (ms >= 500) return static_cast<DWORD>(ms);
	}
	return VERIFY_TIMEOUT_DEFAULT_MS;
}

void log(const wchar_t* fmt, ...) {
	wchar_t message[1024];
	va_list args;
	va_start(args, fmt);
	_vsnwprintf_s(message, _countof(message), _TRUNCATE, fmt, args);
	va_end(args);
	SYSTEMTIME t;
	GetLocalTime(&t);
	wchar_t line[1200];
	auto n = swprintf_s(line, L"%04d-%02d-%02d %02d:%02d:%02d.%03d [%lu] %s\r\n", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond, t.wMilliseconds, GetCurrentProcessId(), message);
	auto path = root + L"\\launcher.log";
	WIN32_FILE_ATTRIBUTE_DATA info {};
	if (GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &info) && info.nFileSizeLow > 256 * 1024) DeleteFileW(path.c_str()); // bounded
	auto file = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
	if (file == INVALID_HANDLE_VALUE) return;
	char utf8[3600];
	auto bytes = WideCharToMultiByte(CP_UTF8, 0, line, n, utf8, sizeof(utf8), nullptr, nullptr);
	DWORD written = 0;
	WriteFile(file, utf8, static_cast<DWORD>(bytes), &written, nullptr);
	CloseHandle(file);
}

void recordFailure(const std::wstring& id, const std::wstring& reason, DWORD exitCode) {
	SYSTEMTIME t;
	GetLocalTime(&t);
	wchar_t text[1500];
	auto n = swprintf_s(text, L"version=%s\r\nwhen=%04d-%02d-%02dT%02d:%02d:%02d\r\nreason=%s\r\nexitCode=%lu\r\n", id.c_str(), t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond, reason.c_str(), exitCode);
	auto file = CreateFileW((root + L"\\last-failure.txt").c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
	if (file == INVALID_HANDLE_VALUE) return;
	char utf8[3200];
	auto bytes = WideCharToMultiByte(CP_UTF8, 0, text, n, utf8, sizeof(utf8), nullptr, nullptr);
	DWORD written = 0;
	WriteFile(file, utf8, static_cast<DWORD>(bytes), &written, nullptr);
	CloseHandle(file);
}

bool exists(const std::wstring& path) { return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES; }

// The command line after the program name, untouched.
std::wstring argumentTail() {
	std::wstring line = GetCommandLineW();
	size_t i = 0;
	if (!line.empty() && line[0] == L'"') {
		i = line.find(L'"', 1);
		i = i == std::wstring::npos ? line.size() : i + 1;
	} else {
		i = line.find_first_of(L" \t");
		if (i == std::wstring::npos) i = line.size();
	}
	while (i < line.size() && (line[i] == L' ' || line[i] == L'\t')) ++i;
	return line.substr(i);
}

bool spawnHost(const std::wstring& dir, const std::wstring& tail, PROCESS_INFORMATION& pi) {
	auto command = L"\"" + dir + L"\\ii-host.exe\"";
	if (!tail.empty()) command += L" " + tail;
	if (tail.find(L"--shell") == std::wstring::npos) {
		command += L" --shell \"" + dir + L"\\quickshell\\quickshell.exe\" --config \"" + dir + L"\\ii\"";
	}
	STARTUPINFOW si {};
	si.cb = sizeof(si);
	pi = {};
	if (!CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW | CREATE_BREAKAWAY_FROM_JOB, nullptr, dir.c_str(), &si, &pi)
	    && !CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, dir.c_str(), &si, &pi))
	{
		log(L"CreateProcess failed (%lu): %s", GetLastError(), command.c_str());
		return false;
	}
	log(L"started %s (pid %lu)", dir.c_str(), pi.dwProcessId);
	return true;
}

// The pending version failed: go back to the previous one, if there is one.
int fallBack(rollout::Current current, const std::wstring& tail, const std::wstring& reason, DWORD exitCode) {
	log(L"version %s failed: %s (exit %lu)", current.active.c_str(), reason.c_str(), exitCode);
	recordFailure(current.active, reason, exitCode);
	auto previousDir = rollout::versionDir(root, current.previous);
	if (current.previous == L"none" || previousDir.empty() || !exists(previousDir + L"\\ii-host.exe")) {
		log(L"no previous version to go back to");
		return 1;
	}
	rollout::Current back;
	back.present = true;
	back.active = current.previous;
	back.previous = current.active; // the failed one stays on disk for diagnosis
	back.state = L"rolled-back";
	back.attempts = 0;
	if (!rollout::write(root, back)) {
		log(L"could not write current.txt (%lu)", GetLastError());
		return 1;
	}
	PROCESS_INFORMATION pi {};
	if (!spawnHost(previousDir, tail, pi)) return 1;
	CloseHandle(pi.hThread);
	CloseHandle(pi.hProcess);
	log(L"fell back to %s", back.active.c_str());
	return 0;
}

} // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
	wchar_t self[MAX_PATH];
	GetModuleFileNameW(nullptr, self, MAX_PATH);
	root = self;
	root = root.substr(0, root.find_last_of(L"\\/"));
	auto tail = argumentTail();

	rollout::Current current;
	if (!rollout::read(root, current)) {
		// An installation from before versions: everything is in the install folder itself.
		PROCESS_INFORMATION pi {};
		if (!spawnHost(root, tail, pi)) return 1;
		CloseHandle(pi.hThread);
		CloseHandle(pi.hProcess);
		return 0;
	}

	if (current.state == L"pending") {
		++current.attempts;
		if (current.attempts > MAX_ATTEMPTS) return fallBack(current, tail, L"too many launches without being verified", 0);
		rollout::write(root, current);
	}
	auto dir = rollout::versionDir(root, current.active);
	if (dir.empty() || !exists(dir + L"\\ii-host.exe")) return fallBack(current, tail, L"the version folder or its ii-host.exe is missing", 0);

	PROCESS_INFORMATION pi {};
	if (!spawnHost(dir, tail, pi)) return fallBack(current, tail, L"ii-host could not be started", GetLastError());
	CloseHandle(pi.hThread);
	if (current.state != L"pending") {
		CloseHandle(pi.hProcess);
		return 0; // proved itself earlier: nothing to watch
	}

	// First start of this version: stay until it is verified, or it fails.
	auto started = GetTickCount64();
	for (;;) {
		auto waited = WaitForSingleObject(pi.hProcess, 300);
		rollout::Current now;
		auto known = rollout::read(root, now);
		if (known && now.active == current.active && now.state == L"verified") {
			log(L"version %s verified after %llu ms", current.active.c_str(), GetTickCount64() - started);
			CloseHandle(pi.hProcess);
			return 0;
		}
		if (known && now.active != current.active) { // someone else (an installer) moved on
			CloseHandle(pi.hProcess);
			return 0;
		}
		if (waited == WAIT_OBJECT_0) {
			DWORD code = 0;
			GetExitCodeProcess(pi.hProcess, &code);
			CloseHandle(pi.hProcess);
			if (code == EXIT_ALREADY_RUNNING) {
				log(L"another ii-host is already running; nothing to verify");
				return 0;
			}
			return fallBack(current, tail, L"ii-host ended before the version was verified", code);
		}
		if (GetTickCount64() - started > verifyTimeoutMs()) {
			// Still alive but never ready. Put Windows back, then go back a version.
			TerminateProcess(pi.hProcess, 1);
			WaitForSingleObject(pi.hProcess, 3000);
			CloseHandle(pi.hProcess);
			PROCESS_INFORMATION rescue {};
			auto command = L"\"" + dir + L"\\ii-host.exe\" --rescue";
			STARTUPINFOW si {};
			si.cb = sizeof(si);
			if (CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, dir.c_str(), &si, &rescue)) {
				WaitForSingleObject(rescue.hProcess, 30000);
				CloseHandle(rescue.hThread);
				CloseHandle(rescue.hProcess);
			}
			return fallBack(current, tail, L"ii-host did not verify the version in time", 0);
		}
	}
}
