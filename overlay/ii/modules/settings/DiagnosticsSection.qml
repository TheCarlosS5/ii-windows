import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows (plan 2026-10-31, A4/A9): Configuración > Avanzado > Diagnóstico. What ii-host switched off after crashes
// (state.ini [safety]), the crash reports kept on this PC, and the buttons to turn everything on again, restart ii,
// open the reports and report a problem. Nothing here leaves the PC.
ContentSection {
    id: root
    icon: "monitor_heart"
    title: Translation.tr("Diagnostics")

    readonly property string dataDir: (Quickshell.env("II_DATA_DIR") || (Quickshell.env("LOCALAPPDATA") + "\\ii-windows"))
    property string disabledParts: ""
    property bool safeMode: false
    readonly property bool anythingOff: root.safeMode || root.disabledParts.length > 0

    function partName(part) {
        switch (part) {
        case "mpris": return Translation.tr("music and videos");
        case "notifications": return Translation.tr("reading Windows notifications");
        case "battery": return Translation.tr("battery");
        case "bluetooth": return Translation.tr("Bluetooth");
        case "render": return Translation.tr("drawing with the graphics card");
        default: return part;
        }
    }

    // state.ini is written by ii-host (WritePrivateProfileString); read again whenever it changes.
    FileView {
        id: stateFile
        path: root.dataDir + "\\state.ini"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const text = stateFile.text();
            const section = /\[safety\]([\s\S]*?)(?:\n\[|$)/i.exec(text);
            const body = section ? section[1] : "";
            const disabled = /^disabled=(.*)$/im.exec(body);
            const safe = /^safe=(.*)$/im.exec(body);
            root.disabledParts = disabled ? disabled[1].trim() : "";
            root.safeMode = safe ? safe[1].trim() === "1" : false;
        }
    }

    FolderListModel {
        id: reports
        folder: "file:///" + (root.dataDir + "\\crashes").replace(/\\/g, "/")
        nameFilters: ["*.json"]
        showDirs: false
        sortField: FolderListModel.Time
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: root.anythingOff ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
        text: root.safeMode
            ? Translation.tr("ii is in safe mode: it closed several times in a row, so it starts with the minimum.")
            : root.disabledParts.length > 0
                ? Translation.tr("Switched off after repeated errors: %1.").arg(root.disabledParts.split(",").map(p => root.partName(p)).join(", "))
                : Translation.tr("Everything is on.")
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
        text: reports.count === 0
            ? Translation.tr("No error reports on this PC.")
            : Translation.tr("Error reports kept on this PC: %1 (the newest: %2). They stay here; nothing is sent.")
                .arg(reports.count).arg(reports.count > 0 ? Qt.formatDateTime(reports.get(0, "fileModified"), "dd/MM HH:mm") : "")
    }
    Flow {
        Layout.fillWidth: true
        spacing: 5
        RippleButtonWithIcon {
            visible: root.anythingOff
            materialIcon: "restart_alt"
            mainText: Translation.tr("Turn everything on again")
            onClicked: Quickshell.execDetached(["ii-shim", "host", "safe-mode-off"])
        }
        RippleButtonWithIcon {
            materialIcon: "refresh"
            mainText: Translation.tr("Restart ii")
            onClicked: Quickshell.execDetached(["ii-shim", "host", "restart-shell"])
        }
        RippleButtonWithIcon {
            materialIcon: "folder_open"
            mainText: Translation.tr("Open the error reports")
            onClicked: Quickshell.execDetached(["explorer.exe", root.dataDir + "\\crashes"])
        }
        RippleButtonWithIcon {
            materialIcon: "bug_report"
            mainText: Translation.tr("Report a problem")
            // powershell.exe directly: cmd /c with a quoted path breaks under execDetached.
            onClicked: Quickshell.execDetached(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                Quickshell.shellPath("../rescue/ii-report.ps1").replace(/\//g, "\\")])
        }
    }
}
