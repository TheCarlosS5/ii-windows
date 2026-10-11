pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common

/**
 * ii-windows: optionally, empty desktops don't pile up (bar.workspaces.removeEmptyDesktops, off by
 * default). Hyprland drops a workspace once you leave it empty; here, leaving the LAST desktop while
 * it has no windows asks the fork to close it. Rules (R09):
 *  - Only the last desktop, never desktop 1, never one the user named.
 *  - What is asked is a request, not a command: the fork only acts if that desktop is the one just
 *    left and the list of desktops is unchanged, and `ii-shim vdesk remove-empty` looks again right
 *    before acting (current desktop, order, any app window or one it can't place) and does nothing
 *    when anything differs. Ambiguity means the desktop stays.
 *  - It needs Windows' internal desktop interface. Whether that works is not assumed from the build:
 *    `ii-shim vdesk probe` checks it, and `canRemove` / `limitation` say what it found so the
 *    settings can show it. Nothing is ever replaced by opening Task View.
 */
Singleton {
    id: root
    property int previous: Hyprland.focusedWorkspace?.id ?? 1

    // From `ii-shim vdesk probe`.
    property bool probed: false
    property bool canRemove: false
    property string limitation: Translation.tr("Checking whether this Windows allows it…")
    readonly property bool enabled: Config.options.bar.workspaces.removeEmptyDesktops ?? false

    function load() { // instantiated from shell.qml
        probe.running = true;
        if (Config.ready) root.announceOnce();
    }

    // The cleanup used to be on without being asked for. It is opt-in now: tell people once.
    function announceOnce() {
        const ws = Config.options.bar.workspaces;
        if (ws.removeEmptyDesktopsNoticeShown ?? false) return;
        ws.removeEmptyDesktopsNoticeShown = true;
        Quickshell.execDetached(["notify-send", "-a", "Shell",
            Translation.tr("Empty desktops are no longer closed automatically"),
            Translation.tr("You can turn it back on in Settings > Bar > Workspaces.")]);
    }

    function parseProbe(text) {
        const lines = text.split("\n").map(l => l.trim());
        const find = key => lines.find(l => l.startsWith(key + " "));
        const remove = find("remove");
        const read = find("read");
        root.probed = true;
        root.canRemove = remove === "remove yes";
        if (root.canRemove) {
            root.limitation = "";
        } else if (remove && remove.length > 10) {
            root.limitation = Translation.tr("Not available on this version of Windows: %1").arg(remove.substring(7).replace(/^no:?\s*/, ""));
        } else if (read && read !== "read yes") {
            root.limitation = Translation.tr("Not available on this version of Windows: its virtual desktops could not be read safely.");
        } else {
            root.limitation = Translation.tr("Not available on this version of Windows.");
        }
    }

    Process {
        id: probe
        command: ["ii-shim", "vdesk", "probe"]
        stdout: StdioCollector {
            onStreamFinished: root.parseProbe(text)
        }
    }

    // The shim answers in well under a second. Without an answer (it could not start, Explorer
    // hung), the cleanup stays off and the settings say so.
    Timer {
        interval: 10000
        running: true
        onTriggered: if (!root.probed) root.parseProbe("")
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) root.announceOnce();
        }
    }

    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            const left = root.previous;
            root.previous = Hyprland.focusedWorkspace?.id ?? 1;
            if (!root.enabled || !root.canRemove) return;
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
            if (!root.enabled || !root.canRemove) return;
            // Re-ask everything the 800 ms may have changed; the fork and the shim ask again.
            if (check.left !== Hyprland.workspaces.values.length || check.left === (Hyprland.focusedWorkspace?.id ?? 1)) return;
            if (HyprlandData.windowList.some(w => w.workspace.id === check.left)) return;
            Hyprland.dispatch(`hl.dsp.ii.desktop.dropEmpty({ workspace = ${check.left} })`);
        }
    }
}
