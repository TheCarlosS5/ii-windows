pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * ii-windows (plan 2026-10-31, F2/F14): Windows' state that ii-host looks at every hour on its own thread
 * (host/src/syshealth.cpp): an update waiting for a restart, and the system drive's free space.
 * <data>\system-status.json; the session screen offers "Reboot and update" while Windows waits for a restart.
 */
Singleton {
    id: root
    readonly property string dataDir: Quickshell.env("II_DATA_DIR") || (Quickshell.env("LOCALAPPDATA") + "\\ii-windows")
    property var info: ({})
    readonly property bool rebootRequired: root.info.rebootRequired === true
    readonly property bool lowDisk: root.info.lowDisk === true
    readonly property real freeBytes: root.info.freeBytes ?? 0
    readonly property string drive: root.info.drive ?? "C:"

    // Ask ii-host to look again now (the session screen does when it opens).
    function refresh() {
        Quickshell.execDetached(["ii-shim", "host", "system-check"]);
        reloadSoon.restart();
    }

    FileView {
        id: statusFile
        path: root.dataDir + "\\system-status.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.info = JSON.parse(statusFile.text());
            } catch (e) {}
        }
    }
    Timer { // the file is rewritten hourly; in case a change notice is missed
        interval: 10 * 60 * 1000
        running: true
        repeat: true
        onTriggered: statusFile.reload()
    }
    Timer {
        id: reloadSoon
        interval: 3000
        onTriggered: statusFile.reload()
    }
}
