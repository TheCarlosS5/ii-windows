pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// ii-windows: right click on a dock app, like the Windows taskbar's: the app, a new window,
// pin or unpin, close its window(s). Right click on the dock itself (or the overview button)
// opens the dock's own menu: pin it, move it, settings. Opens next to the dock; any click
// elsewhere closes it.
PopupWindow {
    id: root

    required property Item dockApps
    property Item button: null
    readonly property var appToplevel: button?.appToplevel ?? null
    readonly property var desktopEntry: button?.desktopEntry ?? null
    readonly property int windowCount: appToplevel?.toplevels?.length ?? 0
    readonly property bool forDock: button === null
    // The dock lists apps by lower-cased id while pins keep the Start menu's casing
    // (Microsoft.Windows.Explorer): compare without case, pin with the proper id.
    readonly property string appId: desktopEntry?.id ?? appToplevel?.appId ?? ""
    readonly property bool pinned: Config.options.dock.pinnedApps.some(id => id.toLowerCase() === root.appId.toLowerCase())
    readonly property string edge: dockApps.edge

    function togglePin() {
        const pins = Config.options.dock.pinnedApps;
        Config.options.dock.pinnedApps = root.pinned
            ? pins.filter(id => id.toLowerCase() !== root.appId.toLowerCase())
            : pins.concat([root.appId]);
    }
    property bool shown: false
    property real center: 0

    function open(target) {
        root.button = target;
        root.center = target ? dockApps.centerOfButton(target) : dockApps.width / 2;
        if (!target)
            root.center = dockApps.vertical ? dockApps.height / 2 : dockApps.width / 2;
        root.shown = true;
    }
    function close() {
        root.shown = false;
    }

    readonly property var entries: {
        if (root.forDock) {
            return [
                { icon: Config.options.dock.pinnedOnStartup ? "keep_off" : "keep",
                  text: Config.options.dock.pinnedOnStartup ? Translation.tr("Let the dock hide") : Translation.tr("Keep the dock visible"),
                  action: () => { Config.options.dock.pinnedOnStartup = !Config.options.dock.pinnedOnStartup; } },
                { icon: "south", text: Translation.tr("Dock at the bottom"), enabled: root.edge !== "bottom",
                  action: () => { Config.options.dock.position = "bottom"; } },
                { icon: "west", text: Translation.tr("Dock on the left"), enabled: root.edge !== "left",
                  action: () => { Config.options.dock.position = "left"; } },
                { icon: "east", text: Translation.tr("Dock on the right"), enabled: root.edge !== "right",
                  action: () => { Config.options.dock.position = "right"; } },
                { icon: "settings", text: Translation.tr("Dock settings"),
                  action: () => Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("settings.qml")]) },
            ];
        }
        const list = [
            { icon: "open_in_new", text: Translation.tr("New window"), enabled: root.desktopEntry !== null,
              action: () => AppUsage.launch(root.desktopEntry) },
            { icon: root.pinned ? "keep_off" : "keep", text: root.pinned ? Translation.tr("Unpin from dock") : Translation.tr("Pin to dock"),
              action: () => root.togglePin() },
        ];
        if (root.windowCount > 0) {
            list.push({ icon: "close", text: root.windowCount > 1 ? Translation.tr("Close all windows") : Translation.tr("Close window"),
                        action: () => root.appToplevel.toplevels.forEach(t => t.close()) });
        }
        return list;
    }

    anchor {
        window: root.dockApps.QsWindow.window
        adjustment: PopupAdjustment.None
        rect.x: root.edge === "left" ? root.dockApps.edgeGap + root.dockApps.bgThick + 4
            : root.edge === "right" ? root.dockApps.width - (root.dockApps.edgeGap + root.dockApps.bgThick + 4) : 0
        rect.y: root.edge === "bottom" ? root.dockApps.height - (root.dockApps.edgeGap + root.dockApps.bgThick + 4) : 0
        rect.width: 1
        rect.height: 1
        gravity: root.edge === "bottom" ? (Edges.Top | Edges.Right) : root.edge === "left" ? (Edges.Bottom | Edges.Right) : (Edges.Bottom | Edges.Left)
        edges: Edges.Top | Edges.Left
    }
    visible: menu.opacity > 0
    color: "transparent"
    implicitWidth: root.dockApps.vertical ? menu.width + Appearance.sizes.elevationMargin * 2 : (root.dockApps.QsWindow.window?.width ?? 1)
    implicitHeight: root.dockApps.vertical ? (root.dockApps.QsWindow.window?.height ?? 1) : menu.implicitHeight + Appearance.sizes.elevationMargin * 2

    HyprlandFocusGrab {
        windows: [root, root.dockApps.QsWindow.window]
        active: root.shown
        onCleared: root.close()
    }

    StyledRectangularShadow {
        target: menu
        opacity: menu.opacity
        visible: menu.visible
    }

    Rectangle {
        id: menu
        opacity: root.shown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        readonly property real margin: Appearance.sizes.elevationMargin
        x: root.edge === "bottom" ? Math.max(margin, Math.min(root.center - width / 2, parent.width - width - margin))
            : root.edge === "left" ? margin : parent.width - width - margin
        y: root.edge === "bottom" ? parent.height - height - margin
            : Math.max(margin, Math.min(root.center - height / 2, parent.height - height - margin))
        width: 240
        implicitHeight: menuColumn.implicitHeight + 12
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surfaceContainer

        Column {
            id: menuColumn
            anchors.fill: parent
            anchors.margins: 6
            spacing: 2

            // The app, as the Windows taskbar shows it at the top of the list.
            Item {
                visible: !root.forDock
                width: menuColumn.width
                height: root.forDock ? 0 : 44
                IconImage {
                    id: appIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 26
                    source: Quickshell.iconPath(AppSearch.iconForWindow(root.appToplevel?.appId ?? "", root.appToplevel?.toplevels?.[0]?.executable ?? ""), "image-missing")
                }
                StyledText {
                    anchors.left: appIcon.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.m3colors.m3onSurface
                    text: root.desktopEntry?.name ?? root.appToplevel?.appId ?? ""
                }
            }

            Rectangle {
                visible: !root.forDock
                width: menuColumn.width - 12
                x: 6
                height: root.forDock ? 0 : 1
                color: Appearance.colors.colOutlineVariant
            }

            Repeater {
                model: root.entries
                delegate: Rectangle {
                    id: entry
                    required property var modelData
                    width: menuColumn.width
                    height: 38
                    radius: Appearance.rounding.small
                    enabled: modelData.enabled ?? true
                    opacity: enabled ? 1 : 0.4
                    color: entryMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"

                    MaterialSymbol {
                        id: entryIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.icon
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.m3colors.m3onSurface
                    }
                    StyledText {
                        anchors.left: entryIcon.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.text
                        color: Appearance.m3colors.m3onSurface
                    }
                    MouseArea {
                        id: entryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.close();
                            entry.modelData.action();
                        }
                    }
                }
            }
        }
    }
}
