pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * ii-windows (plan 2026-10-31, block B): what the updater knows, for the bar's dot, the right sidebar and
 * Configuración > Actualizaciones. ii-shim update keeps <data>\update\state.json; ii-host decides when to look and
 * does what the buttons ask (ii-shim host update-...). Nothing is downloaded or installed from here directly.
 */
Singleton {
    id: root

    readonly property string dataDir: Quickshell.env("II_DATA_DIR") || (Quickshell.env("LOCALAPPDATA") + "\\ii-windows")
    property var info: ({})

    readonly property string status: info?.status ?? "idle"
    readonly property var latest: info?.latest ?? null
    readonly property string latestVersion: latest?.version ?? ""
    readonly property bool critical: latest?.critical ?? false
    readonly property bool tooOld: latest?.tooOld ?? false
    readonly property string notes: latest?.notes ?? ""
    readonly property string releaseUrl: latest?.url ?? "https://github.com/TheCarlosS5/ii-windows/releases"
    readonly property real sizeMb: Math.round((latest?.size ?? 0) / 1048576)
    readonly property real progress: (info?.progress?.total ?? 0) > 0 ? info.progress.bytes / info.progress.total : 0
    readonly property string error: info?.error ?? ""
    readonly property string current: info?.current ?? ""
    readonly property string lastCheck: info?.lastCheck ?? ""
    readonly property bool busy: ["checking", "downloading", "verifying", "installing"].includes(root.status)
    readonly property bool ready: root.status === "ready"
    // Something for the user to see: the dot in the bar.
    readonly property bool attention: root.latest !== null
        && ["available", "downloading", "downloaded", "verifying", "installing", "ready", "waiting-network"].includes(root.status)

    function statusText() {
        switch (root.status) {
        case "checking": return Translation.tr("Looking for a new version…");
        case "available": return Translation.tr("ii %1 is available").arg(root.latestVersion);
        case "waiting-network": return Translation.tr("ii %1 will download on Wi-Fi or cable").arg(root.latestVersion);
        case "downloading": return Translation.tr("Downloading ii %1… %2%").arg(root.latestVersion).arg(Math.round(root.progress * 100));
        case "verifying": return Translation.tr("Checking the download…");
        case "downloaded": return Translation.tr("ii %1 is downloaded").arg(root.latestVersion);
        case "installing": return Translation.tr("Preparing ii %1…").arg(root.latestVersion);
        case "ready": return Translation.tr("ii %1 is ready: it applies when ii restarts").arg(root.latestVersion);
        case "error": return Translation.tr("Could not update: %1").arg(root.error);
        default: return Translation.tr("ii is up to date");
        }
    }

    function command(args) {
        Quickshell.execDetached(["ii-shim", "host"].concat(args));
        refreshSoon.restart();
    }
    function check() { root.command(["update-check"]); }
    function install() { root.command(["update-install"]); }
    function restartNow() { root.command(["update-restart"]); }
    function snooze() { root.command(["update-snooze"]); }
    function skip() {
        if (root.latestVersion.length > 0) root.command(["update-skip", root.latestVersion]);
    }
    function rollback() { Quickshell.execDetached(["ii-shim", "host", "rollback"]); }

    FileView {
        id: stateFile
        path: root.dataDir + "\\update\\state.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.info = JSON.parse(stateFile.text());
            } catch (e) {}
        }
    }
    // The file may not exist yet (no check so far), and a busy step updates it every second.
    Timer {
        interval: root.busy ? 1500 : 60000
        running: true
        repeat: true
        onTriggered: stateFile.reload()
    }
    // ---- what's new after an update (B3.6) ------------------------------------------------------------------------------
    // The installed version's notes (kept from its signed release.json when the updater brought it; none after a setup).
    // At the first start of a version that came by the updater: a notice "ii se actualizó a 0.9.0" with "Ver novedades",
    // which opens Configuración > Actualizaciones, where the notes stay to be read again.
    property string installedId: ""
    property string installedVersion: ""
    property string installedNotes: ""
    Process {
        running: true
        command: ["ii-shim", "update", "whatsnew"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.installedId = d.current ?? "";
                    root.installedVersion = d.version ?? "";
                    root.installedNotes = d.notes ?? "";
                    root.announceIfNew();
                } catch (e) {}
            }
        }
    }
    FileView {
        id: seenFile
        path: FileUtils.trimFileProtocol(`${Directories.state}/whats-new.json`)
        printErrors: false
        blockLoading: true
    }
    function announceIfNew() {
        if (root.installedId === "" || root.installedId === "dev") return;
        let seen = "";
        try { seen = JSON.parse(seenFile.text()).seen ?? ""; } catch (e) {}
        if (seen === root.installedId) return;
        seenFile.setText(JSON.stringify({ seen: root.installedId }));
        if (root.installedNotes.length === 0) return; // installed by the setup: nothing to tell
        Quickshell.execDetached(["notify-send", "-a", "ii", "--ii-button", `${Translation.tr("See what's new")}=whats-new`,
            Translation.tr("ii was updated to %1").arg(root.installedVersion || root.installedId), root.notesSummary()]);
    }
    // The first points of the notes, as plain text, for the notice.
    function notesSummary() {
        const lines = root.installedNotes.split("\n").map(l => l.trim()).filter(l => l.length > 0 && !l.startsWith("#"));
        return lines.slice(0, 3).map(l => l.replace(/^[-*]\s*/, "• ").replace(/[*_`]/g, "")).join("\n");
    }

    Timer {
        id: refreshSoon
        interval: 900
        onTriggered: stateFile.reload()
    }
}
