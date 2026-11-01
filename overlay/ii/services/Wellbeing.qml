pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import "../modules/common/functions/wellbeing_logic.js" as Logic

/**
 * ii-windows (plan 2026-10-31, E11): digital wellbeing, on top of the screen time ii-host keeps (the right panel's
 * "Uso" tab). Kind notices, all local, nothing leaves the PC:
 *   - a daily limit per app ("Llevas 2 h en Brave hoy"), once a day;
 *   - 20-20-20 for the eyes: after every 20 min of use, look at something 6 m away for 20 s (off by default);
 *   - a summary of the week on Sunday evening.
 * Configuración > Sistema > Bienestar.
 */
Singleton {
    id: root
    function load() {}

    readonly property string dir: (Quickshell.env("II_DATA_DIR") || ((Quickshell.env("LOCALAPPDATA") ?? "") + "/ii-windows")).replace(/\\/g, "/") + "/screentime"
    property string todayKey: Logic.dateKey(new Date())
    property var today: null
    property var announced: [] // "exe@date" of the limits already told today
    property int lastBreakAt: -1
    property string weeklyShown: ""
    readonly property var goals: Config.options?.wellbeing?.goals ?? []

    FileView {
        id: todayFile
        path: `${root.dir}/${root.todayKey}.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.today = JSON.parse(text()); } catch (e) { root.today = null; }
            // No check here: at start the translations may not be loaded yet; the minute timer checks.
        }
    }
    FileView { // what was announced survives a restart of ii
        id: stateFile
        path: FileUtils.trimFileProtocol(`${Directories.state}/wellbeing.json`)
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.announced = s.announced ?? [];
                root.lastBreakAt = s.date === root.todayKey ? (s.lastBreakAt ?? -1) : -1;
                root.weeklyShown = s.weeklyShown ?? "";
            } catch (e) {}
        }
    }
    function save() {
        stateFile.setText(JSON.stringify({ date: root.todayKey, announced: root.announced, lastBreakAt: root.lastBreakAt, weeklyShown: root.weeklyShown }));
    }
    function notify(title, body) {
        Quickshell.execDetached(["notify-send", "-a", Translation.tr("Wellbeing"), title, body]);
    }

    Timer {
        interval: 60000
        running: Config.ready
        repeat: true
        onTriggered: {
            const key = Logic.dateKey(new Date());
            if (key !== root.todayKey) {
                root.todayKey = key;
                root.announced = [];
                root.lastBreakAt = -1;
            }
            root.check();
        }
    }
    function check() {
        if (!Config.ready || !root.today) return;
        let changed = false;
        for (const g of Logic.goalsPassed(root.today, root.goals, root.announced, root.todayKey)) {
            root.notify(Translation.tr("%1 today on %2").arg(Logic.hoursText(g.used * 60)).arg(g.name),
                Translation.tr("Your daily limit for it is %1. Maybe time for a break?").arg(Logic.hoursText(g.minutes * 60)));
            root.announced = root.announced.concat([g.exe + "@" + root.todayKey]);
            changed = true;
        }
        const every = (Config.options?.wellbeing?.eyeEvery ?? 20) * 60;
        if ((Config.options?.wellbeing?.eyeBreaks ?? false) && Logic.eyeBreakDue(root.today.total ?? 0, root.lastBreakAt, every)) {
            root.notify(Translation.tr("Rest your eyes"), Translation.tr("Look at something about 6 meters away for 20 seconds."));
            root.lastBreakAt = root.today.total ?? 0;
            changed = true;
        }
        const now = new Date();
        if ((Config.options?.wellbeing?.weekly ?? true) && now.getDay() === 0 && now.getHours() >= 19 && root.weeklyShown !== root.todayKey) {
            root.weeklyShown = root.todayKey;
            weekLoader.start();
            changed = true;
        }
        if (changed) root.save();
    }

    // The week's files, read only on Sunday evening.
    QtObject {
        id: weekLoader
        property var days: []
        property int pending: 0
        function start() {
            weekLoader.days = [];
            weekLoader.pending = 7;
            weekFiles.model = Array.from({ length: 7 }, (_, i) => Logic.dateKey(new Date(Date.now() - i * 86400000)));
        }
        function done(day) {
            if (day) weekLoader.days = weekLoader.days.concat([day]);
            weekLoader.pending -= 1;
            if (weekLoader.pending > 0) return;
            const w = Logic.weekSummary(weekLoader.days);
            weekFiles.model = [];
            if (w.days === 0) return;
            root.notify(Translation.tr("Your week: %1 in front of the screen").arg(Logic.hoursText(w.total)),
                Translation.tr("%1 a day on average. Most: %2.").arg(Logic.hoursText(w.average))
                    .arg(w.top.map(t => `${t.name} (${Logic.hoursText(t.seconds)})`).join(", ")));
        }
    }
    Instantiator {
        id: weekFiles
        model: []
        delegate: FileView {
            required property string modelData
            path: `${root.dir}/${modelData}.json`
            printErrors: false
            onLoaded: {
                let d = null;
                try { d = JSON.parse(text()); } catch (e) {}
                weekLoader.done(d);
            }
            onLoadFailed: weekLoader.done(null)
        }
    }
}
