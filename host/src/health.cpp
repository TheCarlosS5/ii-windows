#include "common.h"

#include <objbase.h>

#include <cwchar>
#include <string>

// Host <-> shell health channel (TASKS_ii_windows 9.6). The shell tells the host what a service of
// its own is really doing; the host acts on that (today: whether Windows' notification banners may
// be switched off). Three rules:
//   - authority comes from the channel, not from the payload: the sender window must belong to the
//     shell process this host started, and the payload must echo the instance id the host handed
//     that shell through its environment. Another quickshell, or a replayed message, matches neither.
//   - freshness is the host's own clock at the moment of receipt; a heartbeat that stops is the
//     same as a failure.
//   - an unknown protocol version, bad size/type, or a state other than "available" never
//     switches anything off.
//
// Message (UTF-16 JSON in a WM_COPYDATA with dwData COPYDATA_SERVICE_STATE, at most 64 KiB):
//   {"protocolVersion":1,"instanceId":"<echoed>","sessionId":1,"requestId":"n",
//    "messageType":"service-state","service":"notifications","state":"available",
//    "permission":"granted","subscribed":true,"observedAtMonotonicMs":12345,"error":null}

namespace ii::health {

namespace {

constexpr DWORD MAX_BYTES = 64 * 1024;

struct Notifications {
	ULONGLONG receivedAt = 0; // host clock, GetTickCount64
	std::wstring state;
	std::wstring permission;
	bool subscribed = false;
	bool seen = false;
};

Notifications notificationsState;
DWORD expectedShellPid = 0;
std::wstring instanceId;
bool warnedVersion = false;

// Minimal scanners for the flat JSON above (ii-host has no JSON parser): the value after "key":.
bool findValue(const std::wstring& json, const wchar_t* key, size_t& at) {
	auto needle = std::wstring(L"\"") + key + L"\"";
	auto pos = json.find(needle);
	if (pos == std::wstring::npos) return false;
	pos = json.find(L':', pos + needle.size());
	if (pos == std::wstring::npos) return false;
	++pos;
	while (pos < json.size() && json[pos] == L' ') ++pos;
	at = pos;
	return pos < json.size();
}

bool stringValue(const std::wstring& json, const wchar_t* key, std::wstring& out) {
	size_t at = 0;
	if (!findValue(json, key, at) || json[at] != L'"') return false;
	out.clear();
	for (auto i = at + 1; i < json.size(); ++i) {
		if (json[i] == L'\\' && i + 1 < json.size()) {
			out += json[++i];
		} else if (json[i] == L'"') {
			return true;
		} else {
			out += json[i];
		}
	}
	return false;
}

bool intValue(const std::wstring& json, const wchar_t* key, long long& out) {
	size_t at = 0;
	if (!findValue(json, key, at)) return false;
	wchar_t* end = nullptr;
	out = wcstoll(json.c_str() + at, &end, 10);
	return end != json.c_str() + at;
}

bool boolValue(const std::wstring& json, const wchar_t* key, bool& out) {
	size_t at = 0;
	if (!findValue(json, key, at)) return false;
	if (json.compare(at, 4, L"true") == 0) {
		out = true;
		return true;
	}
	if (json.compare(at, 5, L"false") == 0) {
		out = false;
		return true;
	}
	return false;
}

bool oneOf(const std::wstring& value, std::initializer_list<const wchar_t*> allowed) {
	for (auto* a: allowed) {
		if (value == a) return true;
	}
	return false;
}

} // namespace

void prepareLaunch(HWND hostWindow) {
	GUID guid {};
	CoCreateGuid(&guid);
	wchar_t text[64];
	StringFromGUID2(guid, text, _countof(text));
	instanceId = text;
	// The shell inherits these. It sends its health to II_HOST_HWND and echoes II_INSTANCE_ID.
	SetEnvironmentVariableW(L"II_INSTANCE_ID", instanceId.c_str());
	SetEnvironmentVariableW(L"II_PROTOCOL_VERSION", std::to_wstring(PROTOCOL_VERSION).c_str());
	SetEnvironmentVariableW(L"II_HOST_HWND", std::to_wstring(reinterpret_cast<ULONG_PTR>(hostWindow)).c_str());
}

void shellStarted(DWORD shellPid) {
	expectedShellPid = shellPid;
	reset();
}

void reset() {
	notificationsState = {};
	warnedVersion = false;
}

bool receive(HWND sender, const void* data, DWORD bytes) {
	if (bytes < sizeof(wchar_t) || bytes > MAX_BYTES || bytes % sizeof(wchar_t) != 0) {
		log(L"health: message of %lu bytes rejected", bytes);
		return true;
	}
	DWORD senderPid = 0;
	if (sender) GetWindowThreadProcessId(sender, &senderPid);
	if (expectedShellPid == 0 || senderPid != expectedShellPid) {
		log(L"health: message from process %lu ignored (the shell is %lu)", senderPid, expectedShellPid);
		return true;
	}
	std::wstring json(static_cast<const wchar_t*>(data), bytes / sizeof(wchar_t));
	while (!json.empty() && json.back() == L'\0') json.pop_back();

	long long version = 0;
	if (!intValue(json, L"protocolVersion", version) || version != PROTOCOL_VERSION) {
		if (!warnedVersion) {
			warnedVersion = true;
			log(L"health: protocol version %lld is not understood (this host speaks %d): banners stay as Windows has them", version, PROTOCOL_VERSION);
		}
		notificationsState = {};
		return true;
	}
	std::wstring echoed;
	std::wstring type;
	std::wstring service;
	if (!stringValue(json, L"instanceId", echoed) || echoed != instanceId || !stringValue(json, L"messageType", type)
	    || type != L"service-state" || !stringValue(json, L"service", service))
	{
		log(L"health: message with a wrong instance id or type ignored");
		return true;
	}
	long long session = -1;
	DWORD ours = 0;
	if (!intValue(json, L"sessionId", session) || !ProcessIdToSessionId(GetCurrentProcessId(), &ours) || session != static_cast<long long>(ours)) {
		log(L"health: message for session %lld ignored", session);
		return true;
	}
	if (service != L"notifications") return true; // other services have no consumer yet

	Notifications next;
	bool subscribed = false;
	if (!stringValue(json, L"state", next.state) || !oneOf(next.state, {L"unsupported", L"permission-required", L"available", L"busy", L"degraded", L"error"})
	    || !stringValue(json, L"permission", next.permission) || !oneOf(next.permission, {L"granted", L"denied", L"unknown"})
	    || !boolValue(json, L"subscribed", subscribed))
	{
		log(L"health: malformed notifications state ignored");
		return true;
	}
	next.subscribed = subscribed;
	next.receivedAt = GetTickCount64();
	next.seen = true;
	if (!notificationsState.seen || notificationsState.state != next.state || notificationsState.permission != next.permission
	    || notificationsState.subscribed != next.subscribed)
	{
		log(L"health: notifications %s, permission %s, subscribed %d", next.state.c_str(), next.permission.c_str(), next.subscribed ? 1 : 0);
	}
	notificationsState = next;
	return true;
}

Status notifications(ULONGLONG nowMs) {
	if (!notificationsState.seen) return {false, L"no health message from this shell yet"};
	if (nowMs - notificationsState.receivedAt > EXPIRY_MS) return {false, L"the shell stopped reporting"};
	if (notificationsState.permission != L"granted") return {false, L"Windows has not granted access to notifications"};
	if (notificationsState.state != L"available") return {false, L"the listener is " + notificationsState.state};
	if (!notificationsState.subscribed) return {false, L"the listener is not subscribed"};
	return {true, L"listener available"};
}

} // namespace ii::health
