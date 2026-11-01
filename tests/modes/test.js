// Plan 2026-10-31, E2: the decisions of the modes (overlay/ii/modules/common/functions/modes_logic.js) under Node.
//   node tests/modes/test.js
"use strict";
const fs = require("fs");
const path = require("path");
const file = process.argv[2] || path.join(__dirname, "..", "..", "overlay", "ii", "modules", "common", "functions", "modes_logic.js");
const m_ = { exports: {} };
new Function("module", fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*/, ""))(m_);
const L = m_.exports;

let checks = 0, failures = 0;
function check(ok, what) { checks++; if (!ok) { failures++; console.log("FAIL: " + what); } }
function at(day, hh, mm) { // 2026-11-01 is a Sunday (day 0)
    return new Date(2026, 10, 1 + day, hh, mm);
}

const clase = { id: "clase", apply: { dnd: true, keepAwake: true, theme: "keep", volume: -1 },
    schedule: { enable: true, days: [1, 2, 3, 4, 5], from: "18:00", to: "22:00" }, apps: ["Teams.exe"] };
const juego = { id: "juego", apply: { dnd: true, light: true }, schedule: { enable: false }, apps: ["osu!.exe"], fullscreen: true };
const noche = { id: "noche", apply: { theme: "dark", nightLight: true }, schedule: { enable: true, days: [0, 1, 2, 3, 4, 5, 6], from: "22:00", to: "06:00" }, apps: [] };
const modes = [clase, juego, noche];

// ---- times
check(L.minutesOf("18:30") === 1110 && L.minutesOf("7:05") === 425, "minutesOf");
check(L.minutesOf("24:00") === -1 && L.minutesOf("ab") === -1 && L.minutesOf("") === -1, "bad times");
check(L.inSchedule(clase, at(1, 18, 0)), "Monday 18:00: in");
check(L.inSchedule(clase, at(1, 21, 59)), "Monday 21:59: in");
check(!L.inSchedule(clase, at(1, 22, 0)), "Monday 22:00: out (the end is not included)");
check(!L.inSchedule(clase, at(0, 19, 0)), "Sunday: not one of its days");
check(L.inSchedule(noche, at(0, 23, 0)), "night: 23:00 in");
check(L.inSchedule(noche, at(1, 5, 59)), "night: 05:59 the next day in");
check(!L.inSchedule(noche, at(1, 6, 0)), "night: 06:00 out");
const weekdayNight = { id: "n", schedule: { enable: true, days: [5], from: "22:00", to: "06:00" } }; // Friday night only
check(L.inSchedule(weekdayNight, at(6, 2, 0)), "Friday's night goes on into Saturday 02:00");
check(!L.inSchedule(weekdayNight, at(5, 2, 0)), "but Friday 02:00 belongs to Thursday's night");
check(!L.inSchedule({ schedule: { enable: false, from: "00:00", to: "23:59" } }, at(1, 12, 0)), "switched off");
check(!L.inSchedule({ schedule: { enable: true, from: "10:00", to: "10:00" } }, at(1, 10, 0)), "from = to: never");

// ---- apps
const osu = [{ executable: "C:\\Users\\x\\AppData\\Local\\osu!\\osu!.exe", activated: false }];
check(L.appReason(juego, osu) === "osu!", "an app of the list with a window open");
check(L.appReason(clase, osu) === "", "not an app of its list");
check(L.appReason(clase, [{ executable: "C:/Program Files/Teams/TEAMS.EXE" }]) === "teams", "names ignore case");
const fsGame = [{ executable: "D:\\Games\\game.exe", activated: true, fullscreen: true, maximized: false, minimized: false }];
check(L.appReason(juego, fsGame) === "game", "Juego: any app in full screen");
check(L.appReason(clase, fsGame) === "", "but only the modes that ask for it");
check(L.appReason(juego, [{ executable: "C:\\b\\chrome.exe", activated: true, fullscreen: true, maximized: false }]) === "", "a browser in full screen is not a game");
check(L.appReason(juego, [{ executable: "D:\\g\\game.exe", activated: true, fullscreen: true, maximized: true }]) === "", "a maximized window is not a game");
check(L.appReason(juego, [{ executable: "D:\\g\\game.exe", activated: false, fullscreen: true, maximized: false }]) === "", "a full-screen app behind is not in front");

