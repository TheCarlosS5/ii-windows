import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "widgets/registry.js" as Registry

// ii-windows (plan 2026-10-31, C2): Configuración > Escritorio > Widgets. One light card per widget (name, icon, on/off);
// a widget's own settings (widgets/Widget_<key>.qml, made from the old long page by tools/port/gen_widget_pages.py)
// are created only when its "Personalizar" is pressed. More widgets no longer make the page longer or slower.
// II_SETTINGS_PAGE=backgroundconfig/<key> opens one directly (the gear of a widget in the desktop's edit mode).
ContentSection {
    id: root
    icon: "widgets"
    title: Translation.tr("Widgets")

    property string openKey: ""
    property string filter: ""
    function openRequested() { // a widget asked for (II_SETTINGS_PAGE, its gear on the desktop, the settings search)
        const key = SettingsRequest.take("backgroundconfig");
        const widget = Registry.widgets.find(w => w.key.toLowerCase() === key);
        if (widget) root.openKey = widget.key;
    }
    Component.onCompleted: root.openRequested()
    Connections { // asked while this page is already open
        target: SettingsRequest
        function onSerialChanged() { root.openRequested(); }
    }
    readonly property var openWidget: Registry.widgets.find(w => w.key === root.openKey) ?? null

    function displayName(widget) {
        return Translation.tr(widget.title).replace(/^Widget:\s*/, "");
    }
    function enabled(key) {
        return Config.options.background.widgets[key]?.enable ?? false;
    }
    function setEnabled(key, value) {
        if (Config.options.background.widgets[key]) Config.options.background.widgets[key].enable = value;
    }

    // --- the gallery ---------------------------------------------------------------------------------------------
    MaterialTextField {
        visible: root.openKey === ""
        Layout.fillWidth: true
        placeholderText: Translation.tr("Search widgets")
        onTextChanged: root.filter = text.toLowerCase()
    }
    StyledText {
        visible: root.openKey === ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
        text: Translation.tr("%1 of %2 on the desktop. Right click the desktop > Edit desktop to move and resize them.")
            .arg(Registry.widgets.filter(w => root.enabled(w.key)).length).arg(Registry.widgets.length)
    }
    Flow {
        visible: root.openKey === ""
        Layout.fillWidth: true
        spacing: 10
        Repeater {
            model: Registry.widgets.filter(w => root.filter === "" || root.displayName(w).toLowerCase().includes(root.filter))
            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property bool on: root.enabled(modelData.key)
                width: 180
                height: 132
                radius: Appearance.rounding.normal
                color: on ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        MaterialSymbol {
                            text: card.modelData.icon
                            iconSize: 26
                            color: card.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                        }
                        Item { Layout.fillWidth: true }
                        StyledSwitch {
                            checked: card.on
                            onClicked: root.setEnabled(card.modelData.key, checked)
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.displayName(card.modelData)
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: card.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                    }
                    Item { Layout.fillHeight: true }
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "tune"
                        mainText: Translation.tr("Customize")
                        onClicked: root.openKey = card.modelData.key
                    }
                }
            }
        }
    }

    // --- one widget's settings ------------------------------------------------------------------------------------
    RowLayout {
        visible: root.openKey !== ""
        Layout.fillWidth: true
        RippleButtonWithIcon {
            materialIcon: "arrow_back"
            mainText: Translation.tr("All widgets")
            onClicked: root.openKey = ""
        }
        Item { Layout.fillWidth: true }
    }
    Loader {
        id: detail
        visible: root.openKey !== ""
        Layout.fillWidth: true
        active: root.openKey !== ""
        asynchronous: true
        source: root.openWidget ? root.openWidget.file : ""
    }
    StyledText {
        visible: root.openKey !== "" && detail.status === Loader.Loading
        text: Translation.tr("Loading…")
        color: Appearance.colors.colSubtext
    }
}
