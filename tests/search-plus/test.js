// Plan 2026-10-31, E1: the logic of "Buscar todo" (overlay/ii/modules/common/functions/search_plus.js) under Node.
//   node tests/search-plus/test.js [path to search_plus.js]
// Exit 0 when every check passes; prints one line per failure.
"use strict";
const fs = require("fs");
const path = require("path");
const file = process.argv[2] || path.join(__dirname, "..", "..", "overlay", "ii", "modules", "common", "functions", "search_plus.js");
const source = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*/, "");
const module_ = { exports: {} };
new Function("module", source)(module_);
const S = module_.exports;

let checks = 0, failures = 0;
function check(ok, what) {
    checks++;
    if (!ok) { failures++; console.log("FAIL: " + what); }
}
function near(a, b, tolerance) { return Math.abs(a - b) <= (tolerance === undefined ? 1e-6 * Math.max(1, Math.abs(b)) : tolerance); }

// ---- numbers
check(S.parseNumber("1.5") === 1.5, "1.5");
check(S.parseNumber("1,5") === 1.5, "1,5 (decimal comma)");
check(S.parseNumber("1.000") === 1000, "1.000 (thousands)");
check(S.parseNumber("1,000,000") === 1000000, "1,000,000");
check(S.parseNumber("1.234,5") === 1234.5, "1.234,5");
check(S.parseNumber("1,234.5") === 1234.5, "1,234.5");
check(S.parseNumber("0.250") === 0.25, "0.250 is a decimal");
check(isNaN(S.parseNumber("abc")), "abc is not a number");
check(S.decimalsFor(1234.5) === 2 && S.decimalsFor(3) === 0 && S.decimalsFor(0.000123) >= 5, "decimals shown");

// ---- what was typed
const known = ["USD", "COP", "EUR", "MXN", "GBP", "JPY"];
function p(q, peso) { return S.parse(q, known, peso); }
let r = p("5 km a millas");
check(r && r.kind === "units" && r.from === "km" && r.to === "mi" && r.value === 5, "5 km a millas");
check(near(S.convertUnits(5, "km", "mi"), 3.10685596), "5 km = 3.107 mi");
r = p("5km");
check(r && r.kind === "units" && r.to === "mi", "5km → miles by default");
r = p("100 f a c");
check(r && r.from === "f" && r.to === "c" && near(S.convertUnits(100, "f", "c"), 37.7777778), "100 °F = 37.8 °C");
r = p("20 grados");
check(r && r.from === "c" && r.to === "f" && near(S.convertUnits(20, "c", "f"), 68), "20 grados → 68 °F");
r = p("3 metros cuadrados a pies cuadrados");
check(r && r.from === "m2" && r.to === "ft2", "metros cuadrados a pies cuadrados (several words)");
r = p("5 in a cm");
check(r && r.from === "in" && r.to === "cm" && near(S.convertUnits(5, "in", "cm"), 12.7), "5 in a cm (in is a unit, a is the word)");
r = p("1,5 litros en galones");
check(r && r.value === 1.5 && r.from === "l" && r.to === "gal", "1,5 litros en galones");
r = p("2 horas a minutos");
check(r && r.from === "h" && r.to === "min" && S.convertUnits(2, "h", "min") === 120, "2 horas a minutos");
r = p("2 años a días");
check(r && r.from === "yr" && r.to === "d", "años (ñ) a días");
r = p("5km=mi");
check(r && r.from === "km" && r.to === "mi", "5km=mi");
r = p("10 kg a lb");
check(r && near(S.convertUnits(10, "kg", "lb"), 22.0462262), "10 kg = 22.05 lb");
check(p("5 km a kg") === null, "km to kg is not a conversion");
check(p("100 mb") === null, "a unit with no usual counterpart and no target: nothing");
check(p("15") === null && p("2+2") === null && p("hola") === null, "plain numbers, math and words are not conversions");

