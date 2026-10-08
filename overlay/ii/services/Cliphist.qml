pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * ii-windows: ii's clipboard history service on top of Windows' own clipboard history
 * (Settings > System > Clipboard), through ii-shim's `cliphist` (list, copy, paste, delete,
 * wipe, decode-to). Same API as ii's: entries are "<id>\t<preview>", images
 * "[[ binary data ... WxH ]]". With Windows' history off the list is empty.
 */
Singleton {
    id: root
    property string cliphistBinary: "cliphist"
    property real pasteDelay: 0.05
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property list<string> entries: []
    readonly property var preparedEntries: entries.map(a => ({
        name: Fuzzy.prepare(`${a.replace(/^\s*\S+\s+/, "")}`),
        entry: a
    }))
    function fuzzyQuery(search: string): var {
        if (search.trim() === "") {
            return entries;
        }
        if (root.sloppySearch) {
            const results = entries.slice(0, 100).map(str => ({
                entry: str,
                score: Levendist.computeTextMatchScore(str.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }

        return Fuzzy.go(search, preparedEntries, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
    }

    function idOf(entry) {
        return `${entry}`.split("\t")[0].trim();
    }

    function entryIsImage(entry) {
        return !!(/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(entry))
    }

    function refresh() {
        readProc.buffer = []
        readProc.running = true
    }

    function copy(entry) {
        Quickshell.execDetached([root.cliphistBinary, "copy", root.idOf(entry)]);
    }

    function paste(entry) {
        Quickshell.execDetached([root.cliphistBinary, "paste", root.idOf(entry)]);
    }

    function superpaste(count, isImage = false) {
        const targetEntries = entries.filter(entry => !isImage || entryIsImage(entry)).slice(0, count);
        // Oldest first, so they land in the order they were copied.
        const ids = [...targetEntries].reverse().map(entry => root.idOf(entry));
        Quickshell.execDetached([root.cliphistBinary, "superpaste", `${Math.round(root.pasteDelay * 1000)}`, ...ids]);
    }

    Process {
        id: deleteProc
        onExited: (exitCode, exitStatus) => root.refresh()
    }

    function deleteEntry(entry) {
        deleteProc.exec([root.cliphistBinary, "delete-id", root.idOf(entry)]);
    }

    Process {
        id: wipeProc
        command: [root.cliphistBinary, "wipe"]
        onExited: (exitCode, exitStatus) => root.refresh()
    }

    function wipe() {
        wipeProc.running = true;
    }

    // Windows keeps the history; read it again when ii shows it or the clipboard changes.
    Connections {
        target: Quickshell
        function onClipboardTextChanged() {
            delayedUpdateTimer.restart()
        }
    }
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen) root.refresh();
        }
    }

    Timer {
        id: delayedUpdateTimer
        interval: Math.max(150, Config.options.hacks.arbitraryRaceConditionDelay)
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: readProc
        property list<string> buffer: []

        command: [root.cliphistBinary, "list"]

        stdout: SplitParser {
            onRead: (line) => {
                readProc.buffer.push(line)
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.entries = readProc.buffer
            } else {
                console.error("[Cliphist] Failed to refresh with code", exitCode, "and status", exitStatus)
            }
        }
    }

    IpcHandler {
        target: "cliphistService"

        function update(): void {
            root.refresh()
        }
    }
}
