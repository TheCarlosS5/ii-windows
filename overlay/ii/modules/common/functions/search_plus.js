.pragma library
// ii-windows (plan 2026-10-31, E1): "Buscar todo", the parts of the launcher that are plain logic. What the launcher
// finds besides apps: open windows, ii's and Windows' settings, commands, conversions (units, percentages, money, the
// time in another city). services/SearchPlus.qml asks these functions and makes the result rows; nothing here
// touches QML, so tests/search-plus/test.js runs it under Node.

// ---- text ------------------------------------------------------------------------------------------------------------

function norm(text) { // lower case, no accents, single spaces
    return String(text || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/\s+/g, " ").trim();
}

function stem(word) { // plurals find the singular: "notas" → "nota", "colores" → "color"
    if (word.length > 4 && word.endsWith("es")) return word.slice(0, -2);
    if (word.length > 3 && word.endsWith("s")) return word.slice(0, -1);
    return word;
}

// How well `query` names `text`, 0 (not at all) to 1 (exactly). Every word typed has to start a word of the text
// (or, from 4 letters, appear inside one); the whole text starting with what was typed scores best.
function matchScore(query, text) {
    const q = norm(query);
    const t = norm(text);
    if (!q || !t) return 0;
    if (q === t) return 1;
    if (t.startsWith(q)) return 0.9 + 0.05 * (q.length / t.length);
    const words = q.split(" ");
    const tw = t.split(/[^a-z0-9ñ]+/).filter(w => w.length > 0);
    let starts = 0;
    for (const w of words) {
        if (tw.some(x => x.startsWith(w) || x.startsWith(stem(w)))) starts += 1;
        else if (w.length >= 4 && t.includes(w)) starts += 0.6;
        else return 0;
    }
    return 0.55 + 0.25 * (starts / words.length) * Math.min(1, q.length / Math.max(4, t.length * 0.6));
}

// The best matchScore among several names of the same thing.
function bestScore(query, names) {
    let best = 0;
    for (const n of names) best = Math.max(best, matchScore(query, n));
    return best;
}

// ---- numbers ---------------------------------------------------------------------------------------------------------

// "1.5", "1,5" (decimal comma), "1.000" / "1,000" (thousands), "1.234,5", "1,234.5" → a number, or NaN.
function parseNumber(text) {
    let s = String(text || "").trim().replace(/\s/g, "");
    if (!/^-?[\d.,]+$/.test(s) || !/\d/.test(s)) return NaN;
    const dot = s.lastIndexOf(".");
    const comma = s.lastIndexOf(",");
    if (dot >= 0 && comma >= 0) {
        const decimal = dot > comma ? "." : ",";
        const thousands = decimal === "." ? "," : ".";
        s = s.split(thousands).join("").replace(decimal, ".");
    } else if (comma >= 0 || dot >= 0) {
        const sep = comma >= 0 ? "," : ".";
        const parts = s.split(sep);
        // 1.000 / 1,000,000: thousands. 1,5 / 1.5 / 0.250: decimal.
        if (parts.length > 2 || (parts.length === 2 && parts[1].length === 3 && parts[0].replace("-", "").length <= 3 && parts[0].replace("-", "") !== "0"))
            s = parts.join("");
        else s = parts.join(".");
    }
    const n = Number(s);
    return isFinite(n) ? n : NaN;
}

// Decimals worth showing: 1234.5 → 2, 0.000123 → enough for 3 significant digits, whole numbers → 0.
function decimalsFor(n) {
    const a = Math.abs(n);
    if (a === 0 || Number.isInteger(n)) return 0;
    if (a >= 100) return Math.abs(n - Math.round(n)) < 0.005 ? 0 : 2;
    if (a >= 1) return 2;
    return Math.min(10, Math.max(2, 2 - Math.floor(Math.log10(a))));
}

function rounded(n) {
    const d = decimalsFor(n);
    const f = Math.pow(10, d);
    return Math.round(n * f) / f;
}

// ---- units -----------------------------------------------------------------------------------------------------------
// [id, dimension, factor to the dimension's base unit, symbol shown, names (normalized: lower case, no accents)]