r = p("100 usd a cop");
check(r && r.kind === "money" && r.from === "USD" && r.to === "COP" && r.amount === 100, "100 usd a cop");
r = p("50 euros a pesos", "MXN");
check(r && r.from === "EUR" && r.to === "MXN", "pesos are this country's peso");
r = p("50 euros a pesos");
check(r && r.to === "COP", "pesos without a country: COP");
r = p("$100 a cop");
check(r && r.from === "USD" && r.amount === 100 && r.to === "COP", "$100 a cop");
r = p("20 dólares");
check(r && r.from === "USD" && r.to === null, "20 dólares (accent) → to the local currency later");
r = p("100 jpy a eur");
check(r && r.from === "JPY" && r.to === "EUR", "ISO codes with rates");
check(p("100 xyz a abc") === null, "unknown codes: nothing");
check(near(S.convertMoney(100, "USD", "COP", { USD: 1, COP: 4000 }), 400000), "money conversion");
check(near(S.convertMoney(100, "EUR", "COP", { USD: 1, EUR: 0.9, COP: 4000 }), 444444.444, 0.01), "cross rates");
check(isNaN(S.convertMoney(1, "USD", "XXX", { USD: 1 })), "a currency without a rate");

r = p("15% de 230");
check(r && r.kind === "percent" && r.op === "of" && r.value === 15 && r.of === 230, "15% de 230");
r = p("15 por ciento de 230");
check(r && r.op === "of", "15 por ciento de 230");
r = p("230 + 15%");
check(r && r.op === "+" && r.of === 230 && r.value === 15, "230 + 15%");

r = p("hora en tokio");
check(r && r.kind === "time" && r.place === "tokio", "hora en tokio");
r = p("¿Qué hora es en Nueva York?");
check(r && r.kind === "time" && r.place === "nueva york", "¿Qué hora es en Nueva York?");
r = p("time in london");
check(r && r.kind === "time" && r.place === "london", "time in london");
r = p("tokio hora");
check(r && r.kind === "time" && r.place === "tokio", "tokio hora");

// ---- time in another place (zones as ii-shim timezones prints them)
const zones = [
    { id: "Tokyo Standard Time", offset: 540, name: "(UTC+09:00) Osaka, Sapporo, Tokio", std: "Hora estándar de Tokio", dst: false },
    { id: "SA Pacific Standard Time", offset: -300, name: "(UTC-05:00) Bogotá, Lima, Quito, Rio Branco", std: "Hora est. Pacífico, Sudamérica", dst: false },
    { id: "Eastern Standard Time", offset: -300, name: "(UTC-05:00) Hora del este (EE.UU. y Canadá)", std: "Hora estándar del Este", dst: false },
    { id: "Romance Standard Time", offset: 60, name: "(UTC+01:00) Bruselas, Copenhague, Madrid, París", std: "Hora estándar romance", dst: false },
    { id: "AUS Eastern Standard Time", offset: 660, name: "(UTC+10:00) Canberra, Melbourne, Sídney", std: "Hora de verano este, Australia", dst: true },
];
let z = S.zoneFor("tokio", zones);
check(z && z.zone.id === "Tokyo Standard Time", "tokio (alias)");
z = S.zoneFor("sapporo", zones);
check(z && z.zone.id === "Tokyo Standard Time", "sapporo (Windows' own list)");
z = S.zoneFor("copenhague", zones);
check(z && z.zone.id === "Romance Standard Time", "copenhague (Windows' own list)");
z = S.zoneFor("Medellín", zones);
check(z && z.zone.id === "SA Pacific Standard Time", "Medellín (alias, accent)");
z = S.zoneFor("sidney", zones);
check(z && z.zone.offset === 660, "sidney, on summer time");
check(S.zoneFor("atlantida", zones) === null, "a place that is nowhere");
const t = S.timeThere(zones[0], Date.UTC(2026, 10, 1, 14, 30), -300); // 9:30 in Colombia
check(t.hours === 23 && t.minutes === 30 && t.dayShift === 0 && t.offsetFromHere === 840, "Tokyo is 23:30 when Colombia is 9:30");
const t2 = S.timeThere(zones[0], Date.UTC(2026, 10, 1, 16, 0), -300); // 11:00 in Colombia → 01:00 next day in Tokyo
check(t2.hours === 1 && t2.dayShift === 1, "and past midnight it says tomorrow");

