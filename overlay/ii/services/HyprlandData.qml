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

    // Same entry points as upstream; all of them rebuild from live data.
    function updateWindowList() { rebuild(); }
    function updateLayers() {}
    function updateMonitors() { rebuild(); }
    function updateWorkspaces() { rebuild(); }
    function updateAll() { rebuild(); }

    function monitorIdFor(toplevel) {
        const screen = toplevel.screens?.[0];
        const monitor = screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor;
        return monitor?.id ?? 0;
    }

    function rebuild() {
        const monitorObjects = Hyprland.monitors.values;
        root.monitors = monitorObjects.map(m => m.lastIpcObject);
        const monitorById = {};
        for (const m of root.monitors) monitorById[m.id] = m;

        const toplevels = ToplevelManager.toplevels.values;
        const current = Hyprland.focusedWorkspace?.id ?? 1;
        const list = [];
        for (let i = 0; i < toplevels.length; ++i) {
            const t = toplevels[i];
            const monitorId = root.monitorIdFor(t);
            const scale = monitorById[monitorId]?.scale ?? 1;
            const g = t.geometry;
            // A window on all desktops (or of unknown desktop) shows on the current one.
            const workspaceId = (t.desktop ?? -1) >= 0 ? t.desktop + 1 : current;
            list.push({
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
                "xwayland": false,
                "pinned": false,
                "fullscreen": t.fullscreen ? 2 : 0,
                "fullscreenClient": t.fullscreen ? 2 : 0,
                "grouped": [],
                "tags": [],
                "swallowing": "0x0",
                "focusHistoryID": t.activated ? 0 : i + 1,
                "inhibitingIdle": false,
            });
        }
        root.windowList = list;
        const byAddress = {};
        for (const w of list) byAddress[w.address] = w;
        root.windowByAddress = byAddress;
        root.addresses = list.map(w => w.address);

        const focused = Hyprland.focusedMonitor;
        const workspaces = Hyprland.workspaces.values.map(w => {
            const windows = list.filter(win => win.workspace.id === w.id);
            const last = windows.find(win => win.focusHistoryID === 0) ?? windows[0];
            return {
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
        });
        root.workspaces = workspaces;
        root.workspaceIds = workspaces.map(w => w.id);
        const byId = {};
        for (const w of workspaces) byId[w.id] = w;
        root.workspaceById = byId;
        root.activeWorkspace = byId[current] ?? workspaces[0] ?? null;
    }

    Component.onCompleted: rebuild()

    // Window list changes (open/close/activate) rebuild at once; geometry and titles are
    // picked up by a light periodic refresh.
    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() { rebuildSoon.restart(); }
    }
    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() { rebuildSoon.restart(); }
    }
    Connections {
        target: Hyprland
        function onFocusedMonitorChanged() { rebuildSoon.restart(); }
        function onFocusedWorkspaceChanged() { rebuildSoon.restart(); }
    }
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { rebuildSoon.restart(); }
    }
    Timer {
        id: rebuildSoon
        interval: 30
        onTriggered: root.rebuild()
    }
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.rebuild()
    }
}