var UNITS = [
    ["mm", "length", 0.001, "mm", ["mm", "milimetro", "milimetros", "millimeter", "millimeters", "millimetre"]],
    ["cm", "length", 0.01, "cm", ["cm", "centimetro", "centimetros", "centimeter", "centimeters", "centimetre"]],
    ["m", "length", 1, "m", ["m", "mt", "mts", "metro", "metros", "meter", "meters", "metre", "metres"]],
    ["km", "length", 1000, "km", ["km", "kms", "kilometro", "kilometros", "kilometer", "kilometers", "kilometre"]],
    ["in", "length", 0.0254, "in", ["in", "pulgada", "pulgadas", "inch", "inches", "\""]],
    ["ft", "length", 0.3048, "ft", ["ft", "pie", "pies", "foot", "feet"]],
    ["yd", "length", 0.9144, "yd", ["yd", "yarda", "yardas", "yard", "yards"]],
    ["mi", "length", 1609.344, "mi", ["mi", "milla", "millas", "mile", "miles"]],
    ["nmi", "length", 1852, "nmi", ["nmi", "milla nautica", "millas nauticas", "nautical mile", "nautical miles"]],
    ["mg", "mass", 0.000001, "mg", ["mg", "miligramo", "miligramos", "milligram", "milligrams"]],
    ["g", "mass", 0.001, "g", ["g", "gr", "grs", "gramo", "gramos", "gram", "grams"]],
    ["kg", "mass", 1, "kg", ["kg", "kgs", "kilo", "kilos", "kilogramo", "kilogramos", "kilogram", "kilograms"]],
    ["t", "mass", 1000, "t", ["t", "tonelada", "toneladas", "ton", "tons", "tonne", "tonnes"]],
    ["oz", "mass", 0.028349523125, "oz", ["oz", "onza", "onzas", "ounce", "ounces"]],
    ["lb", "mass", 0.45359237, "lb", ["lb", "lbs", "libra", "libras", "pound", "pounds"]],
    ["st", "mass", 6.35029318, "st", ["st", "stone", "stones"]],
    ["ml", "volume", 0.001, "ml", ["ml", "mililitro", "mililitros", "milliliter", "milliliters", "millilitre"]],
    ["cl", "volume", 0.01, "cl", ["cl", "centilitro", "centilitros", "centiliter"]],
    ["l", "volume", 1, "l", ["l", "lt", "lts", "litro", "litros", "liter", "liters", "litre", "litres"]],
    ["m3", "volume", 1000, "m³", ["m3", "m³", "metro cubico", "metros cubicos", "cubic meter", "cubic meters"]],
    ["gal", "volume", 3.785411784, "gal", ["gal", "galon", "galones", "gallon", "gallons"]],
    ["qt", "volume", 0.946352946, "qt", ["qt", "cuarto de galon", "quart", "quarts"]],
    ["pt", "volume", 0.473176473, "pt", ["pt", "pinta", "pintas", "pint", "pints"]],
    ["cup", "volume", 0.2365882365, "tazas", ["taza", "tazas", "cup", "cups"]],
    ["floz", "volume", 0.0295735295625, "fl oz", ["fl oz", "floz", "onza liquida", "onzas liquidas", "fluid ounce", "fluid ounces"]],
    ["tbsp", "volume", 0.01478676478125, "cda", ["cda", "cucharada", "cucharadas", "tbsp", "tablespoon", "tablespoons"]],
    ["tsp", "volume", 0.00492892159375, "cdta", ["cdta", "cucharadita", "cucharaditas", "tsp", "teaspoon", "teaspoons"]],
    ["cm2", "area", 0.0001, "cm²", ["cm2", "cm²", "centimetro cuadrado", "centimetros cuadrados"]],
    ["m2", "area", 1, "m²", ["m2", "m²", "metro cuadrado", "metros cuadrados", "square meter", "square meters"]],
    ["km2", "area", 1000000, "km²", ["km2", "km²", "kilometro cuadrado", "kilometros cuadrados", "square kilometer", "square kilometers"]],
    ["ha", "area", 10000, "ha", ["ha", "hectarea", "hectareas", "hectare", "hectares"]],
    ["acre", "area", 4046.8564224, "acres", ["acre", "acres"]],
    ["ft2", "area", 0.09290304, "ft²", ["ft2", "ft²", "pie cuadrado", "pies cuadrados", "square foot", "square feet", "sq ft"]],
    ["mps", "speed", 1, "m/s", ["m/s", "mps", "metros por segundo", "meters per second"]],
    ["kmh", "speed", 1 / 3.6, "km/h", ["km/h", "kmh", "kph", "kilometros por hora", "kilometers per hour"]],
    ["mph", "speed", 0.44704, "mph", ["mph", "mi/h", "millas por hora", "miles per hour"]],
    ["kn", "speed", 0.514444444444, "nudos", ["kn", "kt", "nudo", "nudos", "knot", "knots"]],
    ["bit", "data", 0.125, "bit", ["bit", "bits"]],
    ["byte", "data", 1, "B", ["byte", "bytes"]],
    ["kb", "data", 1000, "KB", ["kb", "kilobyte", "kilobytes"]],
    ["mb", "data", 1000000, "MB", ["mb", "megabyte", "megabytes", "megas"]],
    ["gb", "data", 1000000000, "GB", ["gb", "gigabyte", "gigabytes", "gigas"]],
    ["tb", "data", 1000000000000, "TB", ["tb", "terabyte", "terabytes", "teras"]],
    ["kib", "data", 1024, "KiB", ["kib", "kibibyte", "kibibytes"]],
    ["mib", "data", 1048576, "MiB", ["mib", "mebibyte", "mebibytes"]],
    ["gib", "data", 1073741824, "GiB", ["gib", "gibibyte", "gibibytes"]],
    ["tib", "data", 1099511627776, "TiB", ["tib", "tebibyte", "tebibytes"]],
    ["ms", "time", 0.001, "ms", ["ms", "milisegundo", "milisegundos", "millisecond", "milliseconds"]],
    ["s", "time", 1, "s", ["s", "seg", "segs", "segundo", "segundos", "sec", "secs", "second", "seconds"]],
    ["min", "time", 60, "min", ["min", "mins", "minuto", "minutos", "minute", "minutes"]],
    ["h", "time", 3600, "h", ["h", "hr", "hrs", "hora", "horas", "hour", "hours"]],
    ["d", "time", 86400, "días", ["d", "dia", "dias", "day", "days"]],
    ["wk", "time", 604800, "semanas", ["semana", "semanas", "week", "weeks", "wk"]],
    ["yr", "time", 31557600, "años", ["ano", "anos", "year", "years", "yr"]],
    ["c", "temperature", 0, "°C", ["c", "°c", "ºc", "celsius", "centigrado", "centigrados", "grados celsius", "grados c", "grados"]],
    ["f", "temperature", 0, "°F", ["f", "°f", "ºf", "fahrenheit", "grados fahrenheit", "grados f"]],
    ["k", "temperature", 0, "K", ["k", "kelvin", "kelvins"]],
];

