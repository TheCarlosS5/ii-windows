// Test config (plan 2026-10-31, D1): follows the window list the way ii's dock and overview do, and logs what happens
// to the probe window of tools/sandbox/tests/test-toplevels.ps1 (a form whose title starts "ii-toplevels-probe").
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: root
    property int titleChanges: 0
    property int geometryChanges: 0

    Instantiator {
        model: ToplevelManager.toplevels
        delegate: QtObject {
            id: entry
            required property var modelData
            property string title: modelData?.title ?? ""
            readonly property bool probe: entry.title.startsWith("ii-toplevels-probe")
            property bool minimized: modelData?.minimized ?? false
            property bool activated: modelData?.activated ?? false
            property string appId: modelData?.appId ?? ""
            property var screens: modelData?.screens ?? []
            onTitleChanged: {
                if (!entry.probe) return;
                root.titleChanges++;
                if (entry.title.endsWith("final")) console.info(`probe title=${entry.title}`);
            }
            onMinimizedChanged: if (entry.probe) console.info(`probe minimized=${entry.minimized}`)
            onScreensChanged: if (entry.probe) root.geometryChanges++
            Component.onCompleted: if (entry.probe) console.info(`probe added app=${entry.appId}`)
            Component.onDestruction: if (entry.probe) console.info("probe removed")
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: console.info(`toplevels count=${ToplevelManager.toplevels.values.length} titleChanges=${root.titleChanges} titles=${ToplevelManager.toplevels.values.map(t => t.title).join(" | ")}`)
    }
}
