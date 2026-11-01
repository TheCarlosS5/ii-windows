pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * ii-windows: which screens have their desktop covered by an app (maximized or fullscreen,
 * not minimized, on the current virtual desktop). The wallpaper window repaints whole for any
 * change in it, even when no one can see it, so desktop widgets pause their animations, the
 * spectrum and per-second timers on covered screens.
 */
Singleton {
    id: root
    property var coveredScreens: []
    // Every screen covered: nothing of the desktop can be seen (DesktopTime stops its clock).
    readonly property bool allCovered: Quickshell.screens.length > 0
        && Quickshell.screens.every(s => root.coveredScreens.includes(s.name))

    function covered(screenName: string): bool {
        return root.coveredScreens.includes(screenName);
    }

    function update() {
        const current = (Hyprland.focusedWorkspace?.id ?? 1) - 1;
        const names = [];
        for (const t of ToplevelManager.toplevels.values) {
            if (t.minimized || !(t.maximized || t.fullscreen)) continue;
            // On another desktop (-1: all desktops or unknown counts as here).
            if ((t.desktop ?? -1) >= 0 && t.desktop !== current) continue;
            for (const s of (t.screens ?? [])) {
                if (s?.name && !names.includes(s.name)) names.push(s.name);
            }
        }
        names.sort();
        if (names.join("\n") !== root.coveredScreens.join("\n")) root.coveredScreens = names;
    }

    // ii-windows (plan 2026-10-31, D2.3): on each window's own changes (maximize, minimize, fullscreen, screen,
    // desktop), no more checking every second. Several changes at once make one update.
    property bool updateQueued: false
    function queueUpdate() {
        if (root.updateQueued) return;
        root.updateQueued = true;
        Qt.callLater(() => {
            root.updateQueued = false;
            root.update();
        });
    }
    Instantiator {
        model: ToplevelManager.toplevels
        delegate: Connections {
            required property var modelData
            target: modelData
            ignoreUnknownSignals: true
            function onMaximizedChanged() { root.queueUpdate(); }
            function onMinimizedChanged() { root.queueUpdate(); }
            function onFullscreenChanged() { root.queueUpdate(); }
            function onScreensChanged() { root.queueUpdate(); }
            function onDesktopChanged() { root.queueUpdate(); }
        }
    }
    Connections {
        target: Quickshell
        function onScreensChanged() { root.queueUpdate(); }
    }
    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() { root.update(); }
    }
    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() { root.update(); }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() { root.update(); }
    }
    Component.onCompleted: update()
}