var unitByName = null;
function unitNamed(text) {
    if (!unitByName) {
        unitByName = {};
        for (const u of UNITS) for (const n of u[4]) unitByName[n] = u;
    }
    // "año" and "años" lose their tilde in norm() ("ano"); keep "ñ" for nothing else here.
    return unitByName[norm(text).replace(/ñ/g, "n")] || null;
}

function toKelvin(v, u) { return u === "c" ? v + 273.15 : u === "f" ? (v - 32) * 5 / 9 + 273.15 : v; }
function fromKelvin(v, u) { return u === "c" ? v - 273.15 : u === "f" ? (v - 273.15) * 9 / 5 + 32 : v; }

function convertUnits(value, fromId, toId) {
    const from = UNITS.find(u => u[0] === fromId);
    const to = UNITS.find(u => u[0] === toId);
    if (!from || !to || from[1] !== to[1]) return NaN;
    if (from[1] === "temperature") return fromKelvin(toKelvin(value, fromId), toId);
    return value * from[2] / to[2];
}

// ---- money -----------------------------------------------------------------------------------------------------------
// Currency words → ISO code. "peso"/"pesos" alone is the peso of this PC's country (localPeso), else COP.

var CURRENCY_WORDS = {
    "$": "USD", "us$": "USD", "usd": "USD", "dolar": "USD", "dolares": "USD", "dollar": "USD", "dollars": "USD",
    "dolar estadounidense": "USD", "dolares estadounidenses": "USD",
    "€": "EUR", "eur": "EUR", "euro": "EUR", "euros": "EUR",
    "£": "GBP", "gbp": "GBP", "libra esterlina": "GBP", "libras esterlinas": "GBP", "pound sterling": "GBP",
    "¥": "JPY", "jpy": "JPY", "yen": "JPY", "yenes": "JPY",
    "cop": "COP", "peso colombiano": "COP", "pesos colombianos": "COP",
    "mxn": "MXN", "peso mexicano": "MXN", "pesos mexicanos": "MXN",
    "ars": "ARS", "peso argentino": "ARS", "pesos argentinos": "ARS",
    "clp": "CLP", "peso chileno": "CLP", "pesos chilenos": "CLP",
    "uyu": "UYU", "peso uruguayo": "UYU", "pesos uruguayos": "UYU",
    "dop": "DOP", "peso dominicano": "DOP", "pesos dominicanos": "DOP",
    "pen": "PEN", "sol": "PEN", "soles": "PEN", "brl": "BRL", "real": "BRL", "reales": "BRL",
    "ves": "VES", "bolivar": "VES", "bolivares": "VES", "cad": "CAD", "dolar canadiense": "CAD", "dolares canadienses": "CAD",
    "chf": "CHF", "franco suizo": "CHF", "francos suizos": "CHF", "cny": "CNY", "yuan": "CNY", "yuanes": "CNY",
    "krw": "KRW", "won": "KRW", "inr": "INR", "rupia": "INR", "rupias": "INR", "btc": null,
};
var PESO_OF_COUNTRY = { CO: "COP", MX: "MXN", AR: "ARS", CL: "CLP", UY: "UYU", DO: "DOP", PH: "PHP", CU: "CUP" };

// `known`: the ISO codes there are rates for (any three letters of it are accepted as is).
function currencyNamed(text, known, localPeso) {
    const t = norm(text);
    if (t === "peso" || t === "pesos") return localPeso || "COP";
    if (Object.prototype.hasOwnProperty.call(CURRENCY_WORDS, t)) return CURRENCY_WORDS[t];
    const code = t.toUpperCase();
    if (/^[A-Z]{3}$/.test(code) && known && known.indexOf(code) >= 0) return code;
    return null;
}

function convertMoney(amount, from, to, rates) { // rates: { USD: 1, COP: 4100, ... } against one base
    if (!rates || !rates[from] || !rates[to]) return NaN;
    return amount / rates[from] * rates[to];
}

// ---- what was typed --------------------------------------------------------------------------------------------------
// parse(query, known currencies, local peso) →
//   { kind: "units", value, from, to }        (unit ids; `to` may be null: the usual counterpart)
//   { kind: "money", amount, from, to }       (ISO codes; `to` may be null: the local one, or USD)
//   { kind: "percent", value, of, op }        ("15% de 230" → op "of"; "230 + 15%" → op "+")
//   { kind: "time", place }                   ("hora en tokio", "time in tokyo")
//   null

var USUAL = { km: "mi", mi: "km", m: "ft", ft: "m", cm: "in", in: "cm", kg: "lb", lb: "kg", g: "oz", oz: "g", l: "gal",
    gal: "l", c: "f", f: "c", k: "c", kmh: "mph", mph: "kmh", ml: "floz", floz: "ml", m2: "ft2", ft2: "m2", ha: "acre", acre: "ha" };

