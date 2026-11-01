pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * ii-windows (plan 2026-10-31, F3): how many installed apps have an update in winget, for the badge on the store's
 * tile in the dock (the store itself lists them and has "Actualizar todo"). winget is slow and busy while it looks,
 * so: ten minutes after start, then every 12 hours, never while a full-screen app (a game) is in front, and only
 * while the dock shows the store. After the store was opened, once more a while later (it may have updated some).
 */
Singleton {
    id: root
    property int count: -1 // -1: not known (no winget, or not looked yet)
    readonly property bool wanted: Config.ready && (Config.options.dock.showStore ?? true)

    function check() {
        if (!root.wanted || listProc.running) return;
        if (HyprlandData.activeWorkspace?.hasfullscreen) { // a game: later
            retry.restart();
            return;
        }
        listProc.running = true;
    }
    function storeOpened() { afterStore.restart(); }

    Process {
        id: listProc
        command: ["winget", "upgrade", "--accept-source-agreements", "--disable-interactivity"]
        stdout: StdioCollector {
            onStreamFinished: {
                // The same table reading as the store (services/Winget.qml).
                root.count = Winget.parseTable(text, "upgrade").filter(r => r.available).length;
            }
        }
        onExited: (code, status) => {
            // winget missing: no badge. "No applicable upgrade" exits non-zero with nothing to read: 0.
            if (code !== 0 && root.count < 0) root.count = -1;
        }
    }
    Timer { // the first look
        interval: 10 * 60 * 1000
        running: root.wanted
        onTriggered: root.check()
    }
    Timer {
        interval: 12 * 60 * 60 * 1000
        running: root.wanted
        repeat: true
        onTriggered: root.check()
    }
    Timer {
        id: retry
        interval: 30 * 60 * 1000
        onTriggered: root.check()
    }
    Timer {
        id: afterStore
        interval: 15 * 60 * 1000
        onTriggered: root.check()
    }
}
