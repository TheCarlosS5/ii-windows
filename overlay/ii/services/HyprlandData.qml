pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * ii-windows: same API as illogical-impulse's HyprlandData, but built from the Windows
 * window list (Quickshell.Wayland ToplevelManager) and monitors instead of `hyprctl -j`.
 * Objects keep hyprctl's JSON shape so the overview, dock and bar work unchanged.
 * Workspaces are Windows' virtual desktops (Hyprland.workspaces, id = desktop number), and each
 * window is on its desktop's workspace.
 */
Singleton {
    id: root
    property var windowList: []
    property var addresses: []
    property var windowByAddress: ({})
    property var workspaces: []
    property var workspaceIds: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var layers: ({})
    property var dirtyWindows: ({})
    property bool allWindowsDirty: true
    property bool monitorsDirty: true

    function queueRebuild() {
        if (!rebuildSoon.running) rebuildSoon.start();
    }
    function invalidateAll() {
        allWindowsDirty = true;
        monitorsDirty = true;
        queueRebuild();
    }
    function invalidateWindow(toplevel) {
        if (toplevel) dirtyWindows[`0x${toplevel.HyprlandToplevel.address}`] = true;
        queueRebuild();
    }
    function sameWindow(a, b) {
        return a && a.hidden === b.hidden && a.at[0] === b.at[0] && a.at[1] === b.at[1]
            && a.size[0] === b.size[0] && a.size[1] === b.size[1] && a.workspace.id === b.workspace.id
            && a.monitor === b.monitor && a.class === b.class && a.title === b.title
            && a.pid === b.pid && a.executable === b.executable
            && a.fullscreen === b.fullscreen && a.focusHistoryID === b.focusHistoryID;
    }
    function sameWorkspace(a, b) {
        return a && Object.keys(b).every(key => a[key] === b[key]);
    }

    // Convenient stuff (unchanged from upstream)
    function toplevelsForWorkspace(workspace) {
        return ToplevelManager.toplevels.values.filter(toplevel => {
            const address = `0x${toplevel.HyprlandToplevel?.address}`;
            var win = HyprlandData.windowByAddress[address];
            return win?.workspace?.id === workspace;
        })
    }
    function hyprlandClientsForWorkspace(workspace) {
        return root.windowList.filter(win => win.workspace.id === workspace);
    }
    function clientForToplevel(toplevel) {
        if (!toplevel || !toplevel.HyprlandToplevel) {
            return null;
        }
        const address = `0x${toplevel?.HyprlandToplevel?.address}`;
        return root.windowByAddress[address];
    }
    function biggestWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = HyprlandData.windowList.filter(w => w.workspace.id == workspaceId);
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
    }

    // Preserve upstream entry points, coalescing bursts into one publication.
    function updateWindowList() { invalidateAll(); }
    function updateLayers() {}
    function updateMonitors() { invalidateAll(); }
    function updateWorkspaces() { queueRebuild(); }
    function updateAll() { invalidateAll(); }

    function monitorIdFor(toplevel) {
        const screen = toplevel.screens?.[0];
        const monitor = screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor;
        return monitor?.id ?? 0;
    }

    function rebuild() {
        const monitors = root.monitorsDirty ? Hyprland.monitors.values.map(m => m.lastIpcObject) : root.monitors;
        const monitorById = {};
        for (const m of monitors) monitorById[m.id] = m;

        const toplevels = ToplevelManager.toplevels.values;
        const current = Hyprland.focusedWorkspace?.id ?? 1;
        const list = [];
        for (let i = 0; i < toplevels.length; ++i) {
            const t = toplevels[i];
            const address = `0x${t.HyprlandToplevel.address}`;
            const previous = root.windowByAddress[address];
            if (previous && !root.allWindowsDirty && !root.dirtyWindows[address]) {
                list.push(previous);
                continue;
            }
            const monitorId = root.monitorIdFor(t);
            const scale = monitorById[monitorId]?.scale ?? 1;
            const g = t.geometry;
            // A window on all desktops (or of unknown desktop) shows on the current one.
            const workspaceId = (t.desktop ?? -1) >= 0 ? t.desktop + 1 : current;
            const next = {
                "address": `0x${t.HyprlandToplevel.address}`,
                "mapped": true,
                "hidden": t.minimized,
                "at": [Math.round(g.x / scale), Math.round(g.y / scale)],
                "size": [Math.round(g.width / scale), Math.round(g.height / scale)],
                "workspace": { "id": workspaceId, "name": `${workspaceId}` },
                "floating": true,
                "pseudo": false,
                "monitor": monitorId,
                "class": t.appId,
                "title": t.title,
                "initialClass": t.appId,
                "initialTitle": t.title,
                "pid": t.pid,
                "executable": t.executable ?? "", // ii-windows: for the program's own icon
                "xwayland": false,
                "pinned": false,
                "fullscreen": t.fullscreen ? 2 : 0,
                "fullscreenClient": t.fullscreen ? 2 : 0,
                "grouped": [],
                "tags": [],
                "swallowing": "0x0",
                "focusHistoryID": t.activated ? 0 : i + 1,
                "inhibitingIdle": false,
            };
            list.push(root.sameWindow(previous, next) ? previous : next);
        }
        const focused = Hyprland.focusedMonitor;
        const workspaces = Hyprland.workspaces.values.map(w => {
            const windows = list.filter(win => win.workspace.id === w.id);
            const last = windows.find(win => win.focusHistoryID === 0) ?? windows[0];
            const next = {
                "id": w.id,
                "name": w.name,
                "monitor": focused?.name ?? "",
                "monitorID": focused?.id ?? 0,
                "windows": windows.length,
                "hasfullscreen": windows.some(win => win.fullscreen > 0 && !win.hidden),
                "lastwindow": last?.address ?? "0x0",
                "lastwindowtitle": last?.title ?? "",
                "ispersistent": true,
            };
            const previous = root.workspaceById[w.id];
            return root.sameWorkspace(previous, next) ? previous : next;
        });
        const windowsChanged = list.length !== root.windowList.length || list.some((win, i) => win !== root.windowList[i]);
        const membershipChanged = list.length !== root.addresses.length || list.some((win, i) => win.address !== root.addresses[i]);
        if (root.monitorsDirty) root.monitors = monitors;
        root.monitorsDirty = false;
        root.allWindowsDirty = false;
        root.dirtyWindows = ({});
        if (windowsChanged) {
            root.windowList = list;
            const byAddress = {};
            for (const w of list) byAddress[w.address] = w;
            root.windowByAddress = byAddress;
        }
        if (membershipChanged) root.addresses = list.map(w => w.address);
        if (workspaces.length !== root.workspaces.length || workspaces.some((w, i) => w !== root.workspaces[i]))
            root.workspaces = workspaces;
        const workspaceIds = workspaces.map(w => w.id);
        if (workspaceIds.length !== root.workspaceIds.length || workspaceIds.some((id, i) => id !== root.workspaceIds[i]))
            root.workspaceIds = workspaceIds;
        const byId = {};
        for (const w of workspaces) byId[w.id] = w;
        root.workspaceById = byId;
        root.activeWorkspace = byId[current] ?? workspaces[0] ?? null;
    }

    Component.onCompleted: rebuild()

    // Every field used above has a fork signal. No periodic rebuilding or whole-model JSON serialization.
    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() { root.invalidateAll(); }
    }
    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() { root.queueRebuild(); }
    }
    Connections {
        target: Hyprland
        function onFocusedMonitorChanged() { root.invalidateAll(); }
        function onFocusedWorkspaceChanged() { root.invalidateAll(); }
    }
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { root.queueRebuild(); }
    }
    Connections {
        target: Hyprland.monitors
        function onValuesChanged() { root.invalidateAll(); }
    }
    Instantiator {
        model: Hyprland.monitors
        delegate: Connections {
            required property var modelData
            target: modelData
            function onLastIpcObjectChanged() { root.invalidateAll(); }
        }
    }
    Instantiator {
        model: Hyprland.workspaces
        delegate: Connections {
            required property var modelData
            target: modelData
            function onNameChanged() { root.queueRebuild(); }
        }
    }
    Instantiator {
        model: ToplevelManager.toplevels
        delegate: Connections {
            required property var modelData
            target: modelData
            function onDesktopChanged() { root.invalidateWindow(modelData); }
            function onTitleChanged() { root.invalidateWindow(modelData); }
            function onAppIdChanged() { root.invalidateWindow(modelData); }
            function onGeometryChanged() { root.invalidateWindow(modelData); }
            function onScreensChanged() { root.invalidateWindow(modelData); }
            function onMinimizedChanged() { root.invalidateWindow(modelData); }
            function onFullscreenChanged() { root.invalidateWindow(modelData); }
            function onActivatedChanged() { root.invalidateWindow(modelData); }
        }
    }
    Timer {
        id: rebuildSoon
        interval: 30
        onTriggered: root.rebuild()
    }
}
