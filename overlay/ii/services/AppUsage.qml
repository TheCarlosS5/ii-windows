pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions

// ii-windows: how often each app is launched, for the "most used" row above the app grid.
// Counts live in Persistent.states.launcher.counts: {"<entry id, lower case>": {"n": launches, "t": last launch, ms}}.
Singleton {
    id: root

    // Half-life of a launch, in days: an app used a lot last year does not beat the one used this week.
    readonly property real halfLifeDays: 14
    readonly property int maxEntries: 200

    function record(entry) {
        if (!entry || !entry.id || !Persistent.ready)
            return;
        const key = entry.id.toLowerCase();
        const counts = Object.assign({}, Persistent.states.launcher.counts ?? {});
        counts[key] = {
            n: (counts[key]?.n ?? 0) + 1,
            t: Date.now()
        };
        // Keep it small: forget the ones not launched for the longest time.
        const keys = Object.keys(counts);
        if (keys.length > root.maxEntries)
            keys.sort((a, b) => counts[a].t - counts[b].t).slice(0, keys.length - root.maxEntries).forEach(k => delete counts[k]);
        Persistent.states.launcher.counts = counts; // reassigned: that is what makes it save
    }

    // Opens a Start menu entry (as the search does) and counts it.
    function launch(entry) {
        if (!entry)
            return;
        root.record(entry);
        if (!entry.runInTerminal)
            entry.execute();
        else
            Quickshell.execDetached(["bash", '-c', `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(entry.command.join(' '))}'`]);
    }

    function clear() {
        Persistent.states.launcher.counts = ({});
    }

    // Launches weighted by how recent they are, best first.
    readonly property var top: {
        // Read so this runs again once the Start menu list is there (it is filled in the background at start).
        const loaded = DesktopEntries.applications.values.length;
        const counts = Persistent.states?.launcher?.counts ?? {};
        const now = Date.now();
        const list = [];
        for (const key in counts) {
            const entry = DesktopEntries.byId(key);
            if (!entry || entry.noDisplay)
                continue;
            const ageDays = (now - (counts[key].t ?? now)) / 86400000;
            list.push({
                entry: entry,
                score: (counts[key].n ?? 1) * Math.pow(0.5, ageDays / root.halfLifeDays)
            });
        }
        list.sort((a, b) => b.score - a.score);
        return list.slice(0, Config.options?.overview?.frequentCount ?? 8).map(x => x.entry);
    }
}
