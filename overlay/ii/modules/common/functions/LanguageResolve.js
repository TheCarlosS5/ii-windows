.pragma library

// ii-windows (C12): which UI language to load, from the translation files that really exist.
// Pure functions (also run by tools/sandbox/tests/test-language.ps1 under Node).

// "C:\a\b", "C:/a/b", "/C:/a/b" or "file:///C:/a/b" -> a file URL that FolderListModel accepts.
function folderUrl(path) {
    let p = String(path || "").replace(/\\/g, "/");
    if (p.startsWith("file:")) return p;
    return p.startsWith("/") ? "file://" + p : "file:///" + p;
}

// File names of a translations folder -> the language codes of its .json files, sorted. Anything
// that is not a locale name (a "tools" folder, a readme) is not a language.
function parseLanguages(fileNames) {
    const found = [];
    for (const name of (fileNames || [])) {
        const m = /^([a-z]{2,3}(?:_[A-Za-z0-9]{2,4})?)\.json$/.exec(String(name));
        if (m && !found.includes(m[1])) found.push(m[1]);
    }
    return found.sort();
}

// "es-CO", "es_CO.UTF-8", "ES_co@euro" -> "es_CO"; "" for something that is not a locale.
function normalize(code) {
    const m = /^([A-Za-z]{2,3})(?:[-_]([A-Za-z0-9]{2,4}))?(?:[.@].*)?$/.exec(String(code || "").trim());
    if (!m) return "";
    return m[1].toLowerCase() + (m[2] ? "_" + (m[2].length === 2 ? m[2].toUpperCase() : m[2][0].toUpperCase() + m[2].slice(1).toLowerCase()) : "");
}

// The best available language for a requested one: the exact one; else another variant of the same
// language (es_CO -> es_MX when es_CO.json is not shipped); else English. Nothing available yet
// (the folder has not been scanned): the requested one, so nothing is guessed.
function resolve(code, available) {
    const wanted = normalize(code);
    const list = available || [];
    if (list.length === 0) return wanted || "en_US";
    if (!wanted) return list.includes("en_US") ? "en_US" : list[0];
    if (list.includes(wanted)) return wanted;
    const language = wanted.split("_")[0];
    const sameLanguage = list.filter(l => l.split("_")[0] === language).sort();
    if (sameLanguage.length > 0) return sameLanguage[0];
    return list.includes("en_US") ? "en_US" : list[0];
}