function parse(query, known, localPeso) {
    const q = norm(query).replace(/[¿?¡!]/g, "").trim();
    if (!q) return null;

    let m = /^(?:que |qué )?hora (?:es )?(?:en|de) (.+)$/.exec(q) || /^(?:what )?time (?:is it )?in (.+)$/.exec(q)
        || /^hora (.+)$/.exec(q) || /^(.+) hora$/.exec(q);
    if (m && !/^\d/.test(m[1])) return { kind: "time", place: m[1].replace(/[?¿]/g, "").trim() };

    m = /^(-?[\d.,]+)\s*(?:%|por ?ciento|percent)\s+(?:de|del|of)\s+(-?[\d.,]+)$/.exec(q);
    if (m) {
        const v = parseNumber(m[1]), of = parseNumber(m[2]);
        if (!isNaN(v) && !isNaN(of)) return { kind: "percent", value: v, of: of, op: "of" };
    }
    m = /^(-?[\d.,]+)\s*([+-])\s*([\d.,]+)\s*(?:%|por ?ciento)$/.exec(q);
    if (m) {
        const base = parseNumber(m[1]), v = parseNumber(m[3]);
        if (!isNaN(base) && !isNaN(v)) return { kind: "percent", value: v, of: base, op: m[2] };
    }

    // "<number> <unit or currency> [a|en|to|in|=|->|>] [<unit or currency>]", the number may come after a symbol: "$100 a cop".
    m = /^([$€£¥])\s*([\d.,]+)\s*(?:(?:a|en|to|in|=|->|>)\s+(.+))?$/.exec(q);
    let amount, fromText, toText;
    if (m) { amount = parseNumber(m[2]); fromText = m[1]; toText = m[3] || ""; }
    else {
        // "5km=mi" first: the spaced form would take "km=mi" as one unit name.
        m = /^(-?[\d.,]+)\s*([^\d\s=>]+?)\s*(?:=|->|>)\s*(.+)$/.exec(q)
            || /^(-?[\d.,]+)\s*([^\d\s].*?)(?:\s+(?:a|en|to|in|=|->|>)\s+(.+))?$/.exec(q);
        if (!m) return null;
        amount = parseNumber(m[1]); fromText = m[2]; toText = m[3] || "";
    }
    if (isNaN(amount)) return null;
    fromText = fromText.trim(); toText = toText.trim();

    const fromUnit = unitNamed(fromText), toUnit = toText ? unitNamed(toText) : null;
    if (fromUnit && (!toText ? USUAL[fromUnit[0]] : toUnit && toUnit[1] === fromUnit[1]))
        return { kind: "units", value: amount, from: fromUnit[0], to: toUnit ? toUnit[0] : USUAL[fromUnit[0]] };
    const fromMoney = currencyNamed(fromText, known, localPeso), toMoney = toText ? currencyNamed(toText, known, localPeso) : null;
    if (fromMoney && (!toText || toMoney) && fromMoney !== toMoney)
        return { kind: "money", amount: amount, from: fromMoney, to: toMoney };
    return null;
}

// ---- time in another place -------------------------------------------------------------------------------------------
// City (normalized) → Windows time zone id, for the places Windows' own zone names do not mention.

