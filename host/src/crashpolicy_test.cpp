// Plan 2026-10-31, A4: the crash policy of ii-host, without a shell. Prints PASS/FAIL lines; exit 1 on any failure.
#include <cstdio>
#include <string>
#include <vector>

#include "crashpolicy.h"

using namespace ii::crashpolicy;

static int failures = 0;
static void check(bool ok, const char* what) {
	std::printf("%s: %s\n", ok ? "PASS" : "FAIL", what);
	if (!ok) ++failures;
}

int main() {
	// parse
	auto r = parse(R"({"schema":1,"app":"quickshell","code":"0xC0000005","where":"quickshell.exe+0x19ed74","subsystem":"mpris","uptimeSeconds":2311,"pid":42,"dump":"a.dmp"})");
	check(r.found && r.code == L"0xC0000005" && r.where == L"quickshell.exe+0x19ed74" && r.subsystem == L"mpris", "a crash JSON is read");
	check(r.uptimeSeconds == 2311 && r.dump == L"a.dmp", "uptime and dump name");
	check(!parse("{broken").found, "broken JSON is not a report");
	check(parse(R"({"code":"0x1"})").subsystem == L"gui", "no subsystem means the GUI thread");

	// subsystemOf
	check(subsystemOf(r, 0xC0000005) == L"mpris", "the thread's subsystem when the module is ours");
	Report gpu = r;
	gpu.where = L"atio6axx.dll+0x1234";
	check(subsystemOf(gpu, 0xC0000005) == L"render", "a GPU driver module counts as render");
	gpu.where = L"Qt6Quick.dll+0x99";
	check(subsystemOf(gpu, 0xC0000005) == L"render", "Qt Quick counts as render");
	check(subsystemOf(Report {}, 70) == L"render", "exit 70 (scene graph error) is render");
	check(subsystemOf(Report {}, 0xC0000005) == L"unknown", "no report: unknown");
	check(canDisable(L"mpris") && canDisable(L"render") && !canDisable(L"gui") && !canDisable(L"tray"), "what can be switched off");

	// the policy, minute by minute
	const unsigned long long minute = 60000;
	Policy p;
	std::vector<std::wstring> none;
	check(p.onCrash(0, L"mpris", none, false).action == Action::Restart, "1st crash: restart");
	check(p.onCrash(10 * minute, L"mpris", none, false).action == Action::Restart, "2nd crash: restart");
	auto third = p.onCrash(18 * minute, L"mpris", none, false);
	check(third.action == Action::Disable && third.subsystem == L"mpris" && third.crashes == 3, "3rd in mpris: mpris off");
	std::vector<std::wstring> mprisOff = {L"mpris"};
	check(p.onCrash(20 * minute, L"gui", mprisOff, false).action == Action::SafeMode, "4th (any): safe mode");
	check(p.onCrash(21 * minute, L"gui", mprisOff, true).action == Action::GiveUp, "5th: give up");

	Policy slow;
	check(slow.onCrash(0, L"mpris", none, false).action == Action::Restart, "spread out: 1st");
	check(slow.onCrash(31 * minute, L"mpris", none, false).action == Action::Restart, "spread out: older crash left the window");
	check(slow.onCrash(62 * minute, L"mpris", none, false).action == Action::Restart, "spread out: still one at a time");
	check(slow.recent(62 * minute) == 1, "only the last one is recent");

	Policy mixed;
	mixed.onCrash(0, L"gui", none, false);
	mixed.onCrash(minute, L"tray", none, false);
	check(mixed.onCrash(2 * minute, L"gui", none, false).action == Action::Restart, "3 different-ish crashes: restart");
	check(mixed.onCrash(3 * minute, L"gui", none, false).action == Action::SafeMode, "4th: safe mode");

	Policy gui;
	gui.onCrash(0, L"gui", none, false);
	gui.onCrash(minute, L"gui", none, false);
	check(gui.onCrash(2 * minute, L"gui", none, false).action == Action::SafeMode, "3 in a part that cannot be switched off: safe mode");

	Policy safe;
	safe.onCrash(0, L"x", none, true);
	safe.onCrash(1, L"y", none, true);
	safe.onCrash(2, L"z", none, true);
	check(safe.onCrash(3, L"w", none, true).action == Action::GiveUp, "crashing on in safe mode: give up at the 4th");

	std::printf(failures ? "FAILED: %d\n" : "PASS: crash policy (%d failures)\n", failures);
	return failures ? 1 : 0;
}
