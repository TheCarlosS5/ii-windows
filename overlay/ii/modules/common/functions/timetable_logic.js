.pragma library
// ii-windows (plan 2026-10-31, E3): the class timetable as plain functions (tests/timetable/test.js runs them under
// Node). A class: { id, subject, day (JavaScript's: Sunday 0), from "18:00", to "20:00", room, link }.

function minutesOf(text) {
    const m = /^(\d{1,2}):(\d{2})$/.exec(String(text ?? "").trim());
    if (!m) return -1;
    const h = parseInt(m[1]), min = parseInt(m[2]);
    return h < 24 && min < 60 ? h * 60 + min : -1;
}

function valid(c) {
    return !!c && String(c.subject ?? "").trim().length > 0 && c.day >= 0 && c.day <= 6
        && minutesOf(c.from) >= 0 && minutesOf(c.to) > minutesOf(c.from);
}

// Only links worth a button: http(s).
function joinLink(c) {
    const link = String((c && c.link) ?? "").trim();
    return /^https?:\/\/\S+$/i.test(link) ? link : "";
}

function classesOn(classes, day) {
    return (classes || []).filter(c => valid(c) && c.day === day).sort((a, b) => minutesOf(a.from) - minutesOf(b.from));
}

// { current: the class going on (or null), next: the next one today (or null), minutesToNext }
function today(classes, now) {
    const t = now.getHours() * 60 + now.getMinutes();
    const list = classesOn(classes, now.getDay());
    const current = list.find(c => minutesOf(c.from) <= t && t < minutesOf(c.to)) ?? null;
    const next = list.find(c => minutesOf(c.from) > t) ?? null;
    return { current: current, next: next, minutesToNext: next ? minutesOf(next.from) - t : -1, list: list };
}

function dateKey(now) {
    return now.getFullYear() + "-" + (now.getMonth() + 1) + "-" + now.getDate();
}

// The classes to remind of now: starting in 0..minutesBefore minutes and not reminded today (keys "id@date").
function due(classes, now, minutesBefore, reminded) {
    const t = now.getHours() * 60 + now.getMinutes();
    const key = dateKey(now);
    return classesOn(classes, now.getDay()).filter(c => {
        const left = minutesOf(c.from) - t;
        return left >= 0 && left <= minutesBefore && (reminded || []).indexOf(c.id + "@" + key) < 0;
    });
}

// Reminded keys still worth keeping (today's).
function keepReminded(reminded, now) {
    const key = "@" + dateKey(now);
    return (reminded || []).filter(k => k.endsWith(key));
}

if (typeof module !== "undefined") module.exports = { minutesOf, valid, joinLink, classesOn, today, dateKey, due, keepReminded };
