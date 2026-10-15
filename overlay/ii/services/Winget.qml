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
    property string searchError: ""
    property var progress: ({})       // lower-case id -> { op, state: queued|running|done|error, percent, message }
    property var queue: []            // [{ op, id, name }]
    property bool working: false
    property var current: null

    function isInstalled(id) { return installed[String(id).toLowerCase()] !== undefined; }
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
    function parseTable(text) {
        const lines = text.replace(/\r/g, "").split("\n");
        const h = lines.findIndex(l => /^Name\s+Id\s+Version/.test(l));
        if (h < 0 || h + 2 > lines.length) return [];
        const header = lines[h];
        const names = ["Name", "Id", "Version", "Available", "Match", "Source"].filter(n => header.indexOf(n) >= 0);
        const starts = names.map(n => header.indexOf(n));
        const rows = [];
        for (let i = h + 2; i < lines.length; i++) {
            const line = lines[i];
            if (!line.trim()) continue;
            if (/^(<additional|\d+ (package|upgrade|paquete)|The following|No installed|No applicable|No se encontr)/i.test(line)) break;
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
                const rows = root.parseTable(text);
                const map = {};
                for (const r of rows) map[r.id.toLowerCase()] = r;
                root.installed = map;
                root.installedList = rows;
                upgradeProc.running = true;
            }
        }
        onExited: (code, status) => { if (code !== 0 && !upgradeProc.running) root.listing = false; }
    }
    Process {
        id: upgradeProc
        command: ["winget", "upgrade", "--accept-source-agreements", "--disable-interactivity"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.upgrades = root.parseTable(text).filter(r => r.available);
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
        searchProc.command = ["winget", "search", q, "--source", "winget", "--count", "40", "--accept-source-agreements", "--disable-interactivity"];
        searching = true;
        searchError = "";
        searchProc.running = false;
        searchProc.running = true;
    }
    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.results = root.parseTable(text);
                root.searching = false;
                if (root.results.length === 0) root.searchError = text.trim().split("\n").pop();
            }
        }
        onExited: (code, status) => { if (code !== 0) root.searching = false; }
    }

    // --- install / update / uninstall, one at a time ----------------------------------------------------------------------
    function enqueue(op, id, name) {
        if (!available) return;
        const st = stateOf(id);
        if (st && (st.state === "queued" || st.state === "running")) return;
        queue = [...queue, { op: op, id: id, name: name }];
        setState(id, { op: op, state: "queued", percent: -1, message: "" });
        runNext();
    }
    function install(id, name) { enqueue("install", id, name); }
    function upgrade(id, name) { enqueue("upgrade", id, name); }
    function uninstall(id, name) { enqueue("uninstall", id, name); }
    function upgradeAll() {
        for (const u of upgrades) enqueue("upgrade", u.id, u.name);
    }
    function dismiss(id) { setState(id, null); }

    function commandFor(job) {
        if (job.op === "uninstall")
            return ["winget", "uninstall", "--id", job.id, "--exact", "--silent", "--disable-interactivity"];
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
