.pragma library
// ii-windows (plan 2026-10-31, E11): digital wellbeing on top of screen time (ii-host writes, once a minute,
// %LOCALAPPDATA%\ii-windows\screentime\YYYY-MM-DD.json: {"total":s,"apps":{"brave.exe":s},"names":{...}}).
// Plain functions; tests/wellbeing/test.js runs them under Node.

// The goals passed today and not announced yet: [{ exe, name, minutes, used }]. goals: [{ exe, minutes }];
// announced: ["brave.exe@2026-11-01", ...].
function goalsPassed(day, goals, announced, dateKey) {
    if (!day || !day.apps) return [];
    const out = [];
    for (const g of goals || []) {
        const exe = String(g.exe || "").toLowerCase();
        const minutes = Number(g.minutes);
        if (!exe || !(minutes > 0)) continue;
        const key = Object.keys(day.apps).find(k => k.toLowerCase() === exe);
        if (!key) continue;
        const used = Math.floor(day.apps[key] / 60);
        if (used >= minutes && (announced || []).indexOf(exe + "@" + dateKey) < 0)
            out.push({ exe: exe, name: (day.names && day.names[key]) || key.replace(/\.exe$/i, ""), minutes: minutes, used: used });
    }
    return out;
}

// 20-20-20: a break is due after every `every` seconds of screen time (the day's total grows only while someone uses
// the PC). lastBreakAt: the total when the last one was shown (-1 none today).
function eyeBreakDue(total, lastBreakAt, every) {
    if (!(total > 0) || !(every > 0)) return false;
    const base = lastBreakAt >= 0 && lastBreakAt <= total ? lastBreakAt : 0;
    return total - base >= every;
}

// The week in one line: days [{ total, apps, names }] → { total, average, top: [{ name, seconds }] }.
function weekSummary(days) {
    const per = {};
    const names = {};
    let total = 0, counted = 0;
    for (const d of days || []) {
        if (!d || !d.apps) continue;
        counted += 1;
        total += d.total || 0;
        for (const k of Object.keys(d.apps)) {
            per[k] = (per[k] || 0) + d.apps[k];
            if (d.names && d.names[k]) names[k] = d.names[k];
        }
    }
    const top = Object.keys(per).sort((a, b) => per[b] - per[a]).slice(0, 3)
        .map(k => ({ name: names[k] || k.replace(/\.exe$/i, ""), seconds: per[k] }));
    return { total: total, average: counted ? Math.round(total / counted) : 0, top: top, days: counted };
}

function hoursText(seconds) { // 7260 → "2 h 1 min", 1800 → "30 min"
    const m = Math.round(seconds / 60);
    const h = Math.floor(m / 60);
    return h > 0 ? (m % 60 ? `${h} h ${m % 60} min` : `${h} h`) : `${m} min`;
}

function dateKey(d) { // 2026-11-01 (the screen time files' names)
    const p = n => (n < 10 ? "0" : "") + n;
    return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate());
}

if (typeof module !== "undefined") module.exports = { goalsPassed, eyeBreakDue, weekSummary, hoursText, dateKey };
