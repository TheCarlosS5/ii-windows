pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows: Windows' virtual desktops under the overview, like Task View's strip. Each card
// shows the wallpaper with the icons of the apps open on that desktop; click switches to it
// (the overview stays open with that desktop's windows), × closes it (Windows moves its windows
// to the neighbour), and the last card makes a new one.
Item {
    id: root

    required property var screen
    readonly property real previewHeight: 72
    readonly property real previewWidth: previewHeight * (screen?.width ?? 16) / (screen?.height ?? 9)
    readonly property var desktops: Hyprland.workspaces.values
    readonly property int activeId: Hyprland.focusedWorkspace?.id ?? 1

    implicitWidth: background.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: background.implicitHeight + Appearance.sizes.elevationMargin * 2

    function desktopName(desktop) {
        // Windows numbers unnamed desktops: "Escritorio 2". A name set in Task View wins.
        return desktop.name === `${desktop.id}` ? Translation.tr("Desktop %1").arg(desktop.id) : desktop.name;
    }

    StyledRectangularShadow {
        target: background
    }
    Rectangle {
        id: background
        anchors.centerIn: parent
        property real padding: 8
        implicitWidth: row.implicitWidth + padding * 2
        implicitHeight: row.implicitHeight + padding * 2
        radius: Appearance.rounding.large
        // Same glass as the bar and the dock (colLayer0 and its border), not a darker surface.
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6

            Repeater {
                model: root.desktops
                delegate: DesktopCard {
                    required property var modelData
                    desktop: modelData
                }
            }

            DesktopCard {
                isNew: true
            }
        }
    }

    component DesktopCard: Item {
        id: card
        property var desktop: null
        property bool isNew: false
        readonly property int desktopId: desktop?.id ?? 0
        readonly property bool active: !isNew && desktopId === root.activeId
        readonly property var windows: isNew ? [] : HyprlandData.windowList.filter(w => w.workspace.id === card.desktopId)

        implicitWidth: root.previewWidth + 12
        implicitHeight: column.implicitHeight + 12

        // A window card dragged here from the overview moves to this desktop on release
        // (GlobalStates.overviewDropDesktop; needs Windows 11 24H2+).
        DropArea {
            id: dropArea
            anchors.fill: parent
            enabled: !card.isNew
            onEntered: GlobalStates.overviewDropDesktop = card.desktopId
            onExited: if (GlobalStates.overviewDropDesktop === card.desktopId) GlobalStates.overviewDropDesktop = -1
        }

        Rectangle { // hover / active / drop background
            anchors.fill: parent
            radius: Appearance.rounding.normal
            color: dropArea.containsDrag ? Appearance.colors.colSecondaryContainer
                : mouseArea.pressed ? Appearance.colors.colLayer1Active
                : mouseArea.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        function closeDesktop() {
            if (root.desktops.length > 1) Hyprland.dispatch(`hl.dsp.ii.desktop.close({ workspace = ${card.desktopId} })`);
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: event => {
                if (card.isNew) {
                    // Hyprland semantics: going to a workspace that doesn't exist creates it.
                    Hyprland.dispatch(`hl.dsp.focus({ workspace = ${root.desktops.length + 1} })`);
                } else if (event.button === Qt.MiddleButton) {
                    card.closeDesktop();
                } else if (!card.active) {
                    Hyprland.dispatch(`hl.dsp.focus({ workspace = ${card.desktopId} })`);
                }
            }

            ColumnLayout {
                id: column
                anchors.centerIn: parent
                spacing: 4

                Rectangle { // preview
                    id: preview
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: root.previewWidth
                    implicitHeight: root.previewHeight
                    radius: Appearance.rounding.small
                    color: card.isNew ? "transparent" : Appearance.colors.colLayer2
                    border.width: card.isNew ? 1 : 0
                    border.color: Appearance.colors.colOutlineVariant

                    Image { // the wallpaper, with the preview's rounded corners
                        visible: !card.isNew
                        anchors.fill: parent
                        source: card.isNew ? "" : Config.options.background.wallpaperPath
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: root.previewWidth * 2
                        asynchronous: true
                        opacity: card.active ? 1 : 0.7
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: preview.width
                                height: preview.height
                                radius: preview.radius
                            }
                        }
                    }
                    Rectangle { // active desktop outline
                        anchors.fill: parent
                        visible: card.active
                        radius: preview.radius
                        color: "transparent"
                        border.width: 2
                        border.color: Appearance.colors.colSecondary
                    }

                    Row { // apps open on this desktop
                        anchors.centerIn: parent
                        spacing: 4
                        visible: !card.isNew
                        Repeater {
                            model: card.windows.slice(0, 4)
                            delegate: Rectangle {
                                required property var modelData
                                width: 26
                                height: 26
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer1
                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: 20
                                    source: Quickshell.iconPath(AppSearch.iconForWindow(parent.modelData.class, parent.modelData.executable), "image-missing")
                                }
                            }
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: card.windows.length > 4
                            text: `+${card.windows.length - 4}`
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }

                    MaterialSymbol {
                        visible: card.isNew
                        anchors.centerIn: parent
                        text: "add"
                        iconSize: 30
                        color: Appearance.colors.colOnLayer1
                    }

                    RippleButton { // close
                        visible: !card.isNew && root.desktops.length > 1 && mouseArea.containsMouse
                        anchors {
                            top: parent.top
                            right: parent.right
                            margins: 3
                        }
                        implicitWidth: 22
                        implicitHeight: 22
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer1
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        onClicked: card.closeDesktop()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 16
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledToolTip {
                            text: Translation.tr("Close desktop")
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: root.previewWidth
                    elide: Text.ElideRight
                    text: card.isNew ? Translation.tr("New desktop") : root.desktopName(card.desktop)
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: card.active ? Font.DemiBold : Font.Normal
                }
            }
        }
    }
}