// ---- which one
check(L.wanted(modes, "", {}, [], at(1, 12, 0)) === "", "Monday noon, nothing open: none");
check(L.wanted(modes, "", {}, [], at(1, 19, 0)) === "clase|schedule|18:00–22:00", "Monday 19:00: Clase by its hours");
check(L.wanted(modes, "", {}, osu, at(1, 19, 0)) === "juego|app|osu!", "an app wins over the hours");
check(L.wanted(modes, "noche", {}, osu, at(1, 19, 0)) === "noche|manual|", "by hand wins over everything");
check(L.wanted(modes, "", { juego: true }, osu, at(1, 19, 0)) === "clase|schedule|18:00–22:00", "Juego turned off by hand: the next reason");
check(L.wanted(modes, "borrado", {}, [], at(1, 12, 0)) === "", "a mode chosen by hand that no longer exists");
check(L.wanted(modes, "", {}, [], at(2, 23, 30)) === "noche|schedule|22:00–06:00", "Tuesday 23:30: Noche");

// ---- F24: Windows presenting
const presentacion = { id: "presentacion", apps: [], schedule: { enable: false } };
const withP = [clase, juego, presentacion, noche];
check(L.wanted(withP, "", {}, [], at(1, 12, 0), true) === "presentacion|presenting|", "Windows presenting: Presentación (saved before it was a choice)");
check(L.wanted(withP, "", {}, [], at(1, 12, 0), false) === "", "not presenting: none");
check(L.wanted(withP, "", {}, osu, at(1, 12, 0), true) === "juego|app|osu!", "an app wins over presenting");
check(L.wanted(withP, "", {}, [], at(1, 19, 0), true) === "presentacion|presenting|", "presenting wins over the hours");
check(L.wanted(withP, "", { presentacion: true }, [], at(1, 12, 0), true) === "", "turned off by hand while presenting");
check(L.wanted([clase, Object.assign({}, presentacion, { presenting: false })], "", {}, [], at(1, 12, 0), true) === "", "the choice off");
check(L.wanted([Object.assign({}, clase, { presenting: true })], "", {}, [], at(1, 12, 0), true) === "clase|presenting|", "another mode can follow it");
check(JSON.stringify(L.stillDismissed(withP, { presentacion: true }, [], at(1, 12, 0), true)) === '{"presentacion":true}', "still presenting: still off");
check(JSON.stringify(L.stillDismissed(withP, { presentacion: true }, [], at(1, 12, 0), false)) === "{}", "the presentation ended: forgotten");

// ---- turned off by hand, until its reason ends
check(JSON.stringify(L.stillDismissed(modes, { juego: true }, osu, at(1, 19, 0))) === '{"juego":true}', "osu! still open: still off");
check(JSON.stringify(L.stillDismissed(modes, { juego: true }, [], at(1, 19, 0))) === "{}", "osu! closed: forgotten");
check(JSON.stringify(L.stillDismissed(modes, { clase: true }, [], at(1, 22, 30))) === "{}", "the hours ended: forgotten");

// ---- what it sets, what goes back
check(JSON.stringify(L.plan(clase)) === '{"silent":true,"awake":true}', "Clase sets No molestar and keeps the screen on");
check(JSON.stringify(L.plan(noche)) === '{"dark":true,"night":true}', "Noche: dark theme and night light");
check(L.plan({ apply: { volume: 60 } }).volume === 0.6, "volume in percent");
check(L.plan({ apply: { volume: -1 } }).volume === undefined, "-1: the volume is not touched");
const before = { silent: false, dark: false, light: false, night: false, awake: false, volume: 0.3 };
const applied = { silent: true, dark: true, volume: 0.6 };
let back = L.restorePlan(before, applied, { silent: true, dark: true, volume: 0.6 });
check(back.silent === false && back.dark === false && back.volume === 0.3, "everything it changed goes back");
back = L.restorePlan(before, applied, { silent: true, dark: false, volume: 0.6 });
check(back.dark === undefined && back.silent === false, "a theme changed by hand meanwhile stays");
back = L.restorePlan(before, applied, { silent: true, dark: true, volume: 0.9 });
check(back.volume === undefined, "a volume moved meanwhile stays");
back = L.restorePlan({ silent: true }, { silent: true }, { silent: true });
check(Object.keys(back).length === 0, "what was already so before is not touched");
check(Object.keys(L.restorePlan(null, applied, {})).length === 0, "nothing saved: nothing to put back");

console.log(`${checks} checks, ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
