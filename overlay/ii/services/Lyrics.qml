pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

// ii-windows: synced lyrics for the media panel, from LRCLIB (lrclib.net, free, no account). Off until the user turns
// it on with the lyrics button: only then are the artist, title and length of what plays sent there. One lookup per
// track (kept in memory); the line shown follows the player's position while the panel is open.
Singleton {
    id: root

    readonly property bool enabled: Persistent.ready && (Persistent.states.media?.lyrics ?? false)
    function toggle() {
        Persistent.states.media.lyrics = !root.enabled;
    }

    property string trackKey: ""
    property var lines: [] // [{ t: seconds, text }]
    property string status: "" // "", "loading", "none"
    property var cache: ({})

    // The line for a position in seconds ("" before the first one or without synced lyrics).
    function lineAt(position) {
        let text = "";
        for (const line of root.lines) {
            if (line.t > position + 0.3)
                break;
            text = line.text;
        }
        return text;
    }

    function parse(lrc) {
        const out = [];
        for (const row of (lrc ?? "").split("\n")) {
            // (no String.matchAll in Qt's JavaScript engine)
            const stamp = /\[(\d+):(\d+(?:\.\d+)?)\]/g;
            const times = [];
            let m;
            while ((m = stamp.exec(row)) !== null)
                times.push(parseInt(m[1]) * 60 + parseFloat(m[2]));
            if (times.length === 0)
                continue;
            const text = row.replace(/\[[^\]]*\]/g, "").trim();
            for (const t of times)
                out.push({ t: t, text: text || "♪" });
        }
        out.sort((a, b) => a.t - b.t);
        return out;
    }

    // Asks for the lyrics of a track (does nothing when off, or for the track already shown).
    function request(artist, title, lengthSeconds) {
        if (!root.enabled || !title)
            return;
        const key = `${artist}\n${title}`;
        if (key === root.trackKey)
            return;
        root.trackKey = key;
        if (root.cache[key] !== undefined) {
            root.lines = root.cache[key];
            root.status = root.lines.length > 0 ? "" : "none";
            return;
        }
        root.lines = [];
        root.status = "loading";
        const q = `artist_name=${encodeURIComponent(artist ?? "")}&track_name=${encodeURIComponent(title)}`;
        getProc.key = key;
        getProc.searchUrl = `https://lrclib.net/api/search?${q}`;
        getProc.command = ["ii-shim", "fetch", `https://lrclib.net/api/get?${q}&duration=${Math.round(lengthSeconds || 0)}`,
            "--agent", "ii-windows (https://github.com/TheCarlosS5/ii-windows)"];
        getProc.running = true;
    }

    function finish(key, found) {
        // The exact lookup and the search can both answer: an empty answer never replaces lyrics already found.
        if (found.length === 0 && (root.cache[key]?.length ?? 0) > 0)
            return;
        root.cache[key] = found;
        if (key !== root.trackKey)
            return;
        root.lines = found;
        root.status = found.length > 0 ? "" : "none";
    }

    Process {
        id: getProc
        property string key
        property string searchUrl
        property bool ok: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const found = root.parse(JSON.parse(text).syncedLyrics);
                    getProc.ok = found.length > 0;
                    if (getProc.ok)
                        root.finish(getProc.key, found);
                } catch (e) {
                    getProc.ok = false;
                }
            }
        }
        onRunningChanged: if (running) ok = false
        onExited: {
            if (ok)
                return;
            // No exact match (length differs a little, another version...): the first search result with sync.
            searchProc.key = key;
            searchProc.command = ["ii-shim", "fetch", searchUrl, "--agent", "ii-windows (https://github.com/TheCarlosS5/ii-windows)"];
            searchProc.running = true;
        }
    }
    Process {
        id: searchProc
        property string key
        stdout: StdioCollector {
            onStreamFinished: {
                let found = [];
                try {
                    const hit = JSON.parse(text).find(r => r.syncedLyrics);
                    found = root.parse(hit?.syncedLyrics);
                } catch (e) {}
                root.finish(searchProc.key, found);
            }
        }
    }
}
