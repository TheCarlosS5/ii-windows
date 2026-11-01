// Plan 2026-10-31, E11: wellbeing (overlay/ii/modules/common/functions/wellbeing_logic.js) under Node.
"use strict";
const fs = require("fs");
const path = require("path");
const file = path.join(__dirname, "..", "..", "overlay", "ii", "modules", "common", "functions", "wellbeing_logic.js");
const m_ = { exports: {} };
new Function("module", fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*/, ""))(m_);
const W = m_.exports;
let checks = 0, failures = 0;
function check(ok, what) { checks++; if (!ok) { failures++; console.log("FAIL: " + what); } }

const day = { total: 9000, apps: { "brave.exe": 7260, "Code.exe": 1740 }, names: { "brave.exe": "Brave Browser" } };
let p = W.goalsPassed(day, [{ exe: "brave.exe", minutes: 120 }, { exe: "code.exe", minutes: 60 }], [], "2026-11-01");
check(p.length === 1 && p[0].name === "Brave Browser" && p[0].used === 121, "Brave passed its 2 h, Code not its hour");
check(W.goalsPassed(day, [{ exe: "brave.exe", minutes: 120 }], ["brave.exe@2026-11-01"], "2026-11-01").length === 0, "once a day");
check(W.goalsPassed(day, [{ exe: "code.exe", minutes: 20 }], [], "d")[0].name === "Code", "names ignore case; no description → exe name");
check(W.goalsPassed(day, [{ exe: "brave.exe", minutes: 0 }, { exe: "", minutes: 5 }], [], "d").length === 0, "empty goals are ignored");
check(W.goalsPassed(null, [{ exe: "brave.exe", minutes: 1 }], [], "d").length === 0, "no file yet");

check(!W.eyeBreakDue(1100, -1, 1200) && W.eyeBreakDue(1200, -1, 1200), "first break after 20 min of use");
check(!W.eyeBreakDue(2300, 1200, 1200) && W.eyeBreakDue(2400, 1200, 1200), "then every 20 min of use");
check(W.eyeBreakDue(1300, 5000, 1200), "a new day (total below the last break): counted from 0");

const w = W.weekSummary([day, { total: 3600, apps: { "brave.exe": 3600 } }, null]);
check(w.total === 12600 && w.average === 6300 && w.days === 2, "week total and average over the days with data");
check(w.top[0].name === "Brave Browser" && w.top[0].seconds === 10860 && w.top.length === 2, "top apps");
check(W.hoursText(7260) === "2 h 1 min" && W.hoursText(1800) === "30 min" && W.hoursText(7200) === "2 h", "hours text");
check(W.dateKey(new Date(2026, 10, 1)) === "2026-11-01", "date key");
console.log(`${checks} checks, ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
