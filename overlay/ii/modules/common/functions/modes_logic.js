.pragma library
// ii-windows (plan 2026-10-31, E2): the decisions of services/Modes.qml, as plain functions (tests/modes/test.js runs
// them under Node): which mode should be on, and what to put back when it ends.

function minutesOf(text) { // "18:30" → 1110, anything else → -1
    const m = /^(\d{1,2}):(\d{2})$/.exec(String(text ?? "").trim());
    if (!m) return -1;
    const h = parseInt(m[1]), min = parseInt(m[2]);
    return h < 24 && min < 60 ? h * 60 + min : -1;
}

// Inside its hours at `now` (a Date). Days are JavaScript's (Sunday 0). Across midnight (22:00–06:00) the night
// belongs to the day it started.
function inSchedule(mode, now) {
    const s = mode && mode.schedule;
    if (!s || !s.enable) return false;
    const from = minutesOf(s.from), to = minutesOf(s.to);
    if (from < 0 || to < 0 || from === to) return false;
    const days = Array.isArray(s.days) ? s.days : [0, 1, 2, 3, 4, 5, 6];
    const day = now.getDay(), t = now.getHours() * 60 + now.getMinutes();
    if (from < to) return days.indexOf(day) >= 0 && t >= from && t < to;
    return (days.indexOf(day) >= 0 && t >= from) || (days.indexOf((day + 6) % 7) >= 0 && t < to);
}

function exeName(path) {
    return String(path ?? "").replace(/\\/g, "/").split("/").pop().toLowerCase();
}

var BROWSERS = ["chrome.exe", "msedge.exe", "firefox.exe", "brave.exe", "opera.exe", "opera_gx.exe", "vivaldi.exe",
    "arc.exe", "zen.exe", "librewolf.exe", "floorp.exe", "thorium.exe"];

// The app that turns `mode` on ("osu!"), or "". windows: [{ executable, activated, fullscreen, maximized, minimized }].
function appReason(mode, windows) {
    const apps = (mode.apps || []).map(a => String(a).trim().toLowerCase()).filter(a => a.length > 0);
    for (const w of windows) {
        const exe = exeName(w.executable);
        if (!exe) continue;
        if (apps.indexOf(exe) >= 0) return exe.replace(/\.exe$/, "");
        if (mode.fullscreen && w.activated && w.fullscreen && !w.maximized && !w.minimized && BROWSERS.indexOf(exe) < 0)
            return exe.replace(/\.exe$/, "");
    }
    return "";
}

// F24: the mode follows Windows' presentation mode (PowerPoint's slide show, "presentationsettings /start"). Modes
// saved before it was a choice: on for Presentación.
function followsPresenting(mode) {
    return mode.presenting === undefined ? mode.id === "presentacion" : !!mode.presenting;
}

// Which mode should be on: "id|reason|detail" ("" none). By hand first; then an app (in list order); then Windows
// presenting; then the hours. dismissed: { id: true } for automatic modes turned off by hand.
function wanted(modes, manualId, dismissed, windows, now, presenting) {
    if (manualId && modes.some(m => m.id === manualId)) return manualId + "|manual|";
    for (const m of modes) {
        if (dismissed[m.id]) continue;
        const app = appReason(m, windows);
        if (app) return m.id + "|app|" + app;
    }
    for (const m of modes) {
        if (presenting && !dismissed[m.id] && followsPresenting(m)) return m.id + "|presenting|";
    }
    for (const m of modes) {
        if (dismissed[m.id]) continue;
        if (inSchedule(m, now)) return m.id + "|schedule|" + m.schedule.from + "–" + m.schedule.to;
    }
    return "";
}

// The dismissals that still hold (their mode's reason has not ended).
function stillDismissed(modes, dismissed, windows, now, presenting) {
    const out = {};
    for (const id of Object.keys(dismissed)) {
        const m = modes.find(x => x.id === id);
        if (m && (appReason(m, windows) || (presenting && followsPresenting(m)) || inSchedule(m, now))) out[id] = true;
    }
    return out;
}

// What a mode sets: { silent, dark, light, night, awake, volume } (only the keys it changes).
function plan(mode) {
    const a = (mode && mode.apply) || {};
    const set = {};
    if (a.dnd) set.silent = true;
    if (a.theme === "dark" || a.theme === "light") set.dark = a.theme === "dark";
    if (a.light) set.light = true;
    if (a.nightLight) set.night = true;
    if (a.keepAwake) set.awake = true;
    if (typeof a.volume === "number" && a.volume >= 0) set.volume = Math.max(0, Math.min(100, a.volume)) / 100;
    return set;
}

// What to put back when it ends: { key: value as before } for each thing the mode changed that is still as the mode
// left it (a theme changed by hand meanwhile stays).
function restorePlan(before, applied, current) {
    const out = {};
    if (!before || !applied) return out;
    for (const key of Object.keys(applied)) {
        if (before[key] === undefined || before[key] === applied[key]) continue;
        const same = key === "volume" ? Math.abs(current[key] - applied[key]) < 0.011 : current[key] === applied[key];
        if (same && !(key === "volume" && before[key] < 0)) out[key] = before[key];
    }
    return out;
}

// E12: what arrived while a mode kept No molestar on. notifs: [{ appName, time }] (time in ms); ii's own notices
// do not count. { count, apps: [{ name, count }] } with the apps that sent most first (then by name).
function missedSummary(notifs, since) {
    const byApp = {};
    let count = 0;
    for (const n of notifs || []) {
        if (!n || !(n.time >= since)) continue;
        const name = String(n.appName || "").trim() || "?";
        if (name.toLowerCase() === "ii") continue;
        byApp[name] = (byApp[name] || 0) + 1;
        count++;
    }
    const apps = Object.keys(byApp).map(name => ({ name: name, count: byApp[name] }))
        .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
    return { count: count, apps: apps };
}

if (typeof module !== "undefined") module.exports = { minutesOf, inSchedule, exeName, appReason, wanted, stillDismissed, plan, restorePlan, missedSummary, BROWSERS };
