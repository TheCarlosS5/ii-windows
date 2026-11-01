pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import "../modules/common/functions/dailylook_logic.js" as Logic

/**
 * ii-windows (plan 2026-10-31, E13): the look that follows the day (Configuración > Apariencia > Según el día).
 *   - Wallpaper of the day: Bing's image of the day (`ii-shim randomwall bing`), once a day; a failed download is tried
 *     again half an hour later. Or a folder of your own, its next image every N minutes (by name, wrapping around).
 *     The Material colors follow it as with any wallpaper.
 *   - Light by day, dark by night: at two chosen hours, or at sunrise and sunset (the weather's, for its location; the
 *     chosen hours while it is not known). A change by hand stays until the next transition.
 */
Singleton {
    id: root
    function load() {}
    readonly property var daily: Config.options?.background?.daily ?? ({})
    readonly property bool dailyOn: root.daily.enable ?? false
    readonly property string source: root.daily.source ?? "bing" // "bing" | "folder"
    readonly property bool autoDarkOn: Config.options?.appearance?.autoDark?.enable ?? false
    property string wallpaperDay: ""   // the day the wallpaper of the day was set
    property real triedAt: 0
    property real rotatedAt: 0         // when the folder's image last changed
    property string phase: ""          // "light" | "dark": the last one applied by the clock

    // The weather service is only touched when the sun is asked for (it may be off otherwise).
    readonly property var hours: {
        const a = Config.options?.appearance?.autoDark;
        const sun = root.autoDarkOn && a?.mode === "sun";
        return Logic.hoursFor(a, sun ? Weather.data?.sunrise : "", sun ? Weather.data?.sunset : "");
    }
    function currentPhase(now) {
        return Logic.phaseAt(root.hours.light, root.hours.dark, now);
    }
    function applyPhase(p) {
        root.phase = p;
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", p, "--noswitch"]);
        root.save();
    }
    onAutoDarkOnChanged: if (Config.ready && root.autoDarkOn) { const p = root.currentPhase(new Date()); if (p) root.applyPhase(p); }

    Timer {
        interval: 60000
        running: Config.ready
        repeat: true
        triggeredOnStart: true
        onTriggered: root.check()
    }
    function check() {
        const now = new Date();
        if (root.source === "folder") {
            if (Logic.shouldRotate(root.dailyOn, root.rotatedAt, Date.now(), root.daily.minutes)) root.rotate();
        } else if (Logic.shouldFetch(root.dailyOn, root.wallpaperDay, Logic.dayKey(now), bingProc.running, root.triedAt, Date.now())) {
            root.triedAt = Date.now();
            bingProc.running = true;
        }
        if (root.autoDarkOn) {
            const p = root.currentPhase(now);
            if (p && p !== root.phase) root.applyPhase(p);
        }
    }
    Process {
        id: bingProc
        command: ["ii-shim", "randomwall", "bing"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) return;
            root.wallpaperDay = Logic.dayKey(new Date());
            root.save();
        }
    }

    // ---- a folder of your own ---------------------------------------------------------------------------------------
    FolderListModel {
        id: folderModel
        folder: root.source === "folder" && (root.daily.folder ?? "") !== "" ? "file:///" + String(root.daily.folder).replace(/\\/g, "/") : ""
        showDirs: false
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.bmp", "*.gif"]
        onStatusChanged: if (status === FolderListModel.Ready && root.dailyOn) Qt.callLater(root.check)
    }
    function rotate() {
        if (folderModel.status !== FolderListModel.Ready) return;
        const files = [];
        for (let i = 0; i < folderModel.count; ++i) files.push(String(folderModel.get(i, "filePath")));
        const next = Logic.nextInFolder(files, Config.options.background.wallpaperPath);
        if (!next) return;
        root.rotatedAt = Date.now();
        root.save();
        Wallpapers.apply(next);
    }

    FileView {
        id: stateFile
        path: FileUtils.trimFileProtocol(`${Directories.state}/daily-look.json`)
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.wallpaperDay = s.wallpaperDay ?? "";
                root.phase = s.phase ?? "";
                root.rotatedAt = s.rotatedAt ?? 0;
            } catch (e) {}
        }
    }
    function save() {
        stateFile.setText(JSON.stringify({ wallpaperDay: root.wallpaperDay, phase: root.phase, rotatedAt: root.rotatedAt }));
    }
}
