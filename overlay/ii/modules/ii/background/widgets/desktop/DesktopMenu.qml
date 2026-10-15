pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// ii-windows: the desktop's right-click menu, in place of Explorer's. Desktop icons' entries
// (new folder, paste, sort, Explorer's menu), wallpaper (selector, a random one from the
// wallpaper folder or from Konachan), desktop widgets on and off, the overlay, ii's settings and
// Windows' display settings. A widget turned on from here appears where the menu was opened.
// The icons also show their own entries in it (popupEntries).
// The menu itself is drawn in its own Overlay-layer window: it belongs to the desktop, which
// sits under every app, but must show above the apps like Explorer's menus.
Item {
    id: root

    // The screen of the desktop this menu belongs to.
    property var screen: null

    readonly property bool menuOpen: menu.shown
    property real originX: 0
    property real originY: 0

    // Keep the menu clear of the bar and of the dock (both sit above the desktop).
    readonly property real topLimit: (Config.options.bar.bottom ? 0 : Appearance.sizes.barHeight) + 8
    readonly property real bottomLimit: root.height - 8 - (Config.options.bar.bottom ? Appearance.sizes.barHeight : 0)
        - (Config.options.dock.enable ? GlobalStates.dockInsetBottom + 16 : 0)

    // Options of the widget under the pointer (its menuEntries), shown first.
    property var widgetEntries: []
    // The desktop icons' entries (DesktopIcons.desktopEntries).
    property var desktopEntries: []
    // Set by popupEntries: show only these (an icon's menu).
    property var customEntries: null

    function popup(x, y, widget) {
        root.originX = x;
        root.originY = y;
        root.widgetEntries = widget?.menuEntries ?? [];
        root.customEntries = null;
        menu.shown = true;
    }

    function popupEntries(x, y, entries) {
        root.originX = x;
        root.originY = y;
        root.customEntries = entries;
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

    // Like Windows' own desktop menu, in ii's style and short: what you do on a desktop (new, paste,
    // sort), ii's settings, display settings and the native Windows menu (graphics control panel,
    // "Open with ...", Terminal ...) behind "More options". Wallpaper and widgets are changed from
    // Settings and from the edit mode, not from here.
    function desktopEntry(key) {
        return root.desktopEntries.find(e => e.key === key);
    }
    readonly property var entries: root.customEntries ?? [
        ...root.widgetEntries,
        ...(root.widgetEntries.length > 0 ? [{ separator: true }] : []),
        ...[root.desktopEntry("new"), root.desktopEntry("paste"), root.desktopEntry("sort")].filter(e => e !== undefined),
        ...(root.desktopEntries.length > 0 ? [{ separator: true }] : []),
        { icon: "palette", text: Translation.tr("Personalize"),
          action: () => Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("settings.qml")]) },
        { icon: "storefront", text: Translation.tr("App store"),
          action: () => Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("store.qml")]) },
        { icon: "dashboard_customize", text: Translation.tr("Edit desktop"), action: () => GlobalStates.desktopEditMode = true },
        { icon: "desktop_windows", text: Translation.tr("Display settings"),
          action: () => Quickshell.execDetached(["xdg-open", "ms-settings:display"]) },
        ...[root.desktopEntry("terminal"), root.desktopEntry("more")].filter(e => e !== undefined),
    ]

    PanelWindow {
        id: menuWindow
        screen: root.screen
        visible: menu.shown || menu.opacity > 0
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:desktopMenu"
        WlrLayershell.layer: WlrLayer.Overlay
        // No keyboard of its own: the desktop keeps it (Esc, and renaming right after).
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        MouseArea {
            // Any click outside the open menu closes it.
            anchors.fill: parent
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
            width: 300
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
                        height: modelData.separator ? 9 : modelData.header ? 28 : modelData.widgets ? widgetGrid.implicitHeight : 36

                        Rectangle {
                            visible: entry.modelData.separator === true
                            anchors.centerIn: parent
                            width: parent.width - 12
                            height: 1
                            color: Appearance.colors.colOutlineVariant
                        }

                        Grid {
                            id: widgetGrid
                            visible: entry.modelData.widgets !== undefined
                            columns: 2
                            spacing: 2
                            Repeater {
                                model: entry.modelData.widgets ?? []
                                delegate: Rectangle {
                                    id: chip
                                    required property var modelData
                                    readonly property bool checked: root.widgetEnabled(chip.modelData.widget)
                                    width: (menuColumn.width - 2) / 2
                                    height: 34
                                    radius: Appearance.rounding.small
                                    color: chip.checked ? (chipMouse.containsMouse ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
                                         : chipMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                                    MaterialSymbol {
                                        id: chipIcon
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: chip.modelData.icon
                                        fill: chip.checked ? 1 : 0
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: chip.checked ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    }
                                    StyledText {
                                        anchors.left: chipIcon.right
                                        anchors.leftMargin: 8
                                        anchors.right: parent.right
                                        anchors.rightMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        text: chip.modelData.text
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: chip.checked ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    }
                                    MouseArea {
                                        id: chipMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        // Stays open so several widgets can be switched in a row.
                                        onClicked: root.toggleWidget(chip.modelData.widget)
                                    }
                                }
                            }
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
                                anchors.right: entry.modelData.choices ? undefined : checkIcon.left
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: entry.modelData.text ?? ""
                                color: Appearance.colors.colOnLayer1
                            }
                            Row {
                                // A row of choices (e.g. Sort by: Name / Date / Type).
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                visible: entry.modelData.choices !== undefined
                                Repeater {
                                    model: entry.modelData.choices ?? []
                                    delegate: Rectangle {
                                        id: choice
                                        required property var modelData
                                        width: choiceText.implicitWidth + 14
                                        height: 26
                                        radius: height / 2
                                        color: choice.modelData.checked ? Appearance.colors.colSecondaryContainer
                                             : choiceMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                                        StyledText {
                                            id: choiceText
                                            anchors.centerIn: parent
                                            text: choice.modelData.text
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: choice.modelData.checked ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                        }
                                        MouseArea {
                                            id: choiceMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                root.close();
                                                choice.modelData.action();
                                            }
                                        }
                                    }
                                }
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
                                enabled: entry.modelData.choices === undefined
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
}
