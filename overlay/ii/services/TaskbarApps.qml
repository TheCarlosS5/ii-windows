pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

// ii-windows: replaces upstream's TaskbarApps. Pinned apps and open windows are merged by a canonical key.
//
// On Windows the same app has two spellings: the pin is the Start menu entry's id (often an AppUserModelID such
// as "me.paolino.zapfast"), while the window only knows its exe ("zapfast") when the app does not set an
// AppUserModelID on the window. Comparing the two strings left a pinned icon plus a second one for the
// running window. canonicalId() maps both to the Start menu entry's id.
Singleton {
    id: root

    // startupClass (lower case) -> ids of the Start menu entries that have it
    readonly property var classIndex: {
        const idx = {};
        for (const e of DesktopEntries.applications.values) {
            const c = (e.startupClass ?? "").toLowerCase();
            if (c === "")
                continue;
            (idx[c] = idx[c] ?? []).push(e.id);
        }
        return idx;
    }

    function canonicalId(id) {
        if (!id)
            return "";
        const byId = DesktopEntries.byId(id);
        if (byId)
            return byId.id.toLowerCase();
        // Only when the class belongs to ONE entry: Squirrel's Update.exe or chrome.exe (PWAs) are shared.
        const ids = root.classIndex[id.toLowerCase()];
        if (ids && ids.length === 1)
            return ids[0].toLowerCase();
        return id.toLowerCase();
    }

    function isPinned(appId) {
        const key = root.canonicalId(appId);
        return Config.options.dock.pinnedApps.some(id => root.canonicalId(id) === key);
    }

    function togglePin(appId) {
        const key = root.canonicalId(appId);
        if (root.isPinned(appId)) {
            Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.filter(id => root.canonicalId(id) !== key);
        } else {
            Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.concat([DesktopEntries.byId(appId)?.id ?? appId]);
        }
    }

    // Entry objects are kept between recalculations (a plain JS object, NOT a property: writing a property
    // that the binding below reads would loop): the dock only recreates the icons of apps that appear or go.
    readonly property var entryCache: ({
            map: {}
        })

    property list<var> apps: {
        const info = new Map();

        // Pinned apps first, in the order of the config
        for (const appId of Config.options?.dock.pinnedApps ?? []) {
            const key = root.canonicalId(appId);
            if (key !== "" && !info.has(key))
                info.set(key, {
                    pinned: true,
                    toplevels: []
                });
        }

        // Open windows
        const ignoredRegexStrings = Config.options?.dock.ignoredAppRegexes ?? [];
        const ignoredRegexes = ignoredRegexStrings.map(pattern => new RegExp(pattern, "i"));
        for (const toplevel of ToplevelManager.toplevels.values) {
            if (ignoredRegexes.some(re => re.test(toplevel.appId)))
                continue;
            const key = root.canonicalId(toplevel.appId);
            if (!info.has(key))
                info.set(key, {
                    pinned: false,
                    toplevels: []
                });
            info.get(key).toplevels.push(toplevel);
        }

        const previous = root.entryCache.map;
        const next = {};
        function entryFor(key, value) {
            let entry = previous[key];
            if (entry) {
                entry.toplevels = value.toplevels;
                entry.pinned = value.pinned;
            } else {
                entry = appEntryComp.createObject(null, {
                    appId: key,
                    toplevels: value.toplevels,
                    pinned: value.pinned
                });
            }
            next[key] = entry;
            return entry;
        }

        const values = [];
        let separatorAdded = false;
        let anyPinned = false;
        for (const [key, value] of info)
            if (value.pinned)
                anyPinned = true;
        for (const [key, value] of info) {
            // A separator only when there is something on both sides of it
            if (!value.pinned && anyPinned && !separatorAdded) {
                values.push(entryFor("SEPARATOR", {
                    pinned: false,
                    toplevels: []
                }));
                separatorAdded = true;
            }
            values.push(entryFor(key, value));
        }

        for (const key in previous)
            if (!(key in next)) {
                const gone = previous[key];
                Qt.callLater(() => gone.destroy());
            }
        root.entryCache.map = next;
        return values;
    }

    component TaskbarAppEntry: QtObject {
        id: wrapper
        required property string appId
        property list<var> toplevels
        property bool pinned
    }
    Component {
        id: appEntryComp
        TaskbarAppEntry {}
    }
}
