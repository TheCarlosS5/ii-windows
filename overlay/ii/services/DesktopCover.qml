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

    // Maximize/restore has no list-wide signal: a light check each second, plus at once on
    // focus and desktop changes.
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.update()
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
