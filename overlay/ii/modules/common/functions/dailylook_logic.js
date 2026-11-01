// ii-windows (plan 2026-10-31, E13): the decisions of services/DailyLook.qml, pure so Node can test them
// (tests/dailylook/test.js).

function minutesOf(text) { // "18:30" → 1110, anything else → -1
    const m = /^([01]?\d|2[0-3]):([0-5]\d)$/.exec(String(text ?? "").trim());
    return m ? Number(m[1]) * 60 + Number(m[2]) : -1;
}

// wttr.in's sunrise/sunset ("06:05 AM", "05:48 PM") or "18:30" → minutes of the day; -1 if not a time.
function clockMinutes(text) {
    const t = String(text ?? "").trim();
    const m = /^(\d{1,2}):(\d{2})\s*([AaPp][Mm])$/.exec(t);
    if (!m) return minutesOf(t);
    let h = Number(m[1]);
    const min = Number(m[2]);
    if (h < 1 || h > 12 || min > 59) return -1;
    const pm = m[3].toLowerCase() === "pm";
    if (h === 12) h = 0;
    return (h + (pm ? 12 : 0)) * 60 + min;
}

// "light" from lightAt until darkAt, "dark" the rest of the day (either order of the hours works); "" when the hours
// are not valid or are the same. Accepts "07:00" and "06:05 AM".
function phaseAt(lightAt, darkAt, date) {
    const light = clockMinutes(lightAt), dark = clockMinutes(darkAt);
    if (light < 0 || dark < 0 || light === dark) return "";
    const t = date.getHours() * 60 + date.getMinutes();
    const inLight = light < dark ? (t >= light && t < dark) : (t >= light || t < dark);
    return inLight ? "light" : "dark";
}

// The two hours to use: the sun's (from the weather) when asked and known, else the chosen hours.
function hoursFor(autoDark, sunrise, sunset) {
    if (autoDark && autoDark.mode === "sun" && clockMinutes(sunrise) >= 0 && clockMinutes(sunset) >= 0
            && clockMinutes(sunrise) !== clockMinutes(sunset))
        return { light: sunrise, dark: sunset, sun: true };
    return { light: autoDark ? autoDark.lightAt : "", dark: autoDark ? autoDark.darkAt : "", sun: false };
}

function dayKey(date) {
    return `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`;
}

// Whether to fetch the image of the day now: on, not done today, nothing running, the last try over half an hour ago.
function shouldFetch(enabled, doneDay, today, running, triedAt, nowMs) {
    return enabled && doneDay !== today && !running && nowMs - triedAt > 30 * 60000;
}

var IMAGE = /\.(jpe?g|png|webp|bmp|gif)$/i;

// The folder's next image after `current` (by name, wrapping around); "" if the folder has none.
function nextInFolder(files, current) {
    const images = (files || []).filter(f => IMAGE.test(String(f))).slice().sort((a, b) => String(a).localeCompare(String(b)));
    if (images.length === 0) return "";
    const norm = s => String(s).replace(/\\/g, "/").toLowerCase();
    const i = images.findIndex(f => norm(f) === norm(current));
    return images[(i + 1) % images.length];
}

// Time to show the folder's next image: on, every `minutes` (at least 1) since the last change.
function shouldRotate(enabled, lastMs, nowMs, minutes) {
    return enabled && nowMs - lastMs >= Math.max(1, Number(minutes) || 30) * 60000;
}

if (typeof module !== "undefined") module.exports = { minutesOf, clockMinutes, phaseAt, hoursFor, dayKey, shouldFetch, nextInFolder, shouldRotate };
