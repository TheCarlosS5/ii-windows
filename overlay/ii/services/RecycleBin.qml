pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * ii-windows (plan 2026-10-31, E6): the Recycle Bin for the dock's tile. What is in it (`ii-shim recycle-bin`, every
 * 30 s while the dock shows it, and right after emptying), open it in Explorer, empty it (Windows asks first).
 */
Singleton {
    id: root
    property int items: 0
    property real bytes: 0
    readonly property bool full: root.items > 0
    property bool watched: false // the dock sets it while the tile exists

    function open() {
        Quickshell.execDetached(["explorer.exe", "shell:RecycleBinFolder"]);
    }
    function empty() {
        if (!root.full) return;
        emptyProc.running = true;
    }
    function refresh() {
        if (!queryProc.running) queryProc.running = true;
    }
    function sizeText() {
        const mb = root.bytes / 1048576;
        return mb >= 1024 ? `${(mb / 1024).toFixed(1)} GB` : `${Math.max(1, Math.round(mb))} MB`;
    }

    Timer {
        interval: 30000
        running: root.watched
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
    Process {
        id: queryProc
        command: ["ii-shim", "recycle-bin"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.items = data.items ?? 0;
                    root.bytes = data.bytes ?? 0;
                } catch (e) {}
            }
        }
    }
    Process {
        id: emptyProc
        command: ["ii-shim", "empty-bin"]
        onExited: root.refresh()
    }
}
