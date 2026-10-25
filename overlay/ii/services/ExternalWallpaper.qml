pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Windows
import qs.modules.common

// ii-windows: Wallpaper Engine / Lively next to ii.
//
// Those programs draw the animated wallpaper behind the desktop; ii's background is a window above it that is
// transparent wherever ii paints no picture. So while one of them is running ii stops painting its own wallpaper
// (Background.qml checks `active`) and the animation shows through, with ii's icons, widgets and menus on top.
// The palette comes from the wallpaper's preview picture (the one the program keeps for each wallpaper), through
// `switchwall --palette-from`; when the program is closed the palette of ii's own wallpaper comes back.
//
// `ii-shim extwall status` does the looking (read-only, see host/src/extwall.cpp), but only when something changed:
// every few seconds the shell checks in-process (SystemProbe) whether one of the programs runs and whether its own
// file (`watch`: Wallpaper Engine's config.json, Lively's WallpaperLayout.json) was written since, instead of
// starting a process each time (plan 1.2). A full look every few minutes catches anything else.
Singleton {
    id: root

    // Config.options.background.externalProvider: "auto" (default) or "off"
    readonly property bool enabled: (Config.options?.background?.externalProvider ?? "auto") !== "off"

    property string provider: "none" // wallpaperengine | lively | none
    property bool running: false
    property string title: ""
    property string preview: ""

    readonly property bool active: enabled && running && provider !== "none"
    readonly property string providerName: provider === "wallpaperengine" ? "Wallpaper Engine" : provider === "lively" ? "Lively" : ""

    // Looks again now (the settings page's button, and the timer below).
    function refresh() {
        if (!statusProc.running) {
            root.lastFullLook = Date.now();
            statusProc.running = true;
        }
    }

    // The cheap check: a full look only when a program started or ended, or its file changed.
    readonly property var programs: ["wallpaper64.exe", "wallpaper32.exe", "Lively.exe"]
    property string watch: ""
    property string probeKey: ""
    property real lastFullLook: 0
    function probe() {
        const key = SystemProbe.processRunning(root.programs) + "|" + SystemProbe.modifiedMs(root.watch);
        if (key !== root.probeKey || Date.now() - root.lastFullLook > 300000) {
            root.probeKey = key;
            root.refresh();
        }
    }

    // Makes the palette from the preview again (also after a light/dark switch, which regenerates it from ii's wallpaper).
    function recalc() {
        if (!Persistent.ready)
            return;
        Persistent.states.externalWallpaper.palette = "";
        root.settle();
    }

    // Windows keeps a wallpaper per virtual desktop, and on every desktop switch it shows that one for a moment
    // before the live wallpaper is drawn again: a different static picture. While a live wallpaper runs, the
    // desktop we are on gets a still of it as its Windows wallpaper (only if it showed ii's own picture); when
    // the live wallpaper is gone it gets ii's back. A desktop not visited yet is fixed the first time it is.
    function assistDesktop() {
        if (!enabled || !Persistent.ready)
            return;
        if (root.active && root.preview !== "") {
            Persistent.states.externalWallpaper.stillUsed = true;
            stillProc.command = ["ii-shim", "switchwall", "--desktop-still", root.preview];
        } else if (Persistent.states.externalWallpaper.stillUsed) {
            stillProc.command = ["ii-shim", "switchwall", "--desktop-still-restore"];
        } else {
            return;
        }
        if (!stillProc.running)
            stillProc.running = true;
    }

    function parse(text) {
        let data;
        try {
            data = JSON.parse(text);
        } catch (e) {
            return;
        }
        root.provider = data.provider ?? "none";
        root.running = data.running === true;
        root.title = data.title ?? "";
        root.preview = data.preview ?? "";
        root.watch = data.watch ?? "";
        root.probeKey = SystemProbe.processRunning(root.programs) + "|" + SystemProbe.modifiedMs(root.watch);
        root.settle();
        const key = root.active + "|" + root.preview;
        if (key !== root.assistedKey) {
            root.assistedKey = key;
            root.assistDesktop();
        }
    }
    property string assistedKey: ""

    // Brings the palette in line with what is running. The last preview a palette was made from is kept in
    // Persistent, so a restart neither redoes it nor forgets to undo it (the program was closed meanwhile).
    function settle() {
        if (!Persistent.ready)
            return;
        const made = Persistent.states.externalWallpaper.palette;
        if (root.active && root.preview !== "" && root.preview !== made) {
            Persistent.states.externalWallpaper.palette = root.preview;
            paletteProc.command = ["ii-shim", "switchwall", "--palette-from", root.preview, "--mode", root.modeArg];
            paletteProc.running = true;
        } else if (!root.active && made !== "") {
            Persistent.states.externalWallpaper.palette = "";
            paletteProc.command = ["ii-shim", "switchwall", "--noswitch", "--mode", root.modeArg];
            paletteProc.running = true;
        }
    }

    readonly property string modeArg: Appearance.m3colors.darkmode ? "dark" : "light"

    Process {
        id: statusProc
        command: ["ii-shim", "extwall", "status"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }
    Process {
        id: paletteProc
    }
    Process {
        id: stillProc
    }

    // A desktop switch: the new desktop gets the still (or its own wallpaper back) right away.
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            stillTimer.restart();
        }
    }
    Timer {
        id: stillTimer
        interval: 120
        onTriggered: root.assistDesktop()
    }

    // Cheap (one process snapshot and two small files), so every few seconds; not at all when switched off.
    Timer {
        interval: 6000
        running: root.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: root.probe()
    }
    onEnabledChanged: {
        if (!enabled) {
            root.running = false;
            root.provider = "none";
            root.settle();
        }
    }
    onActiveChanged: root.settle()

    // The light/dark switch runs `switchwall --noswitch`, which paints ii's own wallpaper's palette: put the
    // preview's back once it is done.
    Connections {
        target: Appearance.m3colors
        function onDarkmodeChanged() {
            if (root.active)
                redoTimer.restart();
        }
    }
    Timer {
        id: redoTimer
        interval: 1500
        onTriggered: root.recalc()
    }
}
