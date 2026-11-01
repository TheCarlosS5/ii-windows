import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows (plan 2026-10-31, E9): Configuración > Avanzado > Compatibilidad. The customization apps on this PC that
// ii knows (compat.json next to this file; `ii-shim compat` looks for them), what to expect from each and a fix.
ContentSection {
    id: root
    icon: "extension"
    title: Translation.tr("Compatibility")

    readonly property string tablePath: Quickshell.shellPath("modules/settings/compat.json")
    readonly property bool spanish: (Translation.resolvedLanguageCode ?? "").startsWith("es")
    property var table: []
    property var found: [] // [{ id, found }]
    readonly property var shown: root.found.map(f => ({ app: root.table.find(a => a.id === f.id), how: f.found })).filter(x => x.app)

    FileView {
        path: root.tablePath
        printErrors: false
        onLoaded: {
            try { root.table = JSON.parse(text()).apps ?? []; } catch (e) {}
        }
    }
    Process {
        id: detect
        running: true
        command: ["ii-shim", "compat", root.tablePath]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.found = JSON.parse(text); } catch (e) {}
            }
        }
    }
    function run(action) {
        if (action.kind === "settings") {
            Quickshell.execDetached({ command: ["qs", "-p", Quickshell.shellPath("settings.qml")], environment: { "II_SETTINGS_PAGE": action.target } });
        } else if (action.kind === "run") {
            Quickshell.execDetached(["cmd", "/c", "start", "", action.target]);
        }
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Appearance.colors.colSubtext
        text: detect.running ? Translation.tr("Looking for other customization apps...")
            : root.shown.length === 0 ? Translation.tr("None of the customization apps ii knows is on this PC (StartAllBack, ExplorerPatcher, Windhawk, PowerToys, Rainmeter, Wallpaper Engine...).")
            : Translation.tr("These apps also change Windows. ii works with them; this is what to expect.")
    }
    Repeater {
        model: root.shown
        delegate: RowLayout {
            id: row
            required property var modelData
            Layout.fillWidth: true
            spacing: 12
            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: row.modelData.app.level === "warn" ? "warning" : "info"
                iconSize: 22
                color: row.modelData.app.level === "warn" ? Appearance.m3colors.m3tertiary : Appearance.colors.colSubtext
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    text: row.modelData.app.name
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colOnLayer1
                    text: root.spanish ? row.modelData.app.es : row.modelData.app.en
                }
            }
            RippleButtonWithIcon {
                Layout.alignment: Qt.AlignTop
                visible: !!row.modelData.app.action
                materialIcon: "open_in_new"
                mainText: row.modelData.app.action ? (root.spanish ? row.modelData.app.action.es : row.modelData.app.action.en) : ""
                onClicked: root.run(row.modelData.app.action)
            }
        }
    }
    RippleButtonWithIcon {
        visible: !detect.running
        materialIcon: "refresh"
        mainText: Translation.tr("Look again")
        onClicked: detect.running = true
    }
}
