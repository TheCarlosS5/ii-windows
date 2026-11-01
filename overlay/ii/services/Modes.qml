pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.functions
import "../modules/common/functions/modes_logic.js" as Logic

/**
 * ii-windows (plan 2026-10-31, E2): modes. A mode changes several things at once and puts them back as they were when
 * it ends: No molestar, light/dark theme, ii's light mode, night light, keeping the screen on, the volume.
 *   Clase / Trabajo · Juego · Presentación · Noche   (Config.options.modes.list, edited in Configuración > Modos)
 * A mode starts by hand (the chips of the right panel, the search: "modo juego"), at its hours (days + from/to, also
 * across midnight), or while one of its apps has a window open (exe names; Juego also with any app in full screen
 * that is not a maximized window or a browser). By hand wins over automatic; turning off an automatic mode by hand keeps
 * it off until its reason ends (the app closes, the hours end). What a mode changed is put back only where it is still
 * as the mode left it: a theme changed by hand meanwhile stays. The state survives a restart of ii (State/modes.json).
 * The decisions are modes_logic.js' (tests/modes/test.js); this file reads the shell's state and applies them.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.modes?.enable ?? true
    readonly property var list: (Config.options?.modes?.list ?? []).filter(m => m && m.id)
    readonly property var defaultNames: ({ clase: "Class / Work", juego: "Game", presentacion: "Presentation", noche: "Night" })
    function nameOf(mode) {
        if (!mode) return "";
        return mode.name || Translation.tr(root.defaultNames[mode.id] ?? mode.id);
    }
    function modeById(id) {
        return root.list.find(m => m.id === id) ?? null;
    }

    property string activeId: ""
    property string reason: ""       // "manual" | "schedule" | "app"
    property string reasonDetail: "" // "18:00–22:00", "osu!"
    readonly property var active: root.modeById(root.activeId)
    property string manualId: ""     // chosen by hand
    property var dismissed: ({})     // id → true: turned off by hand while its automatic reason holds
    property var before: null        // what the active mode changed, as it was
    property var applied: null       // what it set
    property bool loaded: false
    property bool reapply: false
    function load() {} // shell.qml calls it at start, so the automatic triggers run without the panel being opened

    // ---- the chips and the search -----------------------------------------------------------------------------------
    function toggle(id) {
        if (root.activeId === id) root.turnOff();
        else root.turnOn(id);
    }
    function turnOn(id) {
        if (!root.modeById(id)) return;
        const d = Object.assign({}, root.dismissed);
        delete d[id];
        root.dismissed = d;
        root.manualId = id;
    }
    // Off by hand: also when an automatic reason holds (its app is open), until that reason ends.
    function turnOff() {
        if (root.manualId !== "") root.manualId = "";
        if (root.activeId !== "") {
            const d = Object.assign({}, root.dismissed);
            d[root.activeId] = true;
            root.dismissed = d;
        }
    }

    // ---- what should be on ------------------------------------------------------------------------------------------
    property int tick: 0
    Timer {
        interval: 30000
        running: root.enabled
        repeat: true
        onTriggered: {
            root.tick += 1;
            const still = Logic.stillDismissed(root.list, root.dismissed, root.windows(), new Date());
            if (Object.keys(still).length !== Object.keys(root.dismissed).length) root.dismissed = still;
        }
    }
    // What Logic needs of the open windows (only fields that rarely change: not the titles).
    function windows() {
        return ToplevelManager.toplevels.values.map(t => ({ executable: t.executable, activated: t.activated,
            fullscreen: t.fullscreen, maximized: t.maximized, minimized: t.minimized }));
    }
    // "id|reason|detail" of the mode that should be on ("" none). A string: it only changes when the answer does.
    readonly property string wanted: {
        root.tick; // the hours move on
        if (!Config.ready || !root.enabled || !root.loaded) return "";
        return Logic.wanted(root.list, root.manualId, root.dismissed, root.windows(), new Date());
    }
    onWantedChanged: Qt.callLater(root.reconcile)
    onEnabledChanged: Qt.callLater(root.reconcile)
    Connections { // a mode saved as on that is no longer wanted after a restart: "wanted" stays "", so no change says it
        target: Config
        function onReadyChanged() { Qt.callLater(root.reconcile); }
    }

    // ---- applying and putting back ----------------------------------------------------------------------------------
    function current() {
        return {
            silent: Notifications.silent,
            dark: Appearance.m3colors.darkmode,
            light: Performance.light,
            night: Hyprsunset.temperatureActive,
            awake: Idle.inhibit,
            volume: Audio.sink?.audio?.volume ?? -1
        };
    }
    function setValue(key, value) {
        switch (key) {
        case "silent": Notifications.silent = value; break;
        case "dark": Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", value ? "dark" : "light", "--noswitch"]); break;
        case "light": Performance.setLight(value); break;
        case "night": Hyprsunset.toggleTemperature(value); break;
        case "awake": Idle.toggleInhibit(value); break;
        case "volume": if (Audio.sink?.audio && value >= 0) Audio.sink.audio.volume = value; break;
        }
    }
    // again: after a restart of ii, set what does not survive one (No molestar) keeping the saved "before".
    function apply(mode, again) {
        const set = Logic.plan(mode);
        const now = root.current();
        if (!again || !root.before) root.before = now;
        for (const key of Object.keys(set)) {
            if (again && key === "volume") continue; // the user may have moved it since
            if (now[key] !== set[key]) root.setValue(key, set[key]);
        }
        root.applied = set;
    }
    function restore() {
        const back = Logic.restorePlan(root.before, root.applied, root.current());
        for (const key of Object.keys(back)) root.setValue(key, back[key]);
        root.before = null;
        root.applied = null;
    }
    function reconcile() {
        if (!root.loaded || !Config.ready) return; // before the config is read, "nothing wanted" would end the mode
        const parts = root.wanted.split("|");
        const id = parts[0] ?? "", reason = parts[1] ?? "", detail = parts[2] ?? "";
        if (id === root.activeId) {
            if (root.reapply && root.active) root.apply(root.active, true);
            root.reapply = false;
            if (root.reason !== reason || root.reasonDetail !== detail) {
                root.reason = reason;
                root.reasonDetail = detail;
                root.save();
            }
            return;
        }
        root.reapply = false;
        const old = root.active;
        if (root.activeId !== "") root.restore();
        root.activeId = id;
        root.reason = reason;
        root.reasonDetail = detail;
        const mode = root.active;
        if (mode) root.apply(mode, false);
        root.save();
        root.announce(old, mode, reason, detail);
    }
    // A notice when a mode starts or ends by itself (by hand, you know already).
    property string lastReason: ""
    function announce(old, mode, reason, detail) {
        const automatic = mode ? reason !== "manual" : root.lastReason !== "manual";
        root.lastReason = reason;
        if (!automatic || !(Config.options?.modes?.notify ?? true)) return;
        let title = "", body = "";
        if (mode) {
            title = Translation.tr("%1 mode is on").arg(root.nameOf(mode));
            body = reason === "app" ? Translation.tr("Because %1 is open. It ends when it closes.").arg(detail)
                : Translation.tr("By its hours (%1). Turn it off in the right panel.").arg(detail);
        } else if (old) {
            title = Translation.tr("%1 mode ended").arg(root.nameOf(old));
            body = Translation.tr("What it changed is back as it was.");
        }
        if (title) Quickshell.execDetached(["notify-send", "-a", "ii", title, body]);
    }

    // ---- across restarts of ii -------------------------------------------------------------------------------------
    readonly property string statePath: FileUtils.trimFileProtocol(`${Directories.state}/modes.json`)
    FileView {
        id: stateFile
        path: root.statePath
        printErrors: false
        blockLoading: true
        onLoaded: root.restoreState(stateFile.text())
        onLoadFailed: root.restoreState("")
    }
    function restoreState(text) {
        if (root.loaded) return;
        let s = null;
        try { s = text ? JSON.parse(text) : null; } catch (e) {}
        if (s && s.activeId) {
            root.activeId = s.activeId;
            root.reason = s.reason ?? "";
            root.reasonDetail = s.reasonDetail ?? "";
            root.lastReason = root.reason;
            root.before = s.before ?? null;
            root.applied = s.applied ?? null;
            root.manualId = s.manualId ?? "";
            root.dismissed = s.dismissed ?? {};
            root.reapply = true; // reconcile sets again what does not survive a restart, once the config is read
        } else if (s) {
            root.dismissed = s.dismissed ?? {};
        }
        root.loaded = true;
        Qt.callLater(root.reconcile);
    }
    function save() {
        stateFile.setText(JSON.stringify({ activeId: root.activeId, reason: root.reason, reasonDetail: root.reasonDetail,
            manualId: root.manualId, before: root.before, applied: root.applied, dismissed: root.dismissed }));
    }
}
