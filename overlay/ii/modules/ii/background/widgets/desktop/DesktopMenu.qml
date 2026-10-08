pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// ii-windows: the desktop's right-click menu, in place of Explorer's. Wallpaper (selector, a
// random one from the wallpaper folder or from Konachan), desktop widgets on and off, the
// overlay, ii's settings and Windows' display settings. A widget turned on from here appears
// where the menu was opened.
Item {
    id: root

    readonly property bool menuOpen: menu.shown
    property real originX: 0
    property real originY: 0

    // Keep the menu clear of the bar and of the dock (both sit above the desktop).
    readonly property real topLimit: (Config.options.bar.bottom ? 0 : Appearance.sizes.barHeight) + 8
    readonly property real bottomLimit: root.height - 8 - (Config.options.bar.bottom ? Appearance.sizes.barHeight : 0)
        - (Config.options.dock.enable ? Config.options.dock.height + 16 : 0)

    // Options of the widget under the pointer (its menuEntries), shown first.
    property var widgetEntries: []

    function popup(x, y, widget) {
        root.originX = x;
        root.originY = y;
        root.widgetEntries = widget?.menuEntries ?? [];
        menu.shown = true;
    }

    function close() {
        menu.shown = false;
    }

    function changeWallpaper() {
        if (Config.options.wallpaperSelector.useSystemFileDialog)
            Wallpapers.openFallbackPicker(Appearance.m3colors.darkmode);
        else
            GlobalStates.wallpaperSelectorOpen = true;
    }

    function widgetEnabled(key) {
        return Config.options.background.widgets[key]?.enable ?? false;
    }

    function toggleWidget(key) {
        const entry = Config.options.background.widgets[key];
        const enabling = !entry.enable;
        // Free-placed widgets come up under the pointer; the others keep their own placement.
        if (enabling && entry.placementStrategy === "free") {
            entry.x = Math.round(root.originX);
            entry.y = Math.round(root.originY);
        }
        entry.enable = enabling;
    }

    readonly property var entries: [
        ...root.widgetEntries,
        ...(root.widgetEntries.length > 0 ? [{ separator: true }] : []),
        { icon: "wallpaper", text: Translation.tr("Change wallpaper"), action: () => root.changeWallpaper() },
        // From the wallpaper folder; with nothing there yet, one from Konachan (saved there).
        { icon: "shuffle", text: Translation.tr("Random wallpaper"),
          action: () => Wallpapers.folderModel.count > 0 ? Wallpapers.randomFromCurrentFolder()
                                                         : Quickshell.execDetached(["ii-shim", "randomwall", "konachan"]) },
        { icon: "cloud_download", text: Translation.tr("Random: Konachan"),
          action: () => Quickshell.execDetached(["ii-shim", "randomwall", "konachan"]) },
        { separator: true },
        { header: Translation.tr("Widgets") },
        { icon: "schedule", text: Translation.tr("Clock"), widget: "clock" },
        { icon: "music_note", text: Translation.tr("Music"), widget: "media" },
        { icon: "image", text: Translation.tr("Photo"), widget: "photo" },
        { icon: "folder", text: Translation.tr("Recent files"), widget: "folder" },
        { icon: "partly_cloudy_day", text: Translation.tr("Weather"), widget: "weather" },
        { icon: "apps", text: Translation.tr("Desktop icons"), widget: "desktopIcons" },
        { separator: true },
        { icon: "layers", text: Translation.tr("Overlay widgets"), action: () => GlobalStates.overlayOpen = true },
        { icon: "settings", text: Translation.tr("Settings"),
          action: () => Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("settings.qml")]) },
        { icon: "desktop_windows", text: Translation.tr("Display settings"),
          action: () => Quickshell.execDetached(["xdg-open", "ms-settings:display"]) },
    ]

    MouseArea {
        // Any click outside the open menu closes it.
        anchors.fill: parent
        visible: menu.shown
        acceptedButtons: Qt.AllButtons
        onPressed: root.close()
    }

    Rectangle {
        id: menu
        property bool shown: false
        // Bound, not assigned in popup(): the height changes once the entries are laid out.
        x: Math.max(8, Math.min(root.originX, root.width - width - 8))
        y: Math.max(root.topLimit, Math.min(root.originY, root.bottomLimit - height))
        visible: opacity > 0
        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.95
        transformOrigin: Item.TopLeft
        width: 248
        height: menuColumn.implicitHeight + 12
        radius: Appearance.rounding.normal
        // Layer1 is a translucent overlay intended to sit on Layer0, not wallpaper.
        color: Appearance.colors.colLayer0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        StyledDropShadow {
            target: menu
        }

        Column {
            id: menuColumn
            anchors.fill: parent
            anchors.margins: 6
            spacing: 2

            Repeater {
                model: root.entries
                delegate: Item {
                    id: entry
                    required property var modelData
                    readonly property bool isWidget: modelData.widget !== undefined
                    readonly property bool checked: isWidget && root.widgetEnabled(modelData.widget)
                    width: menuColumn.width
                    height: modelData.separator ? 9 : modelData.header ? 28 : 36

                    Rectangle {
                        visible: entry.modelData.separator === true
                        anchors.centerIn: parent
                        width: parent.width - 12
                        height: 1
                        color: Appearance.colors.colOutlineVariant
                    }

                    StyledText {
                        visible: entry.modelData.header !== undefined
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        text: entry.modelData.header ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    Rectangle {
                        visible: entry.modelData.icon !== undefined
                        anchors.fill: parent
                        radius: Appearance.rounding.small
                        color: entryMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"

                        MaterialSymbol {
                            id: entryIcon
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: entry.modelData.icon ?? ""
                            fill: entry.checked ? 1 : 0
                            iconSize: Appearance.font.pixelSize.larger
                            color: entry.checked ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            anchors.left: entryIcon.right
                            anchors.leftMargin: 10
                            anchors.right: checkIcon.left
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: entry.modelData.text ?? ""
                            color: Appearance.colors.colOnLayer1
                        }
                        MaterialSymbol {
                            id: checkIcon
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            visible: entry.isWidget
                            text: entry.checked ? "check_circle" : "radio_button_unchecked"
                            fill: entry.checked ? 1 : 0
                            iconSize: Appearance.font.pixelSize.larger
                            color: entry.checked ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        }
                        MouseArea {
                            id: entryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (entry.isWidget) {
                                    // Stay open so several widgets can be switched in a row.
                                    root.toggleWidget(entry.modelData.widget);
                                } else {
                                    root.close();
                                    entry.modelData.action();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
