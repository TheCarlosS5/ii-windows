pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.modules.common

/**
 * ii-windows: empty desktops don't pile up. Hyprland drops a workspace once you leave it empty;
 * here, leaving the LAST desktop while it has no windows removes it (only the last one, so the
 * numbers of the others never change, and never desktop 1). The fork only does it when Windows
 * allows removing a desktop without visiting it (Windows 11 24H2+), so nothing flickers.
 * Option: bar.workspaces.removeEmptyDesktops.
 */
Singleton {
    id: root
    property int previous: Hyprland.focusedWorkspace?.id ?? 1

    function load() {} // instantiated from shell.qml

    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            const left = root.previous;
            root.previous = Hyprland.focusedWorkspace?.id ?? 1;
            if (!(Config.options.bar.workspaces.removeEmptyDesktops ?? true)) return;
            if (left <= 1 || left === root.previous || left !== Hyprland.workspaces.values.length) return;
            // Give the window list a moment: a window moved along with the switch counts.
            check.left = left;
            check.restart();
        }
    }

    Timer {
        id: check
        property int left: 0
        interval: 800
        onTriggered: {
            if (check.left !== Hyprland.workspaces.values.length || check.left === (Hyprland.focusedWorkspace?.id ?? 1)) return;
            if (HyprlandData.windowList.some(w => w.workspace.id === check.left)) return;
            Hyprland.dispatch(`hl.dsp.ii.desktop.dropEmpty({ workspace = ${check.left} })`);
        }
    }
}
