pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows: an app of the store as a tile of a grid (Play Store style): its icon, name, a line about it and the
// one button that matters. The tile lifts a little under the pointer.
Rectangle {
    id: root
    property string appId: ""
    property string name: ""
    property string description: ""
    property string site: ""
    property var aka: []

    implicitHeight: 212
    radius: Appearance.rounding.large
    color: hover.hovered ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
    Behavior on color {
        ColorAnimation { duration: 160 }
    }
    scale: hover.hovered ? 1.015 : 1
    Behavior on scale {
        NumberAnimation { duration: 200 * Appearance.motionFactor; easing.type: Easing.OutCubic }
    }
    HoverHandler {
        id: hover
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: 16
        }
        spacing: 6

        StoreIcon {
            site: root.site
            label: root.name
            size: 60
        }
        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 4
            text: root.name
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.large
            font.weight: Font.Medium
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: root.description
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        StoreAction {
            compact: true
            appId: root.appId
            name: root.name
            aka: root.aka
        }
    }
}
