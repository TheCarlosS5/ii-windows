// ii-windows (plan 2026-10-31, E13): the decisions of services/DailyLook.qml, pure so Node can test them
// (tests/dailylook/test.js).

function minutesOf(text) { // "18:30" → 1110, anything else → -1
    const m = /^([01]?\d|2[0-3]):([0-5]\d)$/.exec(String(text ?? "").trim());
    return m ? Number(m[1]) * 60 + Number(m[2]) : -1;
}

// "light" from lightAt until darkAt, "dark" the rest of the day (either order of the hours works); "" when the hours
// are not valid or are the same.
function phaseAt(lightAt, darkAt, date) {
    const light = minutesOf(lightAt), dark = minutesOf(darkAt);
    if (light < 0 || dark < 0 || light === dark) return "";
    const t = date.getHours() * 60 + date.getMinutes();
    const inLight = light < dark ? (t >= light && t < dark) : (t >= light || t < dark);
    return inLight ? "light" : "dark";
}

function dayKey(date) {
    return `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`;
}

// Whether to fetch the image of the day now: on, not done today, nothing running, the last try over half an hour ago.
function shouldFetch(enabled, doneDay, today, running, triedAt, nowMs) {
    return enabled && doneDay !== today && !running && nowMs - triedAt > 30 * 60000;
}

if (typeof module !== "undefined") module.exports = { minutesOf, phaseAt, dayKey, shouldFetch };