var CITY_ZONES = {
    "colombia": "SA Pacific Standard Time", "medellin": "SA Pacific Standard Time", "bogota": "SA Pacific Standard Time",
    "cali": "SA Pacific Standard Time", "barranquilla": "SA Pacific Standard Time", "cartagena": "SA Pacific Standard Time",
    "peru": "SA Pacific Standard Time", "ecuador": "SA Pacific Standard Time", "panama": "SA Pacific Standard Time",
    "nueva york": "Eastern Standard Time", "new york": "Eastern Standard Time", "nyc": "Eastern Standard Time",
    "miami": "Eastern Standard Time", "washington": "Eastern Standard Time", "boston": "Eastern Standard Time",
    "toronto": "Eastern Standard Time", "florida": "Eastern Standard Time", "chicago": "Central Standard Time",
    "texas": "Central Standard Time", "houston": "Central Standard Time", "dallas": "Central Standard Time",
    "denver": "Mountain Standard Time", "los angeles": "Pacific Standard Time", "san francisco": "Pacific Standard Time",
    "seattle": "Pacific Standard Time", "las vegas": "Pacific Standard Time", "california": "Pacific Standard Time",
    "vancouver": "Pacific Standard Time", "mexico": "Central Standard Time (Mexico)", "ciudad de mexico": "Central Standard Time (Mexico)",
    "cdmx": "Central Standard Time (Mexico)", "guadalajara": "Central Standard Time (Mexico)", "monterrey": "Central Standard Time (Mexico)",
    "cancun": "Eastern Standard Time (Mexico)", "caracas": "Venezuela Standard Time", "venezuela": "Venezuela Standard Time",
    "santiago": "Pacific SA Standard Time", "chile": "Pacific SA Standard Time", "buenos aires": "Argentina Standard Time",
    "argentina": "Argentina Standard Time", "montevideo": "Montevideo Standard Time", "uruguay": "Montevideo Standard Time",
    "sao paulo": "E. South America Standard Time", "rio de janeiro": "E. South America Standard Time", "brasil": "E. South America Standard Time",
    "brazil": "E. South America Standard Time", "la paz": "SA Western Standard Time", "bolivia": "SA Western Standard Time",
    "asuncion": "Paraguay Standard Time", "paraguay": "Paraguay Standard Time", "santo domingo": "SA Western Standard Time",
    "puerto rico": "SA Western Standard Time", "san juan": "SA Western Standard Time", "habana": "Cuba Standard Time",
    "la habana": "Cuba Standard Time", "cuba": "Cuba Standard Time", "guatemala": "Central America Standard Time",
    "costa rica": "Central America Standard Time", "san jose": "Central America Standard Time", "el salvador": "Central America Standard Time",
    "honduras": "Central America Standard Time", "nicaragua": "Central America Standard Time",
    "londres": "GMT Standard Time", "london": "GMT Standard Time", "reino unido": "GMT Standard Time", "inglaterra": "GMT Standard Time",
    "dublin": "GMT Standard Time", "lisboa": "GMT Standard Time", "portugal": "GMT Standard Time",
    "madrid": "Romance Standard Time", "espana": "Romance Standard Time", "spain": "Romance Standard Time", "barcelona": "Romance Standard Time",
    "paris": "Romance Standard Time", "francia": "Romance Standard Time", "france": "Romance Standard Time",
    "berlin": "W. Europe Standard Time", "alemania": "W. Europe Standard Time", "germany": "W. Europe Standard Time",
    "roma": "W. Europe Standard Time", "rome": "W. Europe Standard Time", "italia": "W. Europe Standard Time", "italy": "W. Europe Standard Time",
    "amsterdam": "W. Europe Standard Time", "viena": "W. Europe Standard Time", "zurich": "W. Europe Standard Time",
    "atenas": "GTB Standard Time", "estambul": "Turkey Standard Time", "istanbul": "Turkey Standard Time", "turquia": "Turkey Standard Time",
    "moscu": "Russian Standard Time", "moscow": "Russian Standard Time", "rusia": "Russian Standard Time",
    "dubai": "Arabian Standard Time", "el cairo": "Egypt Standard Time", "cairo": "Egypt Standard Time", "egipto": "Egypt Standard Time",
    "johannesburgo": "South Africa Standard Time", "sudafrica": "South Africa Standard Time", "lagos": "W. Central Africa Standard Time",
    "india": "India Standard Time", "delhi": "India Standard Time", "nueva delhi": "India Standard Time", "mumbai": "India Standard Time",
    "bangkok": "SE Asia Standard Time", "tailandia": "SE Asia Standard Time", "yakarta": "SE Asia Standard Time",
    "singapur": "Singapore Standard Time", "singapore": "Singapore Standard Time", "hong kong": "China Standard Time",
    "pekin": "China Standard Time", "beijing": "China Standard Time", "shanghai": "China Standard Time", "china": "China Standard Time",
    "taiwan": "Taipei Standard Time", "taipei": "Taipei Standard Time", "manila": "Singapore Standard Time", "filipinas": "Singapore Standard Time",
    "tokio": "Tokyo Standard Time", "tokyo": "Tokyo Standard Time", "japon": "Tokyo Standard Time", "japan": "Tokyo Standard Time",
    "osaka": "Tokyo Standard Time", "seul": "Korea Standard Time", "seoul": "Korea Standard Time", "corea": "Korea Standard Time",
    "sidney": "AUS Eastern Standard Time", "sydney": "AUS Eastern Standard Time", "melbourne": "AUS Eastern Standard Time",
    "australia": "AUS Eastern Standard Time", "auckland": "New Zealand Standard Time", "nueva zelanda": "New Zealand Standard Time",
    "hawai": "Hawaiian Standard Time", "hawaii": "Hawaiian Standard Time", "honolulu": "Hawaiian Standard Time",
    "utc": "UTC", "gmt": "UTC",
};

// zones: what `ii-shim timezones` printed. The zone for `place` (its alias, else a Windows zone whose localized name
// mentions it) and the place's name to show, or null.
function zoneFor(place, zones) {
    const p = norm(place);
    if (!p || !zones || !zones.length) return null;
    const id = CITY_ZONES[p];
    if (id) {
        const z = zones.find(x => x.id === id);
        if (z) return { zone: z, label: place };
    }
    for (const z of zones) {
        // "(UTC+09:00) Osaka, Sapporo, Tokio" → the places, then the zone's own name ("Hora estándar de Tokio")
        const places = norm(String(z.name).replace(/^\([^)]*\)\s*/, "")).split(/\s*,\s*/);
        if (places.some(x => x === p || (p.length >= 4 && x.startsWith(p)))) return { zone: z, label: place };
    }
    for (const z of zones) if (p.length >= 4 && norm(z.std + " " + z.id).includes(p)) return { zone: z, label: place };
    return null;
}

// The wall-clock time there for `nowMs` (ms since the epoch): { hours, minutes, dayShift (−1, 0, +1 from here) }.
function timeThere(zone, nowMs, localOffsetMinutes) {
    const there = new Date(nowMs + zone.offset * 60000);
    const here = new Date(nowMs + localOffsetMinutes * 60000);
    const dayThere = Math.floor((nowMs + zone.offset * 60000) / 86400000);
    const dayHere = Math.floor((nowMs + localOffsetMinutes * 60000) / 86400000);
    return { hours: there.getUTCHours(), minutes: there.getUTCMinutes(), dayShift: dayThere - dayHere,
             offsetFromHere: zone.offset - localOffsetMinutes, weekday: there.getUTCDay(), hereHours: here.getUTCHours() };
}

// ---- commands --------------------------------------------------------------------------------------------------------
// id, icon, Spanish names (first: shown), English names (first: shown). SearchPlus.qml runs them by id. `confirm`:
// the row says what it does in full and only comes first when the name was typed in full (no accidental shutdowns).

