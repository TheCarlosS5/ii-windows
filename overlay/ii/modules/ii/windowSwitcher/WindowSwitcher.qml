pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows (plan 2.3): ii's Alt+Tab. Hold Alt: Tab (or Right) moves on, Shift+Tab (or Left) back, letting go of Alt
// picks the window, Esc gives up; a click on a card picks it too. The keys come from ii-host's keyboard router
// (windowSwitcher* shortcuts), which leaves Alt+Tab to Windows over a game or while the shell does not answer.
// Like Windows': the windows of the current desktop, most recently used first, live thumbnails (DWM) and the app's
// icon for a minimized one (DWM shows nothing for it). The dock shows meanwhile (Dock.qml), above everything.
Scope {
    id: root

    // Most recently used first: the order the toplevels came in at start-up, then each activation moves its window
    // to the front.
    property var recent: []
    function touch(toplevel) {
        if (!toplevel)
            return;
        const list = root.recent.filter(t => t !== toplevel && ToplevelManager.toplevels.values.includes(t));
        list.unshift(toplevel);
        root.recent = list;
    }
    Component.onCompleted: root.recent = ToplevelManager.toplevels.values.slice()
    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            root.touch(ToplevelManager.activeToplevel);
        }
    }

    property var windows: []
    property int index: 0
    readonly property bool open: GlobalStates.windowSwitcherOpen

    function candidates() {
        const all = ToplevelManager.toplevels.values;
        const current = (Hyprland.focusedWorkspace?.id ?? 1) - 1;
        const ordered = root.recent.filter(t => all.includes(t)).concat(all.filter(t => !root.recent.includes(t)));
        // On another desktop: not here (-1, all desktops or unknown, counts as here).
        return ordered.filter(t => (t.desktop ?? -1) < 0 || t.desktop === current);
    }
    function step(delta) {
        if (!root.open) {
            root.windows = root.candidates();
            if (root.windows.length === 0)
                return;
            // The first press goes to the window used before the one in front (the one in front is first).
            const front = root.windows[0]?.activated ?? false;
            root.index = front && root.windows.length > 1 ? (delta > 0 ? 1 : root.windows.length - 1) : (delta > 0 ? 0 : root.windows.length - 1);
            GlobalStates.windowSwitcherOpen = true;
            return;
        }
        const n = root.windows.length;
        if (n > 0)
            root.index = (root.index + delta + n) % n;
    }
    function pick(i) {
        const chosen = root.windows[i ?? root.index];
        root.close();
        if (chosen) {
            chosen.activate();
            root.touch(chosen);
        }
    }
    function close() {
        GlobalStates.windowSwitcherOpen = false;
        root.windows = [];
    }

    GlobalShortcut {
        name: "windowSwitcherNext"
        description: "Window switcher (Alt+Tab): next window"
        onPressed: root.step(1)
    }
    GlobalShortcut {
        name: "windowSwitcherPrevious"
        description: "Window switcher (Alt+Shift+Tab): previous window"
        onPressed: root.step(-1)
    }
    GlobalShortcut {
        name: "windowSwitcherPick"
        description: "Window switcher: Alt released, the window shown is picked"
        onPressed: if (root.open) root.pick()
    }
    GlobalShortcut {
        name: "windowSwitcherCancel"
        description: "Window switcher: Esc"
        onPressed: root.close()
    }
    // Something else took over meanwhile.
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen)
                root.close();
        }
        function onScreenLockedChanged() {
            root.close();
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            // On the screen in front (where the window in front is, or the focused one).
            readonly property bool here: (Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name) === modelData.name
            visible: root.open && panel.here
            color: "transparent"
            WlrLayershell.namespace: "quickshell:windowSwitcher"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            implicitWidth: card.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: card.implicitHeight + Appearance.sizes.elevationMargin * 2
            mask: Region {
                item: card
            }

            readonly property real thumbHeight: Math.max(90, Math.min(160, (modelData.height ?? 1080) / 6))
            readonly property real thumbWidth: thumbHeight * 16 / 10
            readonly property int columns: Math.max(1, Math.floor(((modelData.width ?? 1920) * 0.9 - 32) / (panel.thumbWidth + 24)))

            StyledRectangularShadow {
                target: card
            }
            Rectangle {
                id: card
                anchors.centerIn: parent
                implicitWidth: grid.implicitWidth + 32
                implicitHeight: grid.implicitHeight + 32
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                scale: root.open ? 1 : 0.92
                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                GridLayout {
                    id: grid
                    anchors.centerIn: parent
                    columns: Math.min(panel.columns, Math.max(1, root.windows.length))
                    rowSpacing: 8
                    columnSpacing: 8

                    Repeater {
                        model: panel.visible ? root.windows : []
                        delegate: Rectangle {
                            id: tile
                            required property var modelData
                            required property int index
                            readonly property bool selected: tile.index === root.index
                            implicitWidth: panel.thumbWidth + 16
                            implicitHeight: panel.thumbHeight + 44
                            radius: Appearance.rounding.normal
                            color: tile.selected ? Appearance.colors.colSecondaryContainer : (tileMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent")
                            border.width: tile.selected ? 2 : 0
                            border.color: Appearance.colors.colPrimary
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }

                            readonly property string iconSource: Quickshell.iconPath(AppSearch.iconForWindow(tile.modelData?.appId ?? "", tile.modelData?.executable ?? ""), "application-x-executable")

                            Item {
                                id: thumbArea
                                x: 8
                                y: 8
                                width: panel.thumbWidth
                                height: panel.thumbHeight
                                ScreencopyView {
                                    id: thumb
                                    anchors.centerIn: parent
                                    captureSource: tile.modelData?.minimized ? null : tile.modelData
                                    live: true
                                    constraintSize: Qt.size(panel.thumbWidth, panel.thumbHeight)
                                }
                                // Minimized (DWM shows nothing) or not drawn yet: the app's icon.
                                IconImage {
                                    anchors.centerIn: parent
                                    visible: !thumb.hasContent
                                    implicitSize: Math.min(64, panel.thumbHeight * 0.5)
                                    source: tile.iconSource
                                }
                            }
                            RowLayout {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                    margins: 8
                                }
                                spacing: 6
                                IconImage {
                                    implicitSize: 18
                                    source: tile.iconSource
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: tile.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
                                    text: tile.modelData?.title || tile.modelData?.appId || ""
                                }
                            }
                            MouseArea {
                                id: tileMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.pick(tile.index)
                            }
                        }
                    }
                }
            }
        }
    }
}
