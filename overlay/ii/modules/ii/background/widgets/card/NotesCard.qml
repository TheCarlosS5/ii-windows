import QtQuick
import QtQuick.Controls
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

// ii-windows: a sticky note on the desktop. What you write is kept in ii's config
// (background.widgets.notes.text), so it survives restarts.
AbstractBackgroundWidget {
    id: root

    configEntryName: "notes"
    implicitWidth: configEntry.width ?? 300
    implicitHeight: configEntry.height ?? 240

    StyledDropShadow {
        target: card
    }
    Rectangle {
        id: card
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.colors.colTertiaryContainer

        MaterialSymbol {
            id: pin
            anchors {
                top: parent.top
                right: parent.right
                margins: 12
            }
            text: "sticky_note_2"
            iconSize: 22
            fill: 1
            color: Appearance.colors.colOnTertiaryContainer
            opacity: 0.6
        }

        ScrollView {
            anchors {
                fill: parent
                margins: 14
                rightMargin: 36
            }
            TextArea {
                id: textArea
                text: root.configEntry.text ?? ""
                placeholderText: Translation.tr("Write something…")
                placeholderTextColor: Qt.alpha(Appearance.colors.colOnTertiaryContainer, 0.5)
                wrapMode: TextEdit.Wrap
                background: null
                selectByMouse: true
                color: Appearance.colors.colOnTertiaryContainer
                selectionColor: Appearance.colors.colTertiary
                selectedTextColor: Appearance.colors.colOnTertiary
                font {
                    family: Appearance.font.family.main
                    pixelSize: root.configEntry.fontSize ?? 16
                }
                onTextChanged: saveTimer.restart()
            }
        }
        Timer {
            id: saveTimer
            interval: 600
            onTriggered: if (root.configEntry.text !== textArea.text) root.configEntry.text = textArea.text
        }
    }
}