var COMMANDS = [
    { id: "lock", icon: "lock", es: ["Bloquear el equipo", "bloquear", "bloquear pantalla"], en: ["Lock the PC", "lock", "lock screen"] },
    { id: "suspend", icon: "bedtime", es: ["Suspender", "dormir", "suspension"], en: ["Sleep", "suspend"] },
    { id: "poweroff", icon: "power_settings_new", confirm: true, es: ["Apagar el equipo", "apagar", "apagar pc", "apagar computador"], en: ["Shut down", "shutdown", "power off"] },
    { id: "reboot", icon: "restart_alt", confirm: true, es: ["Reiniciar el equipo", "reiniciar", "reiniciar pc"], en: ["Restart the PC", "restart", "reboot"] },
    { id: "logout", icon: "logout", confirm: true, es: ["Cerrar sesión", "cerrar sesion", "salir de la sesion"], en: ["Sign out", "log out", "logout"] },
    { id: "hibernate", icon: "downloading", confirm: true, es: ["Hibernar", "hibernar"], en: ["Hibernate", "hibernate"] },
    { id: "session", icon: "power_settings_new", es: ["Menú de energía", "opciones de energia", "menu de sesion"], en: ["Power menu", "session menu"] },
    { id: "emptyBin", icon: "delete_forever", es: ["Vaciar la papelera", "vaciar papelera", "papelera de reciclaje"], en: ["Empty the Recycle Bin", "empty recycle bin", "empty trash"] },
    { id: "dark", icon: "dark_mode", es: ["Tema oscuro", "modo oscuro", "oscuro"], en: ["Dark theme", "dark mode", "dark"] },
    { id: "light", icon: "light_mode", es: ["Tema claro", "modo claro", "claro"], en: ["Light theme", "light mode"] },
    { id: "dnd", icon: "do_not_disturb_on", es: ["No molestar", "silenciar notificaciones", "concentracion"], en: ["Do not disturb", "dnd", "silence notifications"] },
    { id: "dndHour", icon: "notifications_paused", es: ["No molestar durante 1 hora", "no molestar 1 hora", "no molestar una hora", "silenciar 1 hora"], en: ["Do not disturb for 1 hour", "dnd 1 hour", "dnd 1h"] },
    { id: "dndTomorrow", icon: "bedtime_off", es: ["No molestar hasta mañana", "no molestar hasta manana"], en: ["Do not disturb until tomorrow", "dnd until tomorrow"] },
    { id: "screenshot", icon: "screenshot_region", es: ["Captura de pantalla", "captura", "recorte", "pantallazo"], en: ["Screenshot", "screen capture", "snip"] },
    { id: "pinCapture", icon: "push_pin", es: ["Fijar una captura en pantalla", "fijar captura", "anclar captura", "captura fija"], en: ["Pin a capture on screen", "pin capture", "pin screenshot"] },
    { id: "colorPicker", icon: "colorize", es: ["Selector de color", "cuentagotas", "color de pantalla"], en: ["Color picker", "eyedropper"] },
    { id: "wallpaper", icon: "wallpaper", es: ["Cambiar el fondo de pantalla", "fondo de pantalla", "cambiar fondo"], en: ["Change wallpaper", "wallpaper"] },
    { id: "wallpaperRandom", icon: "shuffle", es: ["Fondo de pantalla aleatorio", "fondo aleatorio"], en: ["Random wallpaper"] },
    { id: "settings", icon: "settings", es: ["Configuración de ii", "configuracion", "ajustes", "preferencias"], en: ["ii settings", "settings", "preferences"] },
    { id: "windowsSettings", icon: "settings_applications", es: ["Configuración de Windows", "configuracion de windows", "ajustes de windows"], en: ["Windows Settings", "windows settings"] },
    { id: "taskManager", icon: "browse_activity", es: ["Administrador de tareas", "administrador de tareas", "procesos"], en: ["Task Manager", "task manager"] },
    { id: "explorer", icon: "folder_open", es: ["Explorador de archivos", "explorador", "mis archivos"], en: ["File Explorer", "explorer", "files"] },
    { id: "store", icon: "storefront", es: ["Tienda de apps", "tienda", "instalar apps"], en: ["App store", "store", "install apps"] },
    { id: "updates", icon: "system_update_alt", es: ["Buscar actualizaciones de ii", "actualizar ii", "actualizaciones"], en: ["Check for ii updates", "update ii", "updates"] },
    { id: "restartShell", icon: "refresh", es: ["Reiniciar ii", "reiniciar ii", "recargar ii", "reiniciar la shell"], en: ["Restart ii", "restart shell", "reload ii"] },
    { id: "clipboard", icon: "content_paste", es: ["Historial del portapapeles", "portapapeles"], en: ["Clipboard history", "clipboard"] },
    { id: "emoji", icon: "add_reaction", es: ["Emojis", "emoji", "emoticonos"], en: ["Emoji", "emojis"] },
    { id: "showDesktop", icon: "desktop_windows", es: ["Mostrar el escritorio", "mostrar escritorio", "minimizar todo"], en: ["Show desktop", "minimize all"] },
    { id: "lightMode", icon: "speed", es: ["Modo ligero", "modo ligero", "modo rendimiento", "rendimiento"], en: ["Lite mode", "lite mode", "performance mode"] },
    { id: "nightLight", icon: "nightlight", es: ["Luz nocturna", "luz nocturna", "filtro de luz azul"], en: ["Night light", "night light", "blue light"] },
    { id: "shortcuts", icon: "keyboard", es: ["Atajos de teclado", "atajos", "teclas"], en: ["Keyboard shortcuts", "shortcuts", "hotkeys"] },
    { id: "report", icon: "bug_report", es: ["Reportar un problema de ii", "reportar problema", "reportar error"], en: ["Report a problem with ii", "report a bug"] },
];