// ---- commands
let c = S.matchCommands("bloquear", true);
check(c.length > 0 && c[0].command.id === "lock", "bloquear → lock");
c = S.matchCommands("apa", true);
check(c.length > 0 && c[0].command.id === "poweroff" && c[0].score <= 0.5, "half a word does not make shutting down the first row");
c = S.matchCommands("apagar", true);
check(c.length > 0 && c[0].command.id === "poweroff" && c[0].score === 1, "apagar typed in full");
c = S.matchCommands("modo oscuro", true);
check(c.length > 0 && c[0].command.id === "dark", "modo oscuro");
c = S.matchCommands("no molestar 1", true);
check(c.length > 0 && c[0].command.id === "dndHour", "no molestar 1 → for an hour");
c = S.matchCommands("vaciar", true);
check(c.length > 0 && c[0].command.id === "emptyBin", "vaciar → empty the bin");
c = S.matchCommands("captura", true);
check(c.length > 0 && c[0].command.id === "screenshot", "captura");
c = S.matchCommands("lock", false);
check(c.length > 0 && c[0].command.id === "lock" && c[0].name === "Lock the PC", "English names in English");
c = S.matchCommands("lock", true);
check(c.length > 0 && c[0].command.id === "lock" && c[0].name === "Bloquear el equipo", "English words found, Spanish name shown");
check(S.matchCommands("x", true).length === 0, "one letter finds no command");
check(new Set(S.COMMANDS.map(x => x.id)).size === S.COMMANDS.length, "command ids are unique");

// ---- Windows' settings
let w = S.matchWindowsSettings("bluetooth", true);
check(w.length > 0 && w[0].page === "bluetooth", "bluetooth");
w = S.matchWindowsSettings("sonido", true);
check(w.length > 0 && w[0].page === "sound", "sonido");
w = S.matchWindowsSettings("audifonos", true);
check(w.length > 0 && w[0].page === "bluetooth", "audífonos → Bluetooth (other words)");
w = S.matchWindowsSettings("desinstalar", true);
check(w.length > 0 && w[0].page === "appsfeatures", "desinstalar → installed apps");
w = S.matchWindowsSettings("contraseña", true);
check(w.length > 0 && w[0].page === "signinoptions", "contraseña → sign-in options");
w = S.matchWindowsSettings("wifi", true);
check(w.length > 0 && w[0].page === "network-wifi", "wifi");
check(new Set(S.WINDOWS_SETTINGS.map(x => x[0])).size === S.WINDOWS_SETTINGS.length, "ms-settings pages are unique");
check(S.WINDOWS_SETTINGS.every(x => /^[a-z0-9-]+$/.test(x[0])), "ms-settings pages are plain names");

// ---- ii's settings (the scoring of Configuración's own search)
const words = S.settingsWords("barra abajo");
check(words.join(" ") === "barra abajo", "settings words");
check(S.scoreSetting(words, " posicion barra abajo arriba", "posicion", false) > 0, "found by other words");
check(S.scoreSetting(words, " posicion barra arriba", "posicion", false) === -1, "a word missing: not found");
check(S.scoreSetting(["barra"], " barra", "barra", false) > S.scoreSetting(["barra"], " algo barra", "algo", false), "its name counts more");

// ---- matching
check(S.matchScore("spoti", "Spotify") > 0.9, "a prefix scores high");
check(S.matchScore("brave", "Inicio - Brave") > 0.5, "a word of the title");
check(S.matchScore("xyz", "Spotify") === 0, "nothing in common");
check(S.matchScore("configuracion", "Configuración") === 1, "accents do not matter");

console.log(`${checks} checks, ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
