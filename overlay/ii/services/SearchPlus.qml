pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import "../modules/common/functions/search_plus.js" as Plus
import "../modules/settings/settings-index.js" as SettingsIndex
import "../modules/settings/widgets/registry.js" as WidgetRegistry

/**
 * ii-windows (plan 2026-10-31, E1): "Buscar todo". What the launcher finds besides apps, each with a score (0–1) so
 * LauncherSearch can put the likeliest row first whatever it is:
 *   - open windows (title or app) → switch to it;
 *   - ii's settings (the index of Configuración's own search) → Configuración opens there and lights it up;
 *   - Windows' settings (a curated list of ms-settings: pages, in Spanish with synonyms);
 *   - commands: lock, sleep, shut down, empty the bin, dark theme, do not disturb, screenshot, …;
 *   - conversions: units, percentages, money (rates of open.er-api.com, cached for a day) and the time in another
 *     city (Windows' own time zones, `ii-shim timezones`).
 * Configuración > Servicios > Buscar turns each one off (search.everything.*).
 */
Singleton {
    id: root

    readonly property bool spanish: (Translation.resolvedLanguageCode ?? "").startsWith("es")
    function enabled(key) {
        return (Config.options?.search?.everything?.[key] ?? true) !== false;
    }
    // Changes when rates or time zones arrive, so the launcher's results are made again.
    property int revision: 0

    // ---- money: the rates (USD base) of open.er-api.com, free and without a key, cached a day ----------------------
    readonly property string ratesPath: FileUtils.trimFileProtocol(`${Directories.cache}/search/rates.json`)
    property var rates: null // { time_last_update_unix, rates: { USD: 1, COP: … } }
    property real ratesTriedAt: 0
    readonly property bool ratesLoading: ratesProc.running
    readonly property var knownCurrencies: root.rates ? Object.keys(root.rates.rates) : []
    readonly property string country: (Qt.locale().name.split("_")[1] ?? "").toUpperCase()
    readonly property string localPeso: Plus.PESO_OF_COUNTRY[root.country] ?? ""
    readonly property string localCurrency: {
        const code = Qt.locale().currencySymbol(Locale.CurrencyIsoCode);
        return /^[A-Z]{3}$/.test(code) ? code : (root.localPeso || "USD");
    }
    FileView {
        id: ratesFile
        path: root.ratesPath
        printErrors: false
        onLoaded: root.readRates()
    }
    function readRates() {
        try {
            const data = JSON.parse(ratesFile.text());
            if (data && data.result === "success" && data.rates && data.rates.USD) {
                root.rates = data;
                root.revision += 1;
            }
        } catch (e) {}
    }
    function ensureRates() {
        const age = root.rates ? Date.now() / 1000 - root.rates.time_last_update_unix : Infinity;
        if (age < 26 * 3600 || ratesProc.running || Date.now() - root.ratesTriedAt < 10 * 60 * 1000) return;
        root.ratesTriedAt = Date.now();
        ratesProc.running = true;
    }
    Process {
        id: ratesProc
        command: ["ii-shim", "fetch", "https://open.er-api.com/v6/latest/USD", "--out", root.ratesPath, "--max", "200000"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) ratesFile.reload();
            root.revision += 1;
        }
    }

    // ---- the time in another place: Windows' time zones, their offset now (asked again every half hour) ----------
    property var zones: []
    property real zonesAt: 0
    function ensureZones() {
        if (Date.now() - root.zonesAt < 30 * 60 * 1000 || zonesProc.running) return;
        zonesProc.running = true;
    }
    Process {
        id: zonesProc
        command: ["ii-shim", "timezones"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.zones = JSON.parse(text);
                    root.zonesAt = Date.now();
                    root.revision += 1;
                } catch (e) {}
            }
        }
    }

    // ---- rows -----------------------------------------------------------------------------------------------------
    Component {
        id: resultComp
        LauncherSearchResult {}
    }
    function row(props) {
        return resultComp.createObject(null, props);
    }
    function score(query, text) { // LauncherSearch ranks the apps with it, next to these rows
        return Plus.matchScore(query, text);
    }
    function number(n) {
        return Number(n).toLocaleString(Qt.locale(), "f", Plus.decimalsFor(n));
    }

    // What the launcher adds for `query`: { conversion: a row or null, rows: [{ score, result }] }.
    function rows(query) {
        const q = (query ?? "").trim();
        const out = { conversion: null, rows: [] };
        if (q.length < 2) return out;
        if (root.enabled("conversions")) out.conversion = root.colorRow(q) ?? root.conversionRow(q);
        if (root.enabled("commands")) out.rows = out.rows.concat(root.colorHistoryRows(q));
        out.rows = out.rows.concat(root.snippetRows(q));
        if (root.enabled("commands")) out.rows = out.rows.concat(root.commandRows(q), root.modeRows(q));
        if (root.enabled("windows")) out.rows = out.rows.concat(root.windowRows(q));
        if (root.enabled("windowsSettings")) out.rows = out.rows.concat(root.windowsSettingsRows(q));
        if (root.enabled("settings")) out.rows = out.rows.concat(root.settingsRows(q));
        return out;
    }

    // ---- conversions ----------------------------------------------------------------------------------------------
    readonly property var unitIcons: ({ length: "straighten", mass: "scale", volume: "water_drop", area: "square_foot",
        speed: "speed", data: "storage", time: "timer", temperature: "thermostat" })
    function copyRow(name, copy, type, icon) {
        return root.row({
            name: name,
            verb: Translation.tr("Copy"),
            type: type,
            iconName: icon,
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => { Quickshell.clipboardText = copy; }
        });
    }
    function conversionRow(q) {
        const parsed = Plus.parse(q, root.knownCurrencies.length ? root.knownCurrencies : ["USD", "EUR", "COP", "MXN"], root.localPeso);
        if (!parsed) return null;
        if (parsed.kind === "units") {
            const from = Plus.UNITS.find(u => u[0] === parsed.from), to = Plus.UNITS.find(u => u[0] === parsed.to);
            const value = Plus.convertUnits(parsed.value, parsed.from, parsed.to);
            if (isNaN(value)) return null;
            return root.copyRow(`${root.number(parsed.value)} ${from[3]} = ${root.number(value)} ${to[3]}`, root.number(value),
                Translation.tr("Conversion"), root.unitIcons[from[1]] ?? "calculate");
        }
        if (parsed.kind === "percent") {
            const value = parsed.op === "of" ? parsed.value * parsed.of / 100
                : parsed.of * (1 + (parsed.op === "+" ? 1 : -1) * parsed.value / 100);
            const text = parsed.op === "of" ? Translation.tr("%1 % of %2").arg(root.number(parsed.value)).arg(root.number(parsed.of))
                : `${root.number(parsed.of)} ${parsed.op} ${root.number(parsed.value)} %`;
            return root.copyRow(`${text} = ${root.number(value)}`, root.number(value), Translation.tr("Percentage"), "percent");
        }
        if (parsed.kind === "money") {
            if (!root.enabled("currency")) return null;
            Qt.callLater(root.ensureRates); // not inside the launcher's binding: it changes what the binding reads
            const to = parsed.to ?? (parsed.from === root.localCurrency ? "USD" : root.localCurrency);
            if (!root.rates) {
                return root.copyRow(root.ratesLoading ? Translation.tr("Getting exchange rates…") : Translation.tr("No exchange rates (no connection?)"),
                    "", Translation.tr("Currency"), "currency_exchange");
            }
            const value = Plus.convertMoney(parsed.amount, parsed.from, to, root.rates.rates);
            if (isNaN(value)) return null;
            const day = new Date(root.rates.time_last_update_unix * 1000);
            return root.copyRow(`${root.number(parsed.amount)} ${parsed.from} = ${root.number(value)} ${to}`, root.number(value),
                Translation.tr("Currency · rate of %1").arg(day.toLocaleDateString(Qt.locale(), "d MMM")), "currency_exchange");
        }
        if (parsed.kind === "time") {
            Qt.callLater(root.ensureZones);
            if (root.zones.length === 0) return null;
            const found = Plus.zoneFor(parsed.place, root.zones);
            if (!found) return null;
            const t = Plus.timeThere(found.zone, Date.now(), -new Date().getTimezoneOffset());
            const clock = `${t.hours < 10 ? "0" : ""}${t.hours}:${t.minutes < 10 ? "0" : ""}${t.minutes}`;
            const day = t.dayShift > 0 ? " " + Translation.tr("(tomorrow)") : t.dayShift < 0 ? " " + Translation.tr("(yesterday)") : "";
            const diff = t.offsetFromHere === 0 ? Translation.tr("same time as here")
                : Translation.tr("%1 h from here").arg((t.offsetFromHere > 0 ? "+" : "−") + root.number(Math.abs(t.offsetFromHere) / 60));
            const place = found.label.replace(/(^|\s)\S/g, s => s.toUpperCase());
            return root.copyRow(`${place}: ${clock}${day}`, clock, `${Translation.tr("Time")} · ${diff} · ${found.zone.name}`, "schedule");
        }
        return null;
    }

    // ---- colors (plan E7): a typed color in its formats, and the color picker's history ("colores") ----------------
    function colorActions(f) {
        return ["hex", "rgb", "hsl"].map(k => root.row({
            name: f[k],
            iconName: "content_copy",
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => { Quickshell.clipboardText = f[k]; }
        }));
    }
    function colorRow(q) {
        const c = Plus.parseColor(q);
        if (!c) return null;
        const f = Plus.colorFormats(c);
        return root.row({ name: `${f.hex} · ${f.rgb} · ${f.hsl}`, verb: Translation.tr("Copy"), type: Translation.tr("Color"),
            iconName: "palette", iconType: LauncherSearchResult.IconType.Material,
            execute: () => { Quickshell.clipboardText = f.hex; }, actions: root.colorActions(f) });
    }
    readonly property string colorsPath: (Quickshell.env("II_DATA_DIR") || ((Quickshell.env("LOCALAPPDATA") ?? "") + "/ii-windows")).replace(/\\/g, "/") + "/colors.txt"
    FileView {
        id: colorsFile
        path: root.colorsPath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
    }
    function colorHistoryRows(q) {
        if (Plus.bestScore(q, ["colores", "historial de colores", "colores recientes", "colors", "color history"]) <= 0) return [];
        const colors = colorsFile.text().split(/\r?\n/).filter(x => /^#[0-9A-Fa-f]{6}$/.test(x)).slice(0, 8);
        return colors.map((hex, i) => {
            const f = Plus.colorFormats(Plus.parseColor(hex));
            return { score: 0.9 - i * 0.001, result: root.row({ name: `${f.hex} · ${f.rgb} · ${f.hsl}`, verb: Translation.tr("Copy"),
                type: Translation.tr("Picked color"), iconName: "colorize", iconType: LauncherSearchResult.IconType.Material,
                execute: () => { Quickshell.clipboardText = f.hex; }, actions: root.colorActions(f) }) };
        });
    }

    // ---- snippets (plan E8): texts you keep (Configuración > Servicios > Fragmentos, or "Guardar como fragmento" on a
    // clipboard entry), pasted into the app in front. "fragmentos" lists them all.
    readonly property var snippets: (Config.options?.search?.snippets ?? []).filter(x => x && x.text)
    function saveSnippet(text) {
        const clean = String(text ?? "").trim();
        if (!clean || root.snippets.some(x => x.text === clean)) return;
        const name = clean.replace(/\s+/g, " ").slice(0, 32);
        Config.options.search.snippets = root.snippets.concat([{ name: name, text: clean }]);
    }
    function pasteText(text) {
        root.later(() => Quickshell.execDetached(["ii-shim", "cliphist", "paste-text", text]));
    }
    function snippetRows(q) {
        if (root.snippets.length === 0) return [];
        const all = Plus.bestScore(q, ["fragmentos", "snippets", "textos guardados"]) > 0;
        const out = [];
        for (const x of root.snippets) {
            const score = all ? 0.85 : Math.max(Plus.matchScore(q, x.name ?? ""), Plus.matchScore(q, x.text) * 0.8);
            if (score <= 0) continue;
            const text = x.text;
            out.push({ score: score * 0.97, result: root.row({
                name: x.name || text,
                verb: Translation.tr("Paste"),
                type: `${Translation.tr("Snippet")} · ${text.replace(/\s+/g, " ").slice(0, 60)}`,
                iconName: "text_snippet",
                iconType: LauncherSearchResult.IconType.Material,
                execute: () => root.pasteText(text),
                actions: [root.row({ name: Translation.tr("Copy"), iconName: "content_copy", iconType: LauncherSearchResult.IconType.Material,
                    execute: () => { Quickshell.clipboardText = text; } })]
            }) });
        }
        return out.sort((a, b) => b.score - a.score).slice(0, 6);
    }

    // ---- commands -------------------------------------------------------------------------------------------------
    function commandRows(q) {
        return Plus.matchCommands(q, root.spanish).slice(0, 4).map(m => {
            let name = m.name;
            if (m.command.id === "dnd") name = Notifications.silent ? Translation.tr("Turn off do not disturb") : Translation.tr("Turn on do not disturb");
            if (m.command.id === "lightMode") name = Performance.light ? Translation.tr("Turn off light mode") : Translation.tr("Turn on light mode");
            return { score: m.score * 0.96, result: root.row({
                name: name,
                verb: Translation.tr("Run"),
                type: Translation.tr("Quick action"),
                iconName: m.command.icon,
                iconType: LauncherSearchResult.IconType.Material,
                execute: () => root.run(m.command.id)
            }) };
        });
    }
    // The modes (plan E2): "modo juego" turns it on (or off when it is on), "salir del modo" ends the active one.
    function modeRows(q) {
        if (!Modes.enabled) return [];
        const out = [];
        for (const m of Modes.list) {
            const name = Modes.nameOf(m);
            const parts = name.split(" / ");
            const names = [`${Translation.tr("Mode")} ${name}`, `modo ${name}`, `mode ${name}`].concat(parts.map(n => `modo ${n}`), parts);
            const score = Plus.bestScore(q, names);
            if (score <= 0) continue;
            const on = Modes.activeId === m.id;
            const id = m.id;
            out.push({ score: score * 0.95, result: root.row({
                name: on ? Translation.tr("Turn off the %1 mode").arg(name) : Translation.tr("Mode %1").arg(name),
                verb: on ? Translation.tr("Turn off") : Translation.tr("Turn on"),
                type: Translation.tr("Modes"),
                iconName: m.icon || "auto_mode",
                iconType: LauncherSearchResult.IconType.Material,
                execute: () => Modes.toggle(id)
            }) });
        }
        if (Modes.active && Plus.bestScore(q, ["salir del modo", "apagar el modo", "quitar el modo", "exit mode", "turn off mode"]) > 0) {
            out.push({ score: 0.95, result: root.row({
                name: Translation.tr("Turn off the %1 mode").arg(Modes.nameOf(Modes.active)),
                verb: Translation.tr("Turn off"),
                type: Translation.tr("Modes"),
                iconName: "toggle_off",
                iconType: LauncherSearchResult.IconType.Material,
                execute: () => Modes.turnOff()
            }) });
        }
        return out;
    }

    // After the launcher has closed (the screenshot must not catch it).
    property var pending: null
    Timer {
        id: laterTimer
        interval: 350
        onTriggered: {
            const f = root.pending;
            root.pending = null;
            if (f) f();
        }
    }
    function later(f) {
        root.pending = f;
        laterTimer.restart();
    }
    function global(name) {
        Hyprland.dispatch(`hl.dsp.global("quickshell:${name}")`);
    }
    function openSettings(page) {
        Quickshell.execDetached({ command: ["qs", "-p", Quickshell.shellPath("settings.qml")], environment: { "II_SETTINGS_PAGE": page } });
    }
    function run(id) {
        switch (id) {
        case "lock": Session.lock(); break;
        case "suspend": Session.suspend(); break;
        case "poweroff": Session.poweroff(); break;
        case "reboot": Session.reboot(); break;
        case "logout": Session.logout(); break;
        case "hibernate": Session.hibernate(); break;
        case "session": root.later(() => { GlobalStates.sessionOpen = true; }); break;
        case "emptyBin": Quickshell.execDetached(["ii-shim", "empty-bin"]); break; // Windows asks first
        case "dark": Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "dark", "--noswitch"]); break;
        case "light": Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "light", "--noswitch"]); break;
        case "dnd": Notifications.silent = !Notifications.silent; break;
        case "dndHour": Notifications.silenceFor("hour"); break;
        case "dndTomorrow": Notifications.silenceFor("tomorrow"); break;
        case "screenshot": root.later(() => root.global("regionScreenshot")); break;
        // F21: Windows' Snipping Tool records the screen (Windows 11); it asks for the area itself.
        case "screenRecord": root.later(() => Qt.openUrlExternally("ms-screenclip:?type=recording")); break;
        case "pinCapture": root.later(() => root.global("regionPin")); break;
        case "colorPicker": root.later(() => Quickshell.execDetached(["ii-shim", "hyprpicker", "-a"])); break;
        case "wallpaper": root.later(() => root.global("wallpaperSelectorToggle")); break;
        case "wallpaperRandom": root.global("wallpaperSelectorRandom"); break;
        case "settings": root.openSettings(""); break;
        case "windowsSettings": Qt.openUrlExternally("ms-settings:"); break;
        case "taskManager": Session.launchTaskManager(); break;
        case "explorer": Quickshell.execDetached(["explorer.exe"]); break;
        case "store": Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("store.qml")]); break;
        case "updates":
            Quickshell.execDetached(["ii-shim", "host", "update-check"]);
            root.openSettings("updatesconfig");
            break;
        case "restartShell": Quickshell.execDetached(["ii-shim", "host", "restart-shell"]); break;
        case "clipboard": root.later(() => root.global("overviewClipboardToggle")); break;
        case "emoji": root.later(() => root.global("overviewEmojiToggle")); break;
        case "showDesktop": root.later(() => Quickshell.execDetached(["ii-shim", "host", "show-desktop"])); break;
        case "lightMode": Performance.setLight(!Performance.light); break;
        case "nightLight": Hyprsunset.toggleTemperature(); break;
        case "shortcuts": root.openSettings("shortcutsconfig"); break;
        case "report": Quickshell.execDetached(["ii-shim", "host", "report"]); break;
        }
    }

    // ---- open windows ---------------------------------------------------------------------------------------------
    function windowRows(q) {
        const out = [];
        for (const t of ToplevelManager.toplevels.values) {
            const title = t.title ?? "";
            if (!title) continue;
            const entry = t.appId ? DesktopEntries.heuristicLookup(t.appId) : null;
            const app = entry?.name ?? t.appId ?? "";
            const score = Math.max(Plus.matchScore(q, title), Plus.matchScore(q, app) * 0.98);
            if (score <= 0) continue;
            const toplevel = t;
            out.push({ score: score * 0.97, result: root.row({
                name: title,
                verb: Translation.tr("Switch to"),
                type: app ? `${Translation.tr("Open window")} · ${app}` : Translation.tr("Open window"),
                iconName: AppSearch.iconForWindow(t.appId ?? "", t.executable ?? ""),
                iconType: LauncherSearchResult.IconType.System,
                execute: () => toplevel.activate(),
                actions: [root.row({
                    name: Translation.tr("Close"),
                    iconName: "close",
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => toplevel.close()
                })]
            }) });
        }
        out.sort((a, b) => b.score - a.score);
        return out.slice(0, 5);
    }

    // ---- Windows' settings ----------------------------------------------------------------------------------------
    function windowsSettingsRows(q) {
        return Plus.matchWindowsSettings(q, root.spanish).slice(0, 3).map(m => ({ score: m.score * 0.9, result: root.row({
            name: m.name,
            verb: Translation.tr("Open"),
            type: Translation.tr("Windows settings"),
            iconName: "settings_applications",
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => Qt.openUrlExternally("ms-settings:" + m.page)
        }) }));
    }

    // ---- ii's settings: Configuración's own index and scoring -----------------------------------------------------
    readonly property var cache: ({ haystacks: [], language: "" })
    function widgetTitle(key) {
        const widget = WidgetRegistry.widgets.find(w => w.key === key);
        return widget ? Translation.tr(widget.title).replace(/^Widget:\s*/, "") : key;
    }
    function pageName(entry) {
        const name = SettingsIndex.pageNames[entry.p];
        return name ? Translation.tr(name) : "";
    }
    function haystack(i) {
        if (root.cache.haystacks.length !== SettingsIndex.entries.length || root.cache.language !== Translation.resolvedLanguageCode) {
            root.cache.language = Translation.resolvedLanguageCode;
            root.cache.haystacks = SettingsIndex.entries.map(e => " " + Plus.norm([Translation.tr(e.l), Translation.tr(e.s), Translation.tr(e.ss),
                e.l, e.s, e.ss, root.pageName(e), e.sub ? root.widgetTitle(e.sub) : "", e.k.replace(/\./g, " "), e.w].join(" ")));
        }
        return root.cache.haystacks[i];
    }
    function trail(entry) { // Barra › Posición
        const parts = [root.pageName(entry)];
        if (entry.sub) parts.push(root.widgetTitle(entry.sub));
        for (const t of [entry.s, entry.ss])
            if (t && t !== entry.l && !(entry.sub && t.startsWith("Widget:"))) parts.push(Translation.tr(t));
        return parts.filter(p => p).join(" › ");
    }
    function settingsRows(q) {
        const words = Plus.settingsWords(q);
        if (words.length === 0 || q.length < 3) return [];
        const found = [];
        for (let i = 0; i < SettingsIndex.entries.length; ++i) {
            const hay = root.haystack(i);
            if (!words.every(w => hay.includes(w))) continue;
            const e = SettingsIndex.entries[i];
            const label = Translation.tr(e.l);
            const raw = Plus.scoreSetting(words, hay, Plus.norm(label), e.l === e.s || e.l === e.ss);
            found.push({ entry: e, label: label, raw: raw, index: i });
        }
        found.sort((a, b) => b.raw - a.raw || a.index - b.index);
        return found.slice(0, 3).map(f => {
            const e = f.entry;
            const target = JSON.stringify({ p: e.p, sub: e.sub, s: e.s, ss: e.ss, l: e.l });
            return { score: Math.max(Plus.matchScore(q, f.label), 0.55) * 0.88, result: root.row({
                name: f.label,
                verb: Translation.tr("Open"),
                type: `${Translation.tr("ii setting")} · ${root.trail(e)}`,
                iconName: e.i || "settings",
                iconType: LauncherSearchResult.IconType.Material,
                execute: () => root.openSettings("locate:" + target)
            }) };
        });
    }
}
