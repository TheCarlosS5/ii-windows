import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows (plan 2026-10-31, C3): the search field at the top of Configuración (Ctrl+F). While it has text the page
// gives way to SettingsSearchResults; Esc empties it, Enter opens the first result, ↑/↓ choose another.
Rectangle {
    id: root

    property alias query: field.text
    signal accepted()
    signal moved(int step)

    function focusField() {
        field.forceActiveFocus();
        field.selectAll();
    }
    function clear() {
        field.text = "";
    }

    implicitHeight: 44
    radius: Appearance.rounding.full
    color: field.activeFocus ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
    border.width: field.activeFocus ? 2 : 0
    border.color: Appearance.colors.colPrimary

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 6
        spacing: 4
        MaterialSymbol {
            text: "search"
            iconSize: 22
            color: Appearance.colors.colSubtext
        }
        ToolbarTextField {
            id: field
            Layout.fillWidth: true
            Layout.fillHeight: true
            colBackground: "transparent"
            placeholderText: Translation.tr("Search settings (Ctrl+F)")
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape && field.text !== "") {
                    field.text = "";
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.accepted();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                    root.moved(1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    root.moved(-1);
                    event.accepted = true;
                }
            }
        }
        RippleButton {
            visible: field.text !== ""
            implicitWidth: 32
            implicitHeight: 32
            buttonRadius: Appearance.rounding.full
            onClicked: field.text = ""
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "close"
                iconSize: 18
                color: Appearance.colors.colSubtext
            }
        }
    }
}
