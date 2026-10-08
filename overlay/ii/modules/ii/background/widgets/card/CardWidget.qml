import QtQuick
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

// ii-windows: one of ii's panels (calendar, to-do, timer...) on the desktop, in a card like the
// sidebar's. Drag it by its edges like the clock. `fill`: the panel takes the card's size;
// otherwise the card takes the panel's.
AbstractBackgroundWidget {
    id: root

    property url source
    property bool fill: true
    property real cardWidth: 360
    property real cardHeight: 360
    property real padding: 10

    implicitWidth: fill ? cardWidth : (loader.item?.implicitWidth || loader.item?.width || 0) + padding * 2
    implicitHeight: fill ? cardHeight : (loader.item?.implicitHeight || loader.item?.height || 0) + padding * 2

    StyledDropShadow {
        target: card
    }
    Rectangle {
        id: card
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer0

        Loader {
            id: loader
            anchors.fill: root.fill ? parent : undefined
            anchors.centerIn: root.fill ? undefined : parent
            anchors.margins: root.fill ? root.padding : 0
            source: root.source
        }
    }
}