// The commands for `query`, best first: [{ command, score, name }]. Spanish names when `spanish`.
function matchCommands(query, spanish) {
    const q = norm(query);
    if (q.length < 2) return [];
    const out = [];
    for (const c of COMMANDS) {
        const names = (spanish ? c.es : c.en).concat(spanish ? c.en : []);
        let score = bestScore(q, names);
        if (score <= 0) continue;
        // Shutting down from a half-typed word: never the first row.
        if (c.confirm && !names.some(n => norm(n) === q || norm(n).startsWith(q + " ") || (q.length >= 6 && norm(n).startsWith(q)))) score = Math.min(score, 0.5);
        out.push({ command: c, score: score, name: (spanish ? c.es : c.en)[0] });
    }
    out.sort((a, b) => b.score - a.score);
    return out;
}

// ---- Windows' settings -----------------------------------------------------------------------------------------------
// [ms-settings page, Spanish name, English name, more words (Spanish and English, normalized)]

var WINDOWS_SETTINGS = [
    ["display", "Pantalla", "Display", "brillo resolucion escala monitor hdr brightness resolution scale"],
    ["nightlight", "Luz nocturna", "Night light", "luz azul blue light"],
    ["display-advancedgraphics", "Gráficos", "Graphics", "gpu tarjeta grafica nvidia amd rendimiento graphics card"],
    ["sound", "Sonido", "Sound", "audio volumen altavoces parlantes salida microfono speakers volume output"],
    ["apps-volume", "Mezclador de volumen", "Volume mixer", "volumen por aplicacion mixer"],
    ["notifications", "Notificaciones", "Notifications", "avisos alertas"],
    ["quiethours", "Concentración", "Focus", "no molestar asistente de concentracion focus assist do not disturb"],
    ["powersleep", "Energía y suspensión", "Power & sleep", "apagar pantalla suspension energia bateria plan de energia power sleep"],
    ["batterysaver", "Ahorro de energía", "Energy saver", "bateria ahorro battery saver"],
    ["storagesense", "Almacenamiento", "Storage", "disco espacio liberar espacio disk space free up"],
    ["multitasking", "Multitarea", "Multitasking", "ajustar ventanas snap escritorios virtuales alt tab"],
    ["clipboard", "Portapapeles (Windows)", "Clipboard (Windows)", "copiar pegar historial copy paste history"],
    ["about", "Acerca de", "About", "especificaciones nombre del equipo version de windows ram procesador specs pc name"],
    ["bluetooth", "Bluetooth y dispositivos", "Bluetooth & devices", "bluetooth audifonos auriculares emparejar headphones pair"],
    ["printers", "Impresoras y escáneres", "Printers & scanners", "imprimir impresora escaner printer scanner"],
    ["mousetouchpad", "Mouse", "Mouse", "raton puntero cursor velocidad scroll"],
    ["devices-touchpad", "Panel táctil", "Touchpad", "touchpad gestos panel tactil gestures"],
    ["typing", "Escritura", "Typing", "teclado autocorrector sugerencias keyboard autocorrect"],
    ["autoplay", "Reproducción automática", "AutoPlay", "usb autoplay"],
    ["network-status", "Red e Internet", "Network & internet", "internet red conexion network connection"],
    ["network-wifi", "Wi-Fi", "Wi-Fi", "wifi wlan inalambrica wireless"],
    ["network-ethernet", "Ethernet", "Ethernet", "cable red ethernet lan"],
    ["network-vpn", "VPN", "VPN", "vpn"],
    ["network-mobilehotspot", "Zona con cobertura móvil", "Mobile hotspot", "hotspot compartir internet zona wifi"],
    ["network-airplanemode", "Modo avión", "Airplane mode", "avion airplane"],
    ["network-proxy", "Proxy", "Proxy", "proxy"],
    ["personalization", "Personalización (Windows)", "Personalization (Windows)", "personalizar"],
    ["colors", "Colores (Windows)", "Colors (Windows)", "color de enfasis accent color tema"],
    ["lockscreen", "Pantalla de bloqueo", "Lock screen", "bloqueo"],
    ["fonts", "Fuentes", "Fonts", "tipografias letras fonts"],
    ["taskbar", "Barra de tareas (Windows)", "Taskbar (Windows)", "barra de tareas taskbar"],
    ["appsfeatures", "Aplicaciones instaladas", "Installed apps", "desinstalar programas aplicaciones uninstall programs"],
    ["defaultapps", "Aplicaciones predeterminadas", "Default apps", "abrir con navegador predeterminado default browser"],
    ["startupapps", "Aplicaciones de arranque", "Startup apps", "inicio arranque al encender startup"],
    ["optionalfeatures", "Características opcionales", "Optional features", "caracteristicas opcionales features"],
    ["yourinfo", "Tu información", "Your info", "cuenta perfil microsoft account"],
    ["emailandaccounts", "Correo y cuentas", "Email & accounts", "correo cuentas email"],
    ["signinoptions", "Opciones de inicio de sesión", "Sign-in options", "contrasena pin windows hello huella password fingerprint"],
    ["otherusers", "Otros usuarios", "Other users", "usuarios familia cuentas users"],
    ["dateandtime", "Fecha y hora", "Date & time", "fecha hora zona horaria reloj time zone clock"],
    ["regionlanguage", "Idioma y región", "Language & region", "idioma lenguaje region teclado language keyboard"],
    ["speech", "Voz", "Speech", "voz dictado reconocimiento speech dictation"],
    ["gaming-gamebar", "Xbox Game Bar", "Xbox Game Bar", "game bar juegos grabar gaming"],
    ["gaming-gamemode", "Modo de juego", "Game Mode", "modo juego gaming game mode"],
    ["easeofaccess-display", "Accesibilidad", "Accessibility", "accesibilidad tamano del texto accessibility text size"],
    ["easeofaccess-narrator", "Narrador", "Narrator", "lector de pantalla narrador screen reader"],
    ["easeofaccess-magnifier", "Lupa", "Magnifier", "lupa zoom ampliar magnifier"],
    ["easeofaccess-highcontrast", "Temas de contraste", "Contrast themes", "alto contraste high contrast"],
    ["easeofaccess-keyboard", "Teclado (accesibilidad)", "Keyboard (accessibility)", "teclas especiales teclado en pantalla sticky keys on-screen keyboard"],
    ["privacy", "Privacidad y seguridad", "Privacy & security", "privacidad seguridad permisos privacy permissions"],
    ["privacy-microphone", "Permisos del micrófono", "Microphone permissions", "microfono privacidad microphone"],
    ["privacy-webcam", "Permisos de la cámara", "Camera permissions", "camara webcam privacidad camera"],
    ["privacy-location", "Ubicación", "Location", "ubicacion gps localizacion location"],
    ["windowsdefender", "Seguridad de Windows", "Windows Security", "antivirus defender virus firewall seguridad"],
    ["windowsupdate", "Windows Update", "Windows Update", "actualizaciones de windows actualizar windows updates"],
    ["windowsupdate-history", "Historial de actualizaciones", "Update history", "historial actualizaciones update history"],
    ["recovery", "Recuperación", "Recovery", "restablecer formatear reinstalar reset recovery"],
    ["activation", "Activación", "Activation", "activar windows licencia clave product key"],
    ["troubleshoot", "Solucionar problemas", "Troubleshoot", "solucionador problemas troubleshooter"],
    ["backup", "Copia de seguridad de Windows", "Windows Backup", "respaldo copia de seguridad onedrive backup"],
    ["developers", "Para programadores", "For developers", "desarrolladores modo desarrollador developer mode"],
];

