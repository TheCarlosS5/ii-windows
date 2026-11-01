pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import "../modules/common/functions/dailylook_logic.js" as Logic

/**
 * ii-windows (plan 2026-10-31, E13): the look that follows the day (Configuración > Apariencia > Según el día).
 *   - Wallpaper of the day: Bing's image of the day (`ii-shim randomwall bing`), once a day; the Material colors follow
 *     it as with any wallpaper. A failed download is tried again half an hour later.
 *   - Light by day, dark by night: the theme changes at the two hours chosen; a change by hand stays until the next one.
 */
Singleton {
    id: root
    function load() {}
    readonly property bool dailyOn: Config.options?.background?.daily?.enable ?? false
    readonly property bool autoDarkOn: Config.options?.appearance?.autoDark?.enable ?? false
    property string wallpaperDay: ""   // the day the wallpaper of the day was set
    property real triedAt: 0
    property string phase: ""          // "light" | "dark": the last one applied by the clock

    function currentPhase(now) {
        const a = Config.options.appearance.autoDark;
        return Logic.phaseAt(a.lightAt, a.darkAt, now);
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
        if (Logic.shouldFetch(root.dailyOn, root.wallpaperDay, Logic.dayKey(now), bingProc.running, root.triedAt, Date.now())) {
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
            } catch (e) {}
        }
    }
    function save() {
        stateFile.setText(JSON.stringify({ wallpaperDay: root.wallpaperDay, phase: root.phase }));
    }
}
