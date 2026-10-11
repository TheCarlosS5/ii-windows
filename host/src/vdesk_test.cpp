// Checks of the rules that decide whether an empty virtual desktop may be removed (R09).
// No Explorer involved: build with the host and run host\build\ii-vdesk-test.exe.
#include <cstdio>
#include <string>
#include <vector>

#include "vdesk_policy.h"

using namespace vdeskpolicy;

static int failed = 0;
static int total = 0;

static void check(bool ok, const char* what) {
	++total;
	if (!ok) {
		++failed;
		std::printf("FAIL %s\n", what);
	}
}

static void expect(Verdict got, Verdict want, const char* what) {
	++total;
	if (got != want) {
		++failed;
		std::printf("FAIL %s (got %ls, want %ls)\n", what, name(got), name(want));
	}
}

int main() {
	const std::vector<std::wstring> three = {
	    normalize(L"{11111111-1111-1111-1111-111111111111}"),
	    normalize(L"{22222222-2222-2222-2222-222222222222}"),
	    normalize(L"{33333333-3333-3333-3333-333333333333}"),
	};
	const auto last = three[2];

	// The plain case: the user left the last desktop, nothing is on it.
	expect(judgeRemoveEmpty(three, three, 1, last, 0), Verdict::Ok, "empty last desktop, user elsewhere");
	expect(judgeRemoveEmpty(three, three, 0, three[1], 0), Verdict::Ok, "empty middle desktop is allowed by the rule (the caller decides which)");

	// A window is there, or it could not be told: never delete.
	expect(judgeRemoveEmpty(three, three, 1, last, 1), Verdict::Occupied, "one window on it");
	expect(judgeRemoveEmpty(three, three, 1, last, 5), Verdict::Occupied, "several windows on it");
	expect(judgeRemoveEmpty(three, three, 1, last, -1), Verdict::Occupied, "occupancy unknown counts as occupied");

	// The user came back, or never left.
	expect(judgeRemoveEmpty(three, three, 2, last, 0), Verdict::IsCurrent, "the user is on it now");

	// Desktop 1 is never removed automatically; the last one cannot be removed at all.
	expect(judgeRemoveEmpty(three, three, 2, three[0], 0), Verdict::IsFirst, "desktop 1");
	const std::vector<std::wstring> one = {three[0]};
	expect(judgeRemoveEmpty(one, one, 0, three[0], 0), Verdict::OnlyOne, "only desktop");

	// The inventory changed between the decision and the call: another desktop was made or closed,
	// or they were reordered. The stale decision is dropped.
	std::vector<std::wstring> four = three;
	four.push_back(normalize(L"{44444444-4444-4444-4444-444444444444}"));
	expect(judgeRemoveEmpty(three, four, 1, last, 0), Verdict::InventoryChanged, "a desktop was added");
	std::vector<std::wstring> two = {three[0], three[1]};
	expect(judgeRemoveEmpty(three, two, 0, last, 0), Verdict::InventoryChanged, "a desktop was closed");
	std::vector<std::wstring> reordered = {three[0], three[2], three[1]};
	expect(judgeRemoveEmpty(three, reordered, 0, last, 0), Verdict::InventoryChanged, "same desktops, other order");
	std::vector<std::wstring> swapped = {three[0], three[1], normalize(L"{99999999-9999-9999-9999-999999999999}")};
	expect(judgeRemoveEmpty(three, swapped, 1, last, 0), Verdict::InventoryChanged, "the target id is gone and another is in its place");
	expect(judgeRemoveEmpty(three, three, 1, normalize(L"{99999999-9999-9999-9999-999999999999}"), 0), Verdict::NotInInventory, "target never was in the list");

	// Spelling of ids.
	check(normalize(L"{AbCdEf01-0000-0000-0000-000000000000}") == normalize(L"abcdef01-0000-0000-0000-000000000000"), "case and braces do not matter");
	auto list = splitIds(L"{11111111-1111-1111-1111-111111111111},22222222-2222-2222-2222-222222222222,{33333333-3333-3333-3333-333333333333}");
	check(list == three, "a comma list parses to the normalized ids, in order");
	check(splitIds(L"").empty(), "empty list");
	check(splitIds(L",,").empty(), "only separators");
	expect(judgeRemoveEmpty(splitIds(L"{11111111-1111-1111-1111-111111111111},{22222222-2222-2222-2222-222222222222},{33333333-3333-3333-3333-333333333333}"), three, 0, L"33333333-3333-3333-3333-333333333333", 0),
	       Verdict::Ok, "a caller's list in another spelling still matches");

	// An empty expected list (the caller did not say what it saw) never matches a real inventory.
	expect(judgeRemoveEmpty({}, three, 0, last, 0), Verdict::InventoryChanged, "no expectation, no removal");

	std::printf("%d checks, %d failed\n", total, failed);
	return failed == 0 ? 0 : 1;
}
