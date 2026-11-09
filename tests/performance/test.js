// Exercise the production QML functions with synthetic native-window events.
// node tests/performance/test.js
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert/strict");
const repo = path.resolve(__dirname, "../..");
function functions(file, state, bindings = {}) {
    const text = fs.readFileSync(path.join(repo, file), "utf8");
    const context = vm.createContext({ root: state, ...bindings });
    for (const key of Object.keys(state)) Object.defineProperty(context, key, {
        get: () => state[key], set: value => state[key] = value, configurable: true,
    });
    for (const match of text.matchAll(/^    function (\w+)\([^\n]*\) \{/gm)) {
        let end = match.index + match[0].length, depth = 1;
        while (depth && end < text.length) {
            if (text[end] === "{") depth++;
            if (text[end] === "}") depth--;
            end++;
        }
        vm.runInContext(text.slice(match.index, end), context);
        state[match[1]] = context[match[1]];
    }
    return state;
}
let geometryReads = 0;
const monitor = { id: 0, name: "main", lastIpcObject: { id: 0, scale: 1 } };
const hyprland = { monitors: { values: [monitor] }, workspaces: { values: [{ id: 1, name: "1" }, { id: 2, name: "2" }] },
    focusedMonitor: monitor, focusedWorkspace: { id: 1 }, monitorFor: () => monitor };
function window(address, desktop = 0) {
    return { HyprlandToplevel: { address }, desktop, title: address, appId: "app", screens: [{}],
        pid: 1, executable: "app.exe", minimized: false, fullscreen: false, activated: false,
        rect: { x: 10, y: 20, width: 800, height: 600 },
        get geometry() { geometryReads++; return this.rect; } };
}
const a = window("a"), b = window("b", 1);
const manager = { toplevels: { values: [a, b] } };
let queued = 0;
const root = functions("overlay/ii/services/HyprlandData.qml", {
    windowList: [], windowByAddress: {}, addresses: [], monitors: [], workspaces: [], workspaceIds: [], workspaceById: {},
    dirtyWindows: {}, allWindowsDirty: true, monitorsDirty: true, workspacesDirty: true, windowGeometries: {},
}, { Hyprland: hyprland, ToplevelManager: manager, rebuildSoon: { running: false, start() { queued++; } },
    geometryFactory: { createObject(parent, data) { return { ...data, destroy() {} }; } } });
root.rebuild();
assert.equal(geometryReads, 2);
const originalB = root.windowByAddress["0xb"];
const originalA = root.windowByAddress["0xa"];
a.title = "new title";
root.invalidateWindow(a);
root.rebuild();
assert.equal(geometryReads, 3, "a title event reads only the affected window");
assert.equal(root.windowByAddress["0xb"], originalB, "the other window retains identity");
assert.equal(root.windowByAddress["0xa"].title, "new title");
assert.notEqual(root.windowByAddress["0xa"], originalA);
const stable = root.windowList;
root.rebuild();
assert.equal(root.windowList, stable, "an unchanged rebuild publishes no window list");
assert.equal(geometryReads, 3, "an unchanged rebuild reads no geometry");
a.rect.width = 1000; a.minimized = true; a.fullscreen = true; a.desktop = 1;
root.invalidateWindow(a); root.rebuild();
assert.equal(root.windowByAddress["0xa"].size[0], 1000);
assert.equal(root.windowByAddress["0xa"].workspace.id, 2);
assert.equal(root.workspaceById[2].windows, 2);
assert.equal(root.workspaceById[2].hasfullscreen, false, "a minimized fullscreen window does not cover its desktop");
a.minimized = false; a.activated = true;
root.invalidateWindow(a); root.rebuild();
assert.equal(root.workspaceById[2].hasfullscreen, true);
assert.equal(root.workspaceById[2].lastwindow, "0xa");
a.desktop = -1; hyprland.focusedWorkspace.id = 2;
monitor.lastIpcObject.scale = 2;
root.invalidateAll(); root.rebuild();
assert.equal(root.windowByAddress["0xa"].workspace.id, 2, "a pinned window follows the current desktop");
assert.equal(root.windowByAddress["0xa"].size[0], 500, "monitor scale invalidates geometry");
manager.toplevels.values = [b];
root.invalidateAll(); root.rebuild();
assert.equal(root.addresses.length, 1);
assert.equal(root.windowByAddress["0xa"], undefined, "closed windows leave no cached client");
b.activated = false;
const c = window("c"); manager.toplevels.values = [c, b];
root.invalidateAll(); root.rebuild();
assert.equal(root.windowByAddress["0xb"].focusHistoryID, 2, "membership changes refresh list positions");

// Forty windows and eight desktops: a drag updates only observable geometry, without list/workspace publications.
manager.toplevels.values = Array.from({ length: 40 }, (_, i) => window(`drag${i}`, i % 8));
hyprland.workspaces.values = Array.from({ length: 8 }, (_, i) => ({ id: i + 1, name: `${i + 1}` }));
root.invalidateAll(); root.rebuild();
const beforeDrag = { list: root.windowList, byAddress: root.windowByAddress, workspaces: root.workspaces, byId: root.workspaceById };
const dragged = manager.toplevels.values[0];
const client = root.windowList[0];
for (let i = 0; i < 90; i++) {
    dragged.rect.x = i * 2;
    root.invalidateWindow(dragged); root.rebuild();
}
assert.equal(root.windowList, beforeDrag.list);
assert.equal(root.windowByAddress, beforeDrag.byAddress);
assert.equal(root.workspaces, beforeDrag.workspaces);
assert.equal(root.workspaceById, beforeDrag.byId);
assert.equal(client.at[0], 89, "geometry reaches the existing client at the current 200% scale");
dragged.desktop = 3;
root.invalidateWindow(dragged); root.rebuild();
assert.notEqual(root.windowList, beforeDrag.list, "desktop membership is still published");
assert.equal(root.windowByAddress[client.address].workspace.id, 4);

const spectrum = functions("overlay/ii/services/AudioSpectrum.qml", { consumers: [], demand: false }, { demandSoon: { restart() {} } });
const left = {}, right = {}, popup = {};
spectrum.setDemand(left, true); spectrum.setDemand(right, true); spectrum.setDemand(left, true);
spectrum.settleDemand();
assert.equal(spectrum.consumers.length, 2, "a subscriber registers only once");
spectrum.setDemand(left, false);
assert.equal(spectrum.consumers.length, 1, "covering one monitor preserves the other subscriber");
spectrum.setDemand(popup, true); spectrum.setDemand(right, false);
assert.equal(spectrum.consumers.length, 1, "handoff to the media popup preserves demand");
spectrum.setDemand(popup, false);
assert.equal(spectrum.consumers.length, 0, "destroying the final consumer stops demand");
assert.equal(spectrum.demand, true, "an outgoing subscriber does not stop the producer synchronously");
spectrum.setDemand(left, true); spectrum.settleDemand();
assert.equal(spectrum.demand, true, "the incoming subscriber preserves capture through a handoff");
spectrum.setDemand(left, false); spectrum.settleDemand();
assert.equal(spectrum.demand, false, "no remaining subscribers stop capture after coalescing");
console.log("PASS: incremental window model, workspace/scale/focus changes and shared spectrum subscriptions");
