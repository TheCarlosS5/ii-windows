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
// pin or unpin, close its window(s). Opens above the button; any click elsewhere closes it.
PopupWindow {
    id: root

    required property Item dockApps
    property Item button: null
    readonly property var appToplevel: button?.appToplevel ?? null
    readonly property var desktopEntry: button?.desktopEntry ?? null
    readonly property int windowCount: appToplevel?.toplevels?.length ?? 0
    // The dock lists apps by lower-cased id while pins keep the Start menu's casing
    // (Microsoft.Windows.Explorer): compare without case, pin with the proper id.
    readonly property string appId: desktopEntry?.id ?? appToplevel?.appId ?? ""
    readonly property bool pinned: Config.options.dock.pinnedApps.some(id => id.toLowerCase() === root.appId.toLowerCase())

    function togglePin() {
        const pins = Config.options.dock.pinnedApps;
        Config.options.dock.pinnedApps = root.pinned
            ? pins.filter(id => id.toLowerCase() !== root.appId.toLowerCase())
            : pins.concat([root.appId]);
    }
    property bool shown: false
    property real centerX: 0

    function open(target) {
        root.button = target;
        root.centerX = dockApps.popupCenterXForButton(target);
        root.shown = true;
    }
    function close() {
        root.shown = false;
    }

    readonly property var entries: {
        const list = [
            { icon: "open_in_new", text: Translation.tr("New window"), enabled: root.desktopEntry !== null,
              action: () => root.desktopEntry?.execute() },
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
        gravity: Edges.Top | Edges.Right
        edges: Edges.Top | Edges.Left
    }
    visible: menu.opacity > 0
    color: "transparent"
    implicitWidth: root.dockApps.QsWindow.window?.width ?? 1
    implicitHeight: menu.implicitHeight + Appearance.sizes.elevationMargin * 2

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
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Appearance.sizes.elevationMargin
        x: Math.max(Appearance.sizes.elevationMargin, Math.min(root.centerX - width / 2, parent.width - width - Appearance.sizes.elevationMargin))
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
                width: menuColumn.width
                height: 44
                IconImage {
                    id: appIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 26
                    source: Quickshell.iconPath(AppSearch.guessIcon(root.appToplevel?.appId ?? ""), "image-missing")
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
                width: menuColumn.width - 12
                x: 6
                height: 1
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
