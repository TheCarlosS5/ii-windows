// Windows' own state that is worth a word from ii (plan 2026-10-31, F2 and F14): an update waiting for a restart, and
// a system drive running out of space. Looked at on a worker thread (Windows Update's COM object talks to its service
// and can take seconds; the host's main thread never waits for it), a minute after start and then every hour. The
// result goes to <data>\system-status.json (the shell's session menu reads it) and to the host window, which decides
// whether to say something.

#include "common.h"

#include <atomic>
#include <mutex>

#include <objbase.h>
#include <wuapi.h>

namespace ii::syshealth {
namespace {

std::mutex lock;
Status latest;
HWND listener = nullptr;
UINT listenerMessage = 0;
HANDLE wake = nullptr;

bool askRebootRequired(bool& required) {
	ISystemInformation* info = nullptr;
	auto hr = CoCreateInstance(CLSID_SystemInformation, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&info));
	if (FAILED(hr) || !info) return false;
	VARIANT_BOOL value = VARIANT_FALSE;
	auto ok = SUCCEEDED(info->get_RebootRequired(&value));
	info->Release();
	if (ok) required = value != VARIANT_FALSE;
	return ok;
}

// Whole or not at all: the shell may read it at any moment.
void writeFileAtomic(const std::wstring& path, const std::string& text) {
	auto temp = path + L".tmp";
	auto* file = CreateFileW(temp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
	if (file == INVALID_HANDLE_VALUE) return;
	DWORD written = 0;
	auto ok = WriteFile(file, text.data(), static_cast<DWORD>(text.size()), &written, nullptr) && written == text.size();
	CloseHandle(file);
	if (ok) MoveFileExW(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING);
	else DeleteFileW(temp.c_str());
}

void writeStatus(const Status& s) {
	std::string drive(s.drive.begin(), s.drive.end()); // "C:", ASCII
	auto text = std::string("{\n  \"rebootRequired\": ") + (s.rebootRequired ? "true" : "false")
	    + ",\n  \"rebootKnown\": " + (s.rebootKnown ? "true" : "false")
	    + ",\n  \"drive\": \"" + drive + "\""
	    + ",\n  \"freeBytes\": " + std::to_string(s.freeBytes)
	    + ",\n  \"totalBytes\": " + std::to_string(s.totalBytes)
	    + ",\n  \"lowDisk\": " + (lowDisk(s) ? "true" : "false") + "\n}\n";
	writeFileAtomic(dataDir() + L"\\system-status.json", text);
}

DWORD WINAPI worker(LPVOID) {
	CoInitializeEx(nullptr, COINIT_MULTITHREADED);
	// The first look a minute after start: never in the way of the start itself (tests: II_TEST_SYSHEALTH_FIRST_MS).
	wchar_t testFirst[16] {};
	auto first = GetEnvironmentVariableW(L"II_TEST_SYSHEALTH_FIRST_MS", testFirst, 16) > 0 ? static_cast<DWORD>(_wtoi(testFirst)) : 60 * 1000;
	WaitForSingleObject(wake, first);
	for (;;) {
		Status s;
		auto started = GetTickCount64();
		s.rebootKnown = askRebootRequired(s.rebootRequired);
		auto took = GetTickCount64() - started;
		if (took >= 2000) log(L"slow: Windows Update's reboot state took %llu ms (on its own thread)", took);

		wchar_t windows[MAX_PATH] {};
		GetWindowsDirectoryW(windows, MAX_PATH);
		s.drive = std::wstring(windows).substr(0, 2); // "C:"
		ULARGE_INTEGER free {}, total {};
		if (GetDiskFreeSpaceExW((s.drive + L"\\").c_str(), &free, &total, nullptr)) {
			s.freeBytes = free.QuadPart;
			s.totalBytes = total.QuadPart;
		}
		wchar_t testFree[16] {}; // tests: a nearly full drive (II_TEST_SYSHEALTH_FREE_GB)
		if (GetEnvironmentVariableW(L"II_TEST_SYSHEALTH_FREE_GB", testFree, 16) > 0) s.freeBytes = _wtoi64(testFree) * 1024ULL * 1024 * 1024;
		{
			std::lock_guard guard(lock);
			latest = s;
		}
		writeStatus(s);
		if (listener) PostMessageW(listener, listenerMessage, 0, 0);
		WaitForSingleObject(wake, 60 * 60 * 1000);
	}
}

} // namespace

bool lowDisk(const Status& s) {
	if (s.totalBytes == 0) return false;
	constexpr ULONGLONG GB = 1024ULL * 1024 * 1024;
	// Under 2 GB always; under 10 GB when that is also under a tenth of the drive (a small drive fills sooner).
	return s.freeBytes < 2 * GB || (s.freeBytes < 10 * GB && s.freeBytes * 10 < s.totalBytes);
}

void start(HWND window, UINT message) {
	static const bool started = [&] {
		listener = window;
		listenerMessage = message;
		wake = CreateEventW(nullptr, FALSE, FALSE, nullptr);
		if (auto* thread = CreateThread(nullptr, 0, worker, nullptr, 0, nullptr)) CloseHandle(thread);
		return true;
	}();
	(void) started;
}

void checkNow() {
	if (wake) SetEvent(wake);
}

Status last() {
	std::lock_guard guard(lock);
	return latest;
}

} // namespace ii::syshealth
