pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

// ii-windows: Wallpaper Engine / Lively next to ii.
//
// Those programs draw the animated wallpaper behind the desktop; ii's background is a window above it that is
// transparent wherever ii paints no picture. So while one of them is running ii stops painting its own wallpaper
// (Background.qml checks `active`) and the animation shows through, with ii's icons, widgets and menus on top.
// The palette comes from the wallpaper's preview picture (the one the program keeps for each wallpaper), through
// `switchwall --palette-from`; when the program is closed the palette of ii's own wallpaper comes back.
//
// `ii-shim extwall status` does the looking (read-only, see host/src/extwall.cpp).
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
        if (!statusProc.running)
            statusProc.running = true;
    }

    // Makes the palette from the preview again (also after a light/dark switch, which regenerates it from ii's wallpaper).
    function recalc() {
        if (!Persistent.ready)
            return;
        Persistent.states.externalWallpaper.palette = "";
        root.settle();
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
        root.settle();
    }

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

    // Cheap (one process snapshot and two small files), so every few seconds; not at all when switched off.
    Timer {
        interval: 6000
        running: root.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
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
