pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

// ii-windows: the app store's backend is winget (Windows' own package manager): search the winget catalogue, list
// what is installed and what has an update, and install / update / uninstall one app at a time. Nothing here runs
// until the store window asks.
Singleton {
    id: root

    property bool checked: false
    property bool available: false
    property var installed: ({})      // lower-case id -> { name, id, version, available }
    property var installedList: []
    property var upgrades: []         // [{ name, id, version, available }]
    property var results: []          // the last search: [{ name, id, version, source }]
    property bool searching: false
    property bool listing: false
    // `winget list` has answered at least once: before that nobody knows what is installed, and the store shows a
    // placeholder instead of an "Install" button on apps that are already there.
    property bool listedOnce: false
    property string lastQuery: ""
    property string searchError: ""
    property var progress: ({})       // lower-case id -> { op, state: queued|running|done|error, percent, message }
    property var queue: []            // [{ op, id, name }]
    property bool working: false
    property var current: null

    // --- is it installed? ------------------------------------------------------------------------------------------------
    // By id when winget knows the app ("Git.Git"). Apps installed by hand show up in `winget list` under another id
    // ("ARP\Machine\X64\{GUID}", a different Python version...) and in the Start menu under their name: so by name too,
    // with the version, the architecture and the maker's name taken out of both sides.
    readonly property var nameNoise: ({ "x64": 1, "x86": 1, "bit": 1, "version": 1, "user": 1, "machine": 1, "preview": 1, "setup": 1, "installer": 1, "release": 1, "stable": 1, "beta": 1, "edition": 1, "community": 1, "lts": 1 })
    readonly property var nameVendors: ({ "microsoft": 1, "google": 1, "jetbrains": 1, "mozilla": 1, "the": 1, "apache": 1, "gnu": 1 })
    function nameKey(s) {
        const tokens = String(s ?? "").toLowerCase()
            .replace(/\([^)]*\)/g, " ")          // (User) (x64) (LTS) (64-bit)
            .replace(/[^a-z0-9]+/g, " ").trim().split(" ")
            .filter(t => t !== "" && !/^\d/.test(t) && !nameNoise[t]);   // 3.12, 25.01, x64 ...
        if (tokens.length > 1 && nameVendors[tokens[0]]) tokens.shift();
        return tokens.join(" ");
    }
    // name key -> the row of `winget list` (or a Start menu entry) that has it
    readonly property var installedKeys: {
        const map = {};
        for (const r of installedList) {
            const k = root.nameKey(r.name);
            if (k && !(k in map)) map[k] = r;
        }
        for (const e of AppSearch.list) {
            const k = root.nameKey(e.name);
            if (k && !(k in map)) map[k] = { name: e.name, id: "", version: "", startMenu: true };
        }
        return map;
    }
    // The installed row of an app: by id, else by its name (or one of its other names, `aka`).
    function installedRow(id, name, aka) {
        const byId = installed[String(id).toLowerCase()];
        if (byId) return byId;
        for (const n of [name].concat(aka ?? [])) {
            const k = root.nameKey(n);
            if (k && installedKeys[k]) return installedKeys[k];
        }
        return null;
    }
    function isInstalled(id, name, aka) { return installedRow(id, name, aka) !== null; }
    function upgradeFor(id) { return upgrades.find(u => u.id.toLowerCase() === String(id).toLowerCase()) ?? null; }
    function stateOf(id) { return progress[String(id).toLowerCase()] ?? null; }
    function setState(id, value) {
        const next = Object.assign({}, progress);
        if (value === null) delete next[String(id).toLowerCase()];
        else next[String(id).toLowerCase()] = value;
        progress = next;
    }

    // --- parsing winget's tables ---------------------------------------------------------------------------
    // "Name   Id   Version  Available  Source" then a line of dashes, then one row per package. The columns
    // are fixed-width, so each cell is cut at the position where its header starts.
    // The header is the line just above the line of dashes, in whatever language winget speaks: in English the
    // columns are known by name; otherwise by their order (name, id, version, then available / source).
    function parseTable(text, kind) {
        // A lone \r is the spinner winget redraws before the table: it starts a line of its own.
        const lines = text.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n");
        const dashes = lines.findIndex(l => /^-{10,}\s*$/.test(l));
        if (dashes < 1) return [];
        let h = dashes - 1;
        while (h > 0 && lines[h].trim() === "") h--;
        const header = lines[h].replace(/^[\s\-\\|/]+(?=\S)/, m => " ".repeat(m.length)); // spinner left on the line
        const starts = [];
        for (let i = 0; i < header.length; i++)
            if (header[i] !== " " && (i === 0 || header[i - 1] === " ")) starts.push(i);
        let names;
        if (/^\s*Name\s+Id\s+Version/.test(header)) {
            names = ["Name", "Id", "Version", "Available", "Match", "Source"].filter(n => header.indexOf(n) >= 0);
            starts.length = 0;
            for (const n of names) starts.push(header.indexOf(n));
        } else {
            names = ["Name", "Id", "Version"];
            const rest = starts.length - 3;
            if (kind === "upgrade" || kind === "list") names = names.concat(rest >= 2 ? ["Available", "Source"] : rest === 1 ? ["Source"] : []);
            else names = names.concat(rest >= 2 ? ["Match", "Source"] : rest === 1 ? ["Source"] : []);
            starts.length = names.length;
        }
        const rows = [];
        for (let i = dashes + 1; i < lines.length; i++) {
            const line = lines[i];
            if (!line.trim()) continue;
            if (/^(<additional|\d+ (package|upgrade|paquete|actualizaci)|The following|No installed|No applicable|No se encontr|Los siguientes)/i.test(line)) break;
            const row = {};
            for (let c = 0; c < names.length; c++)
                row[names[c].toLowerCase()] = line.substring(starts[c], c + 1 < names.length ? starts[c + 1] : undefined).trim();
            if (row.id) rows.push(row);
        }
        return rows;
    }

    // --- is winget there? ----------------------------------------------------------------------------------------
    function check() {
        if (checked || checkProc.running) return;
        checkProc.running = true;
    }
    Process {
        id: checkProc
        command: ["winget", "--version"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.available = /v?\d+\.\d+/.test(text);
                root.checked = true;
                if (root.available) root.refreshInstalled();
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.available = false;
                root.checked = true;
            }
        }
    }

    // --- installed and upgrades ----------------------------------------------------------------------------------------
    function refreshInstalled() {
        if (!available || listProc.running) return;
        listing = true;
        listProc.running = true;
    }
    Process {
        id: listProc
        command: ["winget", "list", "--accept-source-agreements", "--disable-interactivity"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = root.parseTable(text, "list");
                const map = {};
                for (const r of rows) map[r.id.toLowerCase()] = r;
                root.installed = map;
                root.installedList = rows;
                root.listedOnce = true;
                upgradeProc.running = true;
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && !upgradeProc.running) {
                root.listing = false;
                root.listedOnce = true;
            }
        }
    }
    Process {
        id: upgradeProc
        command: ["winget", "upgrade", "--accept-source-agreements", "--disable-interactivity"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.upgrades = root.parseTable(text, "upgrade").filter(r => r.available);
                root.listing = false;
            }
        }
        onExited: (code, status) => root.listing = false
    }

    // --- search --------------------------------------------------------------------------------------------------------------
    function search(query) {
        const q = String(query).trim();
        if (!available) return;
        if (q.length < 2) {
            results = [];
            searching = false;
            return;
        }
        if (q === lastQuery && (searching || results.length > 0)) return;
        lastQuery = q;
        searching = true;
        searchError = "";
        // One search at a time: a newer query waits for the running one to end (its answer is then dropped).
        if (searchProc.running) {
            searchProc.pending = true;
            return;
        }
        searchProc.query = q;
        searchProc.command = ["winget", "search", q, "--source", "winget", "--count", "40", "--accept-source-agreements", "--disable-interactivity"];
        searchProc.running = true;
    }
    Process {
        id: searchProc
        property string query: ""
        property bool pending: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (searchProc.query !== root.lastQuery) return; // typed on meanwhile
                root.results = root.parseTable(text, "search");
                root.searching = false;
                if (root.results.length === 0) root.searchError = text.trim().split("\n").pop();
            }
        }
        onExited: (code, status) => {
            if (searchProc.pending) {
                searchProc.pending = false;
                const q = root.lastQuery;
                root.lastQuery = "";
                Qt.callLater(() => root.search(q));
                return;
            }
            if (code !== 0 && searchProc.query === root.lastQuery) root.searching = false;
        }
    }

    // --- install / update / uninstall, one at a time ----------------------------------------------------------------------
    // `target`: the id winget must act on, when the app is installed under another id than the catalogue's.
    function enqueue(op, id, name, target) {
        if (!available) return;
        const st = stateOf(id);
        if (st && (st.state === "queued" || st.state === "running")) return;
        queue = [...queue, { op: op, id: id, name: name, target: target || id }];
        setState(id, { op: op, state: "queued", percent: -1, message: "" });
        runNext();
    }
    function install(id, name) { enqueue("install", id, name); }
    function upgrade(id, name) { enqueue("upgrade", id, name); }
    function uninstall(id, name, target) { enqueue("uninstall", id, name, target); }
    function upgradeAll() {
        for (const u of upgrades) enqueue("upgrade", u.id, u.name);
    }
    function dismiss(id) { setState(id, null); }

    function commandFor(job) {
        if (job.op === "uninstall")
            return ["winget", "uninstall", "--id", job.target, "--exact", "--silent", "--disable-interactivity"];
        return ["winget", job.op, "--id", job.id, "--exact", "--silent", "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity"]
            .concat(job.op === "install" ? ["--source", "winget"] : []);
    }
    function runNext() {
        if (working || queue.length === 0) return;
        const job = queue[0];
        queue = queue.slice(1);
        current = job;
        working = true;
        setState(job.id, { op: job.op, state: "running", percent: -1, message: "" });
        opProc.command = commandFor(job);
        opProc.running = true;
    }
    Process {
        id: opProc
        stdout: SplitParser {
            splitMarker: "\r"
            onRead: data => {
                const m = /(\d{1,3})\s*%/.exec(data);
                if (m && root.current) {
                    const st = root.stateOf(root.current.id);
                    if (st) root.setState(root.current.id, Object.assign({}, st, { percent: Math.min(100, parseInt(m[1])) }));
                }
            }
        }
        onExited: (code, status) => {
            const job = root.current;
            if (job) {
                // 0 = done. The "already installed" / "no newer version" codes are fine too.
                const u = code >>> 0;
                const ok = u === 0 || u === 0x8A150061 || u === 0x8A15002B;
                root.setState(job.id, {
                    op: job.op,
                    state: ok ? "done" : "error",
                    percent: 100,
                    message: ok ? "" : ("winget " + (code >>> 0).toString(16))
                });
                if (ok) refreshAfterOp.restart();
            }
            root.current = null;
            root.working = false;
            root.runNext();
        }
    }
    Timer {
        id: refreshAfterOp
        interval: 800
        onTriggered: root.refreshInstalled()
    }
}
