pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// ii-windows: every installed app as a grid of big icons (GNOME's "Show Applications", macOS' Launchpad).
Item {
    id: root

    readonly property real cell: 124
    readonly property real windowWidth: root.QsWindow.window?.width ?? 1280
    readonly property real windowHeight: root.QsWindow.window?.height ?? 800
    readonly property int columns: Math.max(3, Math.min(8, Math.floor((windowWidth * 0.75) / cell)))
    readonly property int rows: Math.max(2, Math.floor((windowHeight - 320) / cell))
    readonly property var apps: AppSearch.list.slice().sort((a, b) => a.name.localeCompare(b.name))

    implicitWidth: columns * cell + 40
    implicitHeight: Math.min(rows, Math.ceil(apps.length / columns)) * cell + 40

    signal launched()

    StyledRectangularShadow {
        target: background
    }
    Rectangle {
        id: background
        anchors.centerIn: parent
        width: root.implicitWidth
        height: root.implicitHeight
        radius: Appearance.rounding.large
        color: Appearance.colors.colBackgroundSurfaceContainer
        clip: true

        GridView {
            id: grid
            anchors.fill: parent
            anchors.margins: 20
            cellWidth: root.cell
            cellHeight: root.cell
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.apps
            delegate: RippleButton {
                id: tile
                required property var modelData
                width: root.cell - 4
                height: root.cell - 4
                buttonRadius: Appearance.rounding.large
                colBackground: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 1)
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                onClicked: {
                    GlobalStates.overviewOpen = false;
                    tile.modelData.execute();
                }
                PointingHandInteraction {}
                contentItem: Column {
                    anchors.centerIn: parent
                    spacing: 8
                    IconImage {
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitSize: 56
                        mipmap: true
                        source: Quickshell.iconPath(tile.modelData.icon, "image-missing")
                    }
                    StyledText {
                        width: root.cell - 16
                        horizontalAlignment: Text.AlignHCenter
                        text: tile.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.m3colors.m3onSurface
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