// [{ page, name, score }], best first. A setting's own name counts more than its other words.
function matchWindowsSettings(query, spanish) {
    const q = norm(query);
    if (q.length < 2) return [];
    const out = [];
    for (const s of WINDOWS_SETTINGS) {
        const name = spanish ? s[1] : s[2];
        let score = Math.max(matchScore(q, name), matchScore(q, spanish ? s[2] : s[1]) * 0.95);
        if (score <= 0) {
            const words = s[3].split(" ");
            const typed = q.split(" ");
            const hits = typed.filter(w => words.some(x => x.startsWith(w) || (w.length >= 4 && x.startsWith(stem(w))))).length;
            if (hits === typed.length && q.length >= 3) score = 0.5 + 0.1 * Math.min(1, q.length / 8);
        }
        if (score > 0) out.push({ page: s[0], name: name, score: score });
    }
    out.sort((a, b) => b.score - a.score);
    return out;
}

// ---- ii's settings (the index of Configuración's own search, settings-index.js) -------------------------------------
// words: the query, normalized and stemmed; hay: the entry's haystack (" " + everything it is known by, normalized);
// label: its name as shown, normalized. The score Configuración's search uses (overlay SettingsSearchResults.qml), or
// −1 when a word typed is not there.

function settingsWords(query) {
    return norm(query).split(/\s+/).filter(w => w.length > 0).map(w => stem(w));
}

function scoreSetting(words, hay, label, isSection) {
    if (!words.every(w => hay.includes(w))) return -1;
    let score = 0;
    let inLabel = 0;
    for (const w of words) {
        if (label.includes(w)) inLabel += 1;
        if (label.startsWith(w)) score += 6;
        else if (label.includes(" " + w)) score += 4;
        else if (label.includes(w)) score += 3;
        else if (w.length >= 8 && label.includes(w.slice(0, w.length - 3))) score += 2; // desenfoque ~ desenfocar
        else if (hay.includes(" " + w)) score += 1;
    }
    if (!isSection) score += 0.5; // a control before the section that holds it...
    else if (inLabel === 0) score += 1; // ...unless only other words found it: then the section is the answer
    return score;
}

// For Node (tests/search-plus/test.js); QML ignores it.
if (typeof module !== "undefined") module.exports = { norm, stem, matchScore, bestScore, parseNumber, decimalsFor, rounded,
    UNITS, unitNamed, convertUnits, currencyNamed, convertMoney, parse, USUAL, CITY_ZONES, zoneFor, timeThere, COMMANDS,
    matchCommands, WINDOWS_SETTINGS, matchWindowsSettings, settingsWords, scoreSetting, PESO_OF_COUNTRY };
