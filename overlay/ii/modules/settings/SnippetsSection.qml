import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows (plan 2026-10-31, E8): Configuración > Servicios > Fragmentos. Texts you paste often (your e-mail, an
// address, a signature): type their name in the search (Win) and Enter pastes them into the app in front. Also saved
// from a clipboard entry in the search (";" then "Guardar como fragmento").
ContentSection {
    id: root
    icon: "text_snippet"
    title: Translation.tr("Snippets")

    function snippets() {
        return JSON.parse(JSON.stringify(Config.options.search.snippets ?? []));
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Appearance.colors.colSubtext
        text: Translation.tr("Texts you paste often. Type their name in the search and press Enter: it is pasted into the app you were using.")
    }
    Repeater {
        model: Config.options.search.snippets ?? []
        delegate: RowLayout {
            id: row
            required property var modelData
            required property int index
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol { text: "text_snippet"; iconSize: 20; color: Appearance.colors.colOnLayer1 }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText { text: row.modelData.name || ""; font.weight: Font.Medium; color: Appearance.colors.colOnLayer1; elide: Text.ElideRight; Layout.fillWidth: true }
                StyledText {
                    Layout.fillWidth: true
                    text: String(row.modelData.text ?? "").replace(/\s+/g, " ")
                    elide: Text.ElideRight
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                onClicked: {
                    const list = root.snippets();
                    list.splice(row.index, 1);
                    Config.options.search.snippets = list;
                }
                contentItem: MaterialSymbol { anchors.centerIn: parent; text: "delete"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                StyledToolTip { text: Translation.tr("Remove") }
            }
        }
    }
    ContentSubsection {
        title: Translation.tr("Add a snippet")
        MaterialTextField {
            id: nameField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Name (what you type in the search, e.g. correo)")
        }
        MaterialTextArea {
            id: textField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Text")
            wrapMode: TextEdit.Wrap
        }
        RippleButtonWithIcon {
            materialIcon: "add"
            mainText: Translation.tr("Add")
            enabled: nameField.text.trim().length > 0 && textField.text.trim().length > 0
            onClicked: {
                Config.options.search.snippets = root.snippets().concat([{ name: nameField.text.trim(), text: textField.text }]);
                nameField.text = "";
                textField.text = "";
            }
        }
    }
}
