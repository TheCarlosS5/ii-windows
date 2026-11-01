// What ii-host does when the shell crashes (plan 2026-10-31, A3/A4).
//
// The shell's crash handler (quickshell-windows src/win32/crash.cpp) leaves a JSON per crash in <data>\crashes with
// the code, where (module+offset) and the "subsystem" that was running on the crashing thread. ii-host reads it,
// logs it, and decides with a sliding 30-minute window:
//   1st crash         restart at once, and tell the user ii recovered
//   2nd               restart at once, and say what happens if it happens again
//   3rd in the same subsystem that can be switched off  restart with that part off (II_DISABLE)
//   4th (any)         restart in safe mode (II_SAFE_MODE=1: optional services off, basic render loop)
//   5th               give Windows' desktop back and stop (with a dialog)
// The pure part (Policy, parse, subsystemOf) has no Win32 calls of its own and is tested by crashpolicy_test.cpp.
#pragma once

#include <string>
#include <vector>

namespace ii::crashpolicy {

constexpr unsigned long long WINDOW_MS = 30ULL * 60 * 1000;

struct Report {
	bool found = false;
	std::wstring code;      // "0xC0000005"
	std::wstring where;     // "quickshell.exe+0x19ed74"
	std::wstring subsystem; // "mpris", "notifications", "gui", "render"...
	std::wstring kind;      // "exception", "abort", "terminate"...
	std::wstring dump;      // file name in the crashes folder, or empty
	std::wstring file;      // full path of the JSON
	unsigned long long uptimeSeconds = 0;
};

// Parses one crash JSON (UTF-8). Unknown fields are ignored; a missing subsystem becomes "gui".
Report parse(const std::string& json);

// The newest JSON in <dir> written for this pid (the shell that just exited). found=false if none.
Report find(const std::wstring& dir, unsigned long pid);

// A crash in a graphics module (Qt Quick, Direct3D, a GPU driver) counts as "render", whatever thread it was on;
// an exit with code 70 (the shell's own scene-graph-error exit) too.
std::wstring subsystemOf(const Report& report, unsigned long exitCode);

// Parts the shell can run without (crash.hpp disabled()). "render" is "switched off" by the basic render loop.
bool canDisable(const std::wstring& subsystem);

// Spanish name for messages: "la música y los videos", "las notificaciones"...
std::wstring describe(const std::wstring& subsystem);

enum class Action { Restart, Disable, SafeMode, GiveUp };

struct Decision {
	Action action = Action::Restart;
	int crashes = 0;          // in the window, this one included
	std::wstring subsystem;   // for Disable
};

class Policy {
public:
	// One more crash at nowMs. alreadyDisabled: the subsystems the next shell would already start without.
	Decision onCrash(unsigned long long nowMs, const std::wstring& subsystem, const std::vector<std::wstring>& alreadyDisabled,
	                 bool alreadySafe);
	void reset() { this->events.clear(); }
	[[nodiscard]] int recent(unsigned long long nowMs) const;

private:
	struct Event {
		unsigned long long at;
		std::wstring subsystem;
	};
	std::vector<Event> events;
};

} // namespace ii::crashpolicy
