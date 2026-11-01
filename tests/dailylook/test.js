// Plan 2026-10-31, E13: the decisions of services/DailyLook.qml (dailylook_logic.js). node tests/dailylook/test.js
const L = require("../../overlay/ii/modules/common/functions/dailylook_logic.js");
let failures = 0, checks = 0;
function eq(got, want, what) {
    checks++;
    if (got !== want) { failures++; console.log(`FAIL ${what}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); }
}
const at = (h, m) => new Date(2026, 10, 1, h, m);

// Day hours in order: light from 07:00, dark from 19:00.
eq(L.phaseAt("07:00", "19:00", at(0, 0)), "dark", "midnight");
eq(L.phaseAt("07:00", "19:00", at(6, 59)), "dark", "06:59");
eq(L.phaseAt("07:00", "19:00", at(7, 0)), "light", "07:00");
eq(L.phaseAt("07:00", "19:00", at(18, 59)), "light", "18:59");
eq(L.phaseAt("07:00", "19:00", at(19, 0)), "dark", "19:00");
// The other order (a night worker: light from 20:00, dark from 08:00).
eq(L.phaseAt("20:00", "08:00", at(23, 0)), "light", "reversed 23:00");
eq(L.phaseAt("20:00", "08:00", at(3, 0)), "light", "reversed 03:00");
eq(L.phaseAt("20:00", "08:00", at(12, 0)), "dark", "reversed noon");
// Hours that do not work.
eq(L.phaseAt("7", "19:00", at(12, 0)), "", "bad light hour");
eq(L.phaseAt("07:00", "25:00", at(12, 0)), "", "bad dark hour");
eq(L.phaseAt("07:00", "07:00", at(12, 0)), "", "same hours");
eq(L.phaseAt("7:30", "19:00", at(7, 30)), "light", "one-digit hour");

eq(L.dayKey(at(10, 0)), "2026-11-1", "day key");
const now = at(10, 0).getTime();
eq(L.shouldFetch(true, "2026-10-31", "2026-11-1", false, 0, now), true, "fetch: new day");
eq(L.shouldFetch(false, "2026-10-31", "2026-11-1", false, 0, now), false, "fetch: off");
eq(L.shouldFetch(true, "2026-11-1", "2026-11-1", false, 0, now), false, "fetch: done today");
eq(L.shouldFetch(true, "", "2026-11-1", true, 0, now), false, "fetch: already running");
eq(L.shouldFetch(true, "", "2026-11-1", false, now - 10 * 60000, now), false, "fetch: failed 10 min ago");
eq(L.shouldFetch(true, "", "2026-11-1", false, now - 31 * 60000, now), true, "fetch: failed 31 min ago");

console.log(`${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
