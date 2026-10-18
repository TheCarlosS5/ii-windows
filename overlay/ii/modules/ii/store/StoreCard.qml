pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows: one app of the store as a row of a list (search results, installed apps, updates): icon, name, a line
// about it and what can be done with it right now.
Rectangle {
    id: root
    property string appId: ""
    property string name: ""
    property string description: ""
    property string site: ""
    property var aka: [] // other names it has once installed (the store lists "Zoom", the PC says "Zoom Workplace")

    implicitHeight: 84
    radius: Appearance.rounding.large
    color: hover.hovered ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
    Behavior on color {
        ColorAnimation { duration: 160 }
    }
    HoverHandler {
        id: hover
    }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: 14
            rightMargin: 10
        }
        spacing: 14

        StoreIcon {
            Layout.alignment: Qt.AlignVCenter
            site: root.site
            label: root.name
            size: 52
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2
            StyledText {
                Layout.fillWidth: true
                text: root.name
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: root.description !== "" ? root.description : root.appId
                maximumLineCount: 2
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        StoreAction {
            Layout.alignment: Qt.AlignVCenter
            appId: root.appId
            name: root.name
            aka: root.aka
        }
    }
}
