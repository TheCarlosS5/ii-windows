pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// ii-windows: every installed app as a grid of big icons (GNOME's "Show Applications", macOS' Launchpad),
// with the most used ones in a row above. Keyboard (driven from the search field, which keeps the focus):
// move(direction) with the arrows, activateCurrent() with Enter.
Item {
    id: root

    // Height the overview leaves for this widget (Overview.qml); 0 = guess from the window.
    property real availableHeight: 0
    readonly property real cell: 124
    readonly property real sectionTitleHeight: 30
    readonly property real windowWidth: root.QsWindow.window?.width ?? 1280
    readonly property real windowHeight: root.QsWindow.window?.height ?? 800
    readonly property int columns: Math.max(3, Math.min(8, Math.floor((windowWidth * 0.75) / cell)))
    readonly property var apps: AppSearch.list.slice().sort((a, b) => a.name.localeCompare(b.name))

    // The most used apps: one row at most.
    readonly property var frequent: (Config.options.overview.showFrequent ?? true) ? AppUsage.top.slice(0, columns) : []
    readonly property bool hasFrequent: frequent.length > 0
    readonly property real frequentBlockHeight: hasFrequent ? sectionTitleHeight + cell + 12 : 0

    readonly property real freeHeight: availableHeight > 0 ? availableHeight : windowHeight - 320
    readonly property int rows: Math.max(1, Math.floor((freeHeight - 40 - frequentBlockHeight) / cell))

    implicitWidth: columns * cell + 40
    implicitHeight: Math.min(rows, Math.max(1, Math.ceil(apps.length / columns))) * cell + 40 + frequentBlockHeight

    // Keyboard selection: 0..F-1 the most used row, F.. the grid. -1 = nothing selected yet.
    property int currentIndex: -1
    readonly property int frequentCount: frequent.length

    function entryAt(index) {
        return index < root.frequentCount ? root.frequent[index] : root.apps[index - root.frequentCount];
    }
    function move(direction) {
        const F = root.frequentCount;
        const total = F + root.apps.length;
        if (total === 0)
            return;
        const cols = root.columns;
        let i = root.currentIndex;
        if (i < 0) {
            root.currentIndex = 0;
            return;
        }
        if (direction === "right")
            i = Math.min(total - 1, i + 1);
        else if (direction === "left")
            i = Math.max(0, i - 1);
        else if (direction === "down") {
            if (i < F)
                i = F + Math.min(i, root.apps.length - 1);
            else if (i - F + cols < root.apps.length)
                i += cols;
        } else if (direction === "up") {
            if (i >= F) {
                const g = i - F;
                if (g - cols >= 0)
                    i -= cols;
                else if (F > 0)
                    i = Math.min(g, F - 1);
            }
        }
        root.currentIndex = i;
        if (i >= F)
            grid.positionViewAtIndex(i - F, GridView.Contain);
    }
    function activateCurrent() {
        if (root.currentIndex < 0)
            return;
        root.launch(root.entryAt(root.currentIndex));
    }
    function launch(entry) {
        if (!entry)
            return;
        GlobalStates.overviewOpen = false;
        AppUsage.launch(entry);
    }

    StyledRectangularShadow {
        target: background
    }
    Rectangle {
        id: background
        anchors.centerIn: parent
        width: root.implicitWidth
        height: root.implicitHeight
        radius: Appearance.rounding.large
        // Same glass as the bar and the dock (colLayer0 and its border).
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        clip: true

        // The most used apps.
        Item {
            id: frequentBlock
            visible: root.hasFrequent
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: 14
                leftMargin: 20
                rightMargin: 20
            }
            height: root.frequentBlockHeight
            StyledText {
                id: frequentTitle
                text: Translation.tr("Frequently used")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                height: root.sectionTitleHeight
                verticalAlignment: Text.AlignVCenter
                leftPadding: 4
            }
            Row {
                anchors.top: frequentTitle.bottom
                spacing: 4 // the tiles are cell - 4 wide: they line up with the grid below
                Repeater {
                    model: root.frequent
                    delegate: AppTile {
                        required property var modelData
                        required property int index
                        entry: modelData
                        tileIndex: index
                    }
                }
            }
            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    bottomMargin: 2
                }
                height: 1
                color: Appearance.colors.colOutlineVariant
            }
        }

        GridView {
            id: grid
            anchors {
                top: root.hasFrequent ? frequentBlock.bottom : parent.top
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: 20
                topMargin: root.hasFrequent ? 6 : 20
            }
            cellWidth: root.cell
            cellHeight: root.cell
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.apps
            delegate: AppTile {
                required property var modelData
                required property int index
                entry: modelData
                tileIndex: root.frequentCount + index
            }
        }
    }

    component AppTile: RippleButton {
        id: tile
        required property var entry
        required property int tileIndex
        readonly property bool current: root.currentIndex === tileIndex
        width: root.cell - 4
        height: root.cell - 4
        focusPolicy: Qt.NoFocus
        buttonRadius: Appearance.rounding.large
        colBackground: current ? Appearance.colors.colPrimaryContainer : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 1)
        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
        colRipple: Appearance.colors.colPrimaryContainerActive
        onClicked: root.launch(tile.entry)
        PointingHandInteraction {}
        contentItem: Column {
            anchors.centerIn: parent
            spacing: 8
            IconImage {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitSize: 56
                mipmap: true
                source: Quickshell.iconPath(tile.entry.icon, "image-missing")
            }
            StyledText {
                width: root.cell - 16
                horizontalAlignment: Text.AlignHCenter
                text: tile.entry.name
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: tile.current ? Appearance.colors.colOnPrimaryContainer : Appearance.m3colors.m3onSurface
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }
}
