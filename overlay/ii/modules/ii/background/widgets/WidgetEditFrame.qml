import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows: a desktop widget while editing the desktop: outlined, dragged from anywhere (its
// own buttons stop taking clicks), − / + resize it, the eye hides it. Drops snap to the grid.
MouseArea {
    id: root

    required property Item widget
    readonly property real counterScale: 1 / Math.max(0.1, widget.scale)

    anchors.fill: parent
    z: 1000
    enabled: GlobalStates.desktopEditMode && !GlobalStates.screenLocked
    visible: enabled
    hoverEnabled: true
    preventStealing: true
    drag.target: widget
    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    onPressed: root.bringToFront()
    onReleased: widget.saveDrop()

    // The widget being arranged goes above the others (each sits in its own loader).
    function bringToFront() {
        GlobalStates.desktopEditTop += 1;
        if (root.widget.parent) root.widget.parent.z = GlobalStates.desktopEditTop;
    }
    onWheel: event => {
        widget.resizeBy(event.angleDelta.y > 0 ? 0.1 : -0.1);
        event.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -6 * root.counterScale
        radius: Appearance.rounding.large * root.counterScale
        color: Qt.alpha(Appearance.colors.colPrimary, root.containsMouse ? 0.12 : 0.05)
        border.width: 2 * root.counterScale
        border.color: Appearance.colors.colPrimary
    }

    Rectangle { // toolbar, kept at its normal size whatever the widget's
        id: toolbar
        // Inside the widget's corner: outside it, neighbours (or the bar) would cover it.
        anchors {
            top: parent.top
            right: parent.right
            margins: 6 * root.counterScale
        }
        transformOrigin: Item.TopRight
        scale: root.counterScale
        implicitWidth: buttons.implicitWidth + 8
        implicitHeight: buttons.implicitHeight + 8
        radius: Appearance.rounding.full
        color: Appearance.colors.colPrimary

        RowLayout {
            id: buttons
            anchors.centerIn: parent
            spacing: 2
            EditButton {
                symbol: "remove"
                tip: Translation.tr("Smaller")
                onClicked: root.widget.resizeBy(-0.1)
            }
            StyledText {
                text: `${Math.round(root.widget.sizeFactor * 100)}%`
                color: Appearance.colors.colOnPrimary
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
            }
            EditButton {
                symbol: "add"
                tip: Translation.tr("Bigger")
                onClicked: root.widget.resizeBy(0.1)
            }
            EditButton {
                // The music widget: its synced lyrics on or off.
                visible: root.widget.configEntryName === "media"
                symbol: "lyrics"
                tip: (root.widget.configEntry.lyrics ?? false) ? Translation.tr("Hide the lyrics") : Translation.tr("Show the lyrics")
                onClicked: root.widget.configEntry.lyrics = !(root.widget.configEntry.lyrics ?? false)
            }
            EditButton {
                symbol: "visibility_off"
                tip: Translation.tr("Hide")
                onClicked: root.widget.configEntry.enable = false
            }
        }
    }

    // Bottom-right corner: drag to resize, keeping the widget's proportions (like a window
    // resized from its corner, without distorting it).
    MouseArea {
        id: resizeHandle
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: -8 * root.counterScale
        }
        width: 30 * root.counterScale
        height: 30 * root.counterScale
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.SizeFDiagCursor
        property point start
        property real startFactor: 1
        property real startWidth: 1
        property real startHeight: 1
        onPressed: mouse => {
            root.bringToFront();
            start = mapToItem(root.widget.parent, mouse.x, mouse.y);
            startFactor = root.widget.sizeFactor;
            startWidth = Math.max(1, root.widget.width * root.widget.scale);
            startHeight = Math.max(1, root.widget.height * root.widget.scale);
        }
        onPositionChanged: mouse => {
            if (!pressed) return;
            const p = mapToItem(root.widget.parent, mouse.x, mouse.y);
            const factor = Math.max((startWidth + p.x - start.x) / startWidth, (startHeight + p.y - start.y) / startHeight);
            root.widget.setSize(startFactor * factor);
        }

        Rectangle {
            anchors.centerIn: parent
            width: 26 * root.counterScale
            height: width
            radius: width / 2
            color: resizeHandle.containsMouse || resizeHandle.pressed ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary
            MaterialSymbol {
                anchors.centerIn: parent
                text: "open_in_full"
                rotation: 90
                iconSize: 16 * root.counterScale
                color: Appearance.colors.colOnPrimary
            }
        }
    }

    component EditButton: RippleButton {
        id: button
        property string symbol
        property string tip
        implicitWidth: 30
        implicitHeight: 30
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        colBackgroundHover: Qt.alpha(Appearance.colors.colOnPrimary, 0.15)
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: button.symbol
            iconSize: 18
            color: Appearance.colors.colOnPrimary
        }
        StyledToolTip {
            text: button.tip
        }
    }
}
