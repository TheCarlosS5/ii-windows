// Plan 2026-10-31, E3: the class timetable (overlay/ii/modules/common/functions/timetable_logic.js) under Node.
"use strict";
const fs = require("fs");
const path = require("path");
const file = path.join(__dirname, "..", "..", "overlay", "ii", "modules", "common", "functions", "timetable_logic.js");
const m_ = { exports: {} };
new Function("module", fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*/, ""))(m_);
const T = m_.exports;
let checks = 0, failures = 0;
function check(ok, what) { checks++; if (!ok) { failures++; console.log("FAIL: " + what); } }
const at = (day, h, m) => new Date(2026, 10, 1 + day, h, m); // 2026-11-01 is a Sunday

const classes = [
    { id: "a", subject: "Programación", day: 1, from: "18:00", to: "20:00", room: "Meet", link: "https://meet.google.com/abc-defg-hij" },
    { id: "b", subject: "Inglés", day: 1, from: "20:15", to: "21:30", room: "", link: "" },
    { id: "c", subject: "Bases de datos", day: 3, from: "18:00", to: "21:00", link: "javascript:alert(1)" },
    { id: "d", subject: "", day: 1, from: "08:00", to: "09:00" },
    { id: "e", subject: "Mal", day: 1, from: "10:00", to: "09:00" },
];
check(T.valid(classes[0]) && !T.valid(classes[3]) && !T.valid(classes[4]), "a class needs a subject and from < to");
check(T.classesOn(classes, 1).map(c => c.id).join() === "a,b", "Monday's classes, in order, the invalid ones left out");
check(T.joinLink(classes[0]) === "https://meet.google.com/abc-defg-hij", "an https link");
check(T.joinLink(classes[2]) === "" && T.joinLink(classes[1]) === "", "no button for other links or none");
let d = T.today(classes, at(1, 17, 40));
check(d.current === null && d.next.id === "a" && d.minutesToNext === 20, "17:40: next Programación in 20 min");
d = T.today(classes, at(1, 19, 0));
check(d.current.id === "a" && d.next.id === "b" && d.minutesToNext === 75, "19:00: in Programación, then Inglés");
d = T.today(classes, at(1, 22, 0));
check(d.current === null && d.next === null, "22:00: nothing more today");
check(T.today(classes, at(0, 18, 30)).list.length === 0, "Sunday: no classes");
check(T.due(classes, at(1, 17, 50), 10, []).map(c => c.id).join() === "a", "10 min before: remind");
check(T.due(classes, at(1, 17, 49), 10, []).length === 0, "11 min before: not yet");
check(T.due(classes, at(1, 18, 0), 10, []).map(c => c.id).join() === "a", "at the start: still");
check(T.due(classes, at(1, 18, 1), 10, []).length === 0, "after the start: no");
const key = "a@" + T.dateKey(at(1, 0, 0));
check(T.due(classes, at(1, 17, 55), 10, [key]).length === 0, "reminded once a day");
check(T.keepReminded([key, "a@2026-10-31"], at(1, 12, 0)).join() === key, "old reminders are forgotten");
console.log(`${checks} checks, ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
