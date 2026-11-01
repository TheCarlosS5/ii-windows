// SHQueryUserNotificationState off the host's main thread (plan 2026-10-31, A5).
//
// The call asks Explorer, and Explorer may itself be waiting on a hung window (the crashing shell's app bars, the
// night of 2026-10-25): keyboard::refreshContext then held ii-host's main thread 1.1 / 3.4 / 4.8 s, and with it the
// panic key, the heartbeat check and the welcome cover. Now a worker thread asks, the callers read the last answer,
// and a changed answer is announced to the host window so the keyboard rules are re-evaluated at once.

#include "common.h"

#include <atomic>

#include <objbase.h>
#include <shellapi.h>

namespace ii::notifystate {
namespace {

std::atomic<int> current {QUNS_ACCEPTS_NOTIFICATIONS};
std::atomic<bool> known {false};
std::atomic<ULONGLONG> askedAt {0};
HANDLE wake = nullptr;
HWND listener = nullptr;
UINT listenerMessage = 0;

DWORD WINAPI worker(LPVOID) {
	CoInitializeEx(nullptr, COINIT_MULTITHREADED);
	for (;;) {
		WaitForSingleObject(wake, INFINITE);
		auto started = GetTickCount64();
		QUERY_USER_NOTIFICATION_STATE state {};
		auto ok = SUCCEEDED(SHQueryUserNotificationState(&state));
		auto took = GetTickCount64() - started;
		if (took >= 500) log(L"slow: SHQueryUserNotificationState took %llu ms (on its own thread)", took);
		if (!ok) continue;
		auto previous = current.exchange(static_cast<int>(state));
		auto first = !known.exchange(true);
		if ((first || previous != static_cast<int>(state)) && listener) PostMessageW(listener, listenerMessage, 0, 0);
	}
}

void ensureStarted() {
	static const bool started = [] {
		wake = CreateEventW(nullptr, FALSE, FALSE, nullptr);
		if (auto* thread = CreateThread(nullptr, 0, worker, nullptr, 0, nullptr)) CloseHandle(thread);
		return true;
	}();
	(void) started;
}

} // namespace

void setListener(HWND window, UINT message) {
	listener = window;
	listenerMessage = message;
	ensureStarted();
	SetEvent(wake);
}

int get() {
	ensureStarted();
	auto now = GetTickCount64();
	// Asked again at most every 250 ms; the caller never waits for the answer.
	if (now - askedAt.load() >= 250) {
		askedAt = now;
		SetEvent(wake);
	}
	return current.load();
}

bool fullscreenOrPresenting() {
	auto state = get();
	return state == QUNS_RUNNING_D3D_FULL_SCREEN || state == QUNS_PRESENTATION_MODE;
}

} // namespace ii::notifystate
