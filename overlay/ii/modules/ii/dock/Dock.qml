import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland

// ii-windows: the dock panel. A transparent window along one screen edge (bottom by default,
// or left/right) big enough for the magnified icons; only the dock itself takes the mouse.
// Drawing and magnification live in DockApps.qml.
Scope {
    id: root
    property bool pinned: Config.options?.dock.pinnedOnStartup ?? false
    onPinnedChanged: {
        if (Config.options.dock.pinnedOnStartup !== pinned)
            Config.options.dock.pinnedOnStartup = pinned;
    }
    Connections {
        target: Config.options.dock
        function onPinnedOnStartupChanged() {
            root.pinned = Config.options.dock.pinnedOnStartup;
        }
    }
    // Space the dock takes at each edge (for the desktop icons), pinned or not.
    readonly property real reserved: (Appearance.sizes.hyprlandGapsOut + 1) * 1 + Math.max(24, Config.options.dock.iconSize) + 18 + Appearance.sizes.hyprlandGapsOut
    Binding { target: GlobalStates; property: "dockInsetBottom"; value: root.edge === "bottom" ? root.reserved : 0 }
    Binding { target: GlobalStates; property: "dockInsetLeft"; value: root.edge === "left" ? root.reserved : 0 }
    Binding { target: GlobalStates; property: "dockInsetRight"; value: root.edge === "right" ? root.reserved : 0 }
    readonly property string edge: {
        const p = Config.options?.dock.position ?? "bottom";
        return (p === "left" || p === "right") ? p : "bottom";
    }

    Variants {
        // For each monitor
        model: Quickshell.screens

        PanelWindow {
            id: dockRoot
            // Window
            required property var modelData
            screen: modelData
            visible: !GlobalStates.screenLocked && (Config.options?.dock.enable ?? true)

            readonly property bool vertical: root.edge !== "bottom"
            property bool reveal: root.pinned || dockApps.requestDockShow || (!ToplevelManager.activeToplevel?.activated)
                || (Config.options?.dock.hoverToReveal && dockApps.hovering)

            anchors {
                bottom: true
                left: true
                right: root.edge !== "left"
                top: root.edge !== "bottom"
            }

            // The panel only needs to be as tall (wide) as the magnified dock.
            exclusiveZone: root.pinned ? dockApps.reservedThickness : 0

            implicitWidth: vertical ? dockApps.thickness : 0
            implicitHeight: vertical ? 0 : dockApps.thickness
            WlrLayershell.namespace: "quickshell:dock"
            color: "transparent"

            // Input: the dock when idle, the magnified area while the cursor is on it, a thin strip at
            // the screen edge when slid away (that strip brings it back).
            mask: Region {
                item: maskItem
            }
            Item {
                id: maskItem
                readonly property real strip: Math.max(2, Config.options?.dock.hoverRegionHeight ?? 2)
                readonly property real stripLen: Math.max(120, dockApps.stripMain)
                readonly property real mainStart: dockApps.stripMainOrigin
                // Cross size of what takes input.
                readonly property real crossSize: !dockRoot.reveal ? strip
                    : dockApps.active ? dockApps.edgeGap + dockApps.bgThick + dockApps.overflow
                    : dockApps.edgeGap + dockApps.bgThick
                readonly property real mainStartActive: dockRoot.reveal ? mainStart - (dockApps.active ? 10 : 0) : (dockApps.mainLen - stripLen) / 2
                readonly property real mainSize: dockRoot.reveal ? dockApps.stripMain + (dockApps.active ? 20 : 0) : stripLen
                x: !dockRoot.vertical ? mainStartActive : (root.edge === "left" ? 0 : dockApps.width - crossSize)
                y: !dockRoot.vertical ? dockApps.height - crossSize : mainStartActive
                width: !dockRoot.vertical ? mainSize : crossSize
                height: !dockRoot.vertical ? crossSize : mainSize
            }

            // What the side panels need to know to use the corner next to a pinned dock (they stop above the
            // space it reserves, which leaves an empty corner where the dock does not reach). The span is
            // the dock at rest plus room for its magnification, so it does not jump while the pointer is on it.
            readonly property real spanSlack: (dockApps.maxScale - 1) * dockApps.iconSize * 4
            Binding {
                target: GlobalStates
                property: "dockExclusiveBottom"
                value: (root.pinned && root.edge === "bottom") ? dockApps.reservedThickness : 0
            }
            Binding {
                target: GlobalStates
                property: "dockSpanLeft"
                value: dockApps.width / 2 - dockApps.layout.restTotal / 2 - dockApps.pad - dockRoot.spanSlack
            }
            Binding {
                target: GlobalStates
                property: "dockSpanRight"
                value: dockApps.width / 2 + dockApps.layout.restTotal / 2 + dockApps.pad + dockRoot.spanSlack
            }

            DockApps {
                id: dockApps
                anchors.fill: parent
                edge: root.edge
                revealed: dockRoot.reveal
                slide: dockRoot.reveal ? 0 : (edgeGap + bgThick + 14)
                Behavior on slide {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
