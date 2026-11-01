pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * ii-windows (plan 2026-10-31, E7): captures pinned on screen. A region taken with the middle click (or the "pin"
 * shortcut / search action) stays above every window, where it was taken, until closed: drag it to move it, the wheel
 * to resize it, right click or × to close it. It is also copied, like a normal capture. The images are temporary files.
 */
Singleton {
    id: root
    property var pins: [] // [{ id, path, screen, x, y, width, height }]
    property var queue: []
    readonly property string dir: `${FileUtils.trimFileProtocol(StandardPaths.writableLocation(StandardPaths.TempLocation))}/quickshell/pins`

    // source: the full screenshot; x/y/width/height: the region in the screen's pixels; at: where to show it (logical).
    function pinRegion(source, x, y, width, height, screen, at) {
        const id = Date.now();
        root.queue = root.queue.concat([{ id: id, source: source, region: [x, y, width, height].map(v => String(Math.round(v))),
            path: `${root.dir}/pin-${id}.png`, screen: screen, x: at.x, y: at.y, width: at.width, height: at.height }]);
        root.next();
    }
    function close(id) {
        const pin = root.pins.find(p => p.id === id);
        root.pins = root.pins.filter(p => p.id !== id);
        if (pin) Quickshell.execDetached(["ii-shim", "rm", "-f", pin.path]);
    }
    function next() {
        if (!root.cleaned || cropProc.running || root.queue.length === 0) return;
        cropProc.job = root.queue[0];
        root.queue = root.queue.slice(1);
        cropProc.command = ["ii-shim", "crop", cropProc.job.source].concat(cropProc.job.region, ["pin", cropProc.job.path]);
        cropProc.running = true;
    }
    // Pins of an earlier run of ii (closed without closing them): gone before the first new one is written.
    property bool cleaned: false
    Process {
        running: true
        command: ["ii-shim", "rm", "-rf", root.dir]
        onExited: {
            root.cleaned = true;
            root.next();
        }
    }
    Process {
        id: cropProc
        property var job: null
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && cropProc.job) root.pins = root.pins.concat([cropProc.job]);
            cropProc.job = null;
            root.next();
        }
    }

    Variants {
        model: root.pins
        delegate: PanelWindow {
            id: pinWindow
            required property var modelData
            property real zoom: 1
            screen: modelData.screen
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:pin"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors { top: true; left: true }
            margins { top: Math.round(modelData.y); left: Math.round(modelData.x) }
            implicitWidth: Math.max(48, Math.round(modelData.width * zoom)) + 8
            implicitHeight: Math.max(48, Math.round(modelData.height * zoom)) + 8

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant ?? Appearance.colors.colLayer0Border
                Image {
                    anchors.fill: parent
                    anchors.margins: 4
                    source: "file:///" + pinWindow.modelData.path.replace(/^\/+/, "")
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    cache: false
                }
            }
            MouseArea {
                id: drag
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property point pressAt: Qt.point(0, 0)
                onPressed: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        root.close(pinWindow.modelData.id);
                        return;
                    }
                    pressAt = Qt.point(mouse.x, mouse.y);
                }
                onPositionChanged: mouse => {
                    if (!pressed) return;
                    // The window moves under the pointer: the offset from the press point is the step.
                    pinWindow.margins.left += mouse.x - pressAt.x;
                    pinWindow.margins.top += mouse.y - pressAt.y;
                }
                onWheel: wheel => {
                    pinWindow.zoom = Math.max(0.25, Math.min(3, pinWindow.zoom * (wheel.angleDelta.y > 0 ? 1.1 : 1 / 1.1)));
                }
            }
            Rectangle {
                visible: drag.containsMouse
                anchors { top: parent.top; right: parent.right; margins: 8 }
                width: 26
                height: 26
                radius: 13
                color: Appearance.colors.colLayer2
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer2
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close(pinWindow.modelData.id)
                }
            }
        }
    }
}
