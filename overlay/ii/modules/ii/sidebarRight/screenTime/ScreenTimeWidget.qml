import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// ii-windows: today's screen time per program, counted by ii-host (host/src/screentime.cpp) while someone is at the
// PC: %LOCALAPPDATA%\ii-windows\screentime\YYYY-MM-DD.json. Nothing leaves the PC.
Item {
    id: root

    property int total: 0
    property var apps: [] // [{ exe, seconds, name, path }] most first

    function today() {
        return Qt.formatDate(new Date(), "yyyy-MM-dd");
    }
    function duration(s) {
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        if (h > 0)
            return Translation.tr("%1 h %2 min").arg(h).arg(m);
        if (m > 0)
            return Translation.tr("%1 min").arg(m);
        return Translation.tr("< 1 min");
    }
    function baseName(exe) {
        return exe.replace(/\.exe$/i, "");
    }
    function displayName(app) {
        if (app.name)
            return app.name; // the program's own description, written by the host
        const base = root.baseName(app.exe);
        if (AppSearch.appsVersion < 0)
            return base; // dependency only: names once the Start menu list is loaded
        // Only an exact id: matching by program (heuristicLookup) also finds shortcuts that merely open a file with it.
        const entry = DesktopEntries.byId(base);
        return entry?.name ?? (base.charAt(0).toUpperCase() + base.slice(1));
    }

    FileView {
        id: file
        path: `${(Quickshell.env("II_DATA_DIR") || (Quickshell.env("LOCALAPPDATA") + "/ii-windows")).replace(/\\/g, "/")}/screentime/${root.today()}.json`
        onLoaded: {
            try {
                const data = JSON.parse(file.text());
                const list = Object.keys(data.apps ?? {}).map(exe => ({
                    exe: exe,
                    seconds: data.apps[exe],
                    name: data.names?.[exe] ?? "",
                    path: data.paths?.[exe] ?? ""
                }));
                list.sort((a, b) => b.seconds - a.seconds);
                root.total = data.total ?? 0;
                root.apps = list.slice(0, 7);
            } catch (e) {
                root.total = 0;
                root.apps = [];
            }
        }
        onLoadFailed: {
            root.total = 0;
            root.apps = [];
        }
    }
    // The host writes once a minute; read again while the tab is on screen.
    Timer {
        running: root.visible
        interval: 30000
        repeat: true
        triggeredOnStart: true
        onTriggered: file.reload()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            StyledText {
                text: Translation.tr("Today")
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer1
            }
            Item { Layout.fillWidth: true }
            StyledText {
                text: root.total > 0 ? root.duration(root.total) : ""
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: Appearance.colors.colPrimary
            }
        }

        Repeater {
            model: root.apps
            delegate: RowLayout {
                id: row
                required property var modelData
                Layout.fillWidth: true
                spacing: 10
                IconImage {
                    implicitSize: 22
                    mipmap: true
                    // the program file's own icon (as the dock shows programs without a Start menu entry)
                    source: Quickshell.iconPath(row.modelData.path ? "winfile:" + row.modelData.path : AppSearch.guessIcon(root.baseName(row.modelData.exe)), "application-x-executable")
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.displayName(row.modelData)
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            text: root.duration(row.modelData.seconds)
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 4
                        radius: 2
                        color: Appearance.colors.colLayer2
                        Rectangle {
                            width: parent.width * Math.min(1, row.modelData.seconds / Math.max(1, root.apps[0]?.seconds ?? 1))
                            height: parent.height
                            radius: 2
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        StyledText {
            visible: root.apps.length === 0
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Translation.tr("Nothing yet today. ii counts the time each program is in front while you use the PC; it stays on this PC.")
            color: Appearance.colors.colSubtext
        }
        Item {
            visible: root.apps.length === 0
            Layout.fillHeight: true
        }
    }
}
