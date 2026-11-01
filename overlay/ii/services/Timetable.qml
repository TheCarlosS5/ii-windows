pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions
import "../modules/common/functions/timetable_logic.js" as Logic

/**
 * ii-windows (plan 2026-10-31, E3): the class timetable (for students, no account or internet needed). A week of
 * classes (Config.options.timetable.classes: subject, day, from/to, room, Meet/Teams link) edited in Configuración >
 * Servicios > Horario de clases. N minutes before each one (10 by default) a notice says so, with "Unirme" when it has
 * a link: the button reaches ii-host (`class-join`), which presses the global shortcut classJoin here, and the link of
 * that class opens. The left panel's Hoy tab shows the day.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.timetable?.enable ?? true
    readonly property var classes: (Config.options?.timetable?.classes ?? []).filter(c => Logic.valid(c))
    readonly property int remindMinutes: Config.options?.timetable?.remindMinutes ?? 10
    property int tick: 0
    readonly property var day: { root.tick; return Logic.today(root.classes, new Date()); }
    property var reminded: []
    property var lastReminded: null // the class "Unirme" opens
    function load() {} // shell.qml calls it at start so reminders run without the panel being opened

    function joinLink(c) {
        return Logic.joinLink(c);
    }
    function join(c) {
        const link = Logic.joinLink(c);
        if (link) Qt.openUrlExternally(link);
    }
    function newId() {
        return Date.now().toString(36) + Math.floor(Math.random() * 1000).toString(36);
    }

    Timer {
        interval: 30000
        running: Config.ready
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.tick += 1;
            if (!root.enabled) return;
            const now = new Date();
            const kept = Logic.keepReminded(root.reminded, now);
            for (const c of Logic.due(root.classes, now, root.remindMinutes, kept)) {
                kept.push(c.id + "@" + Logic.dateKey(now));
                root.remind(c, now);
            }
            if (kept.length !== root.reminded.length) {
                root.reminded = kept;
                stateFile.setText(JSON.stringify({ reminded: kept }));
            }
        }
    }
    function remind(c, now) {
        root.lastReminded = c;
        const left = Logic.minutesOf(c.from) - (now.getHours() * 60 + now.getMinutes());
        const title = left > 0 ? Translation.tr("%1 in %2 min").arg(c.subject).arg(left) : Translation.tr("%1 starts now").arg(c.subject);
        const body = [`${c.from}–${c.to}`, c.room ?? ""].filter(x => x).join(" · ");
        const command = ["notify-send", "-a", Translation.tr("Timetable")];
        if (Logic.joinLink(c)) command.push("--ii-button", `${Translation.tr("Join")}=class-join`);
        Quickshell.execDetached(command.concat([title, body]));
    }
    GlobalShortcut {
        name: "classJoin"
        description: "Opens the link of the class ii just reminded of (the notice's Join button)"
        onPressed: root.join(root.lastReminded ?? root.day.current ?? root.day.next)
    }

    FileView { // what was already reminded today survives a restart of ii
        id: stateFile
        path: FileUtils.trimFileProtocol(`${Directories.state}/timetable.json`)
        printErrors: false
        blockLoading: true // read before the first check
        onLoaded: {
            try { root.reminded = Logic.keepReminded(JSON.parse(stateFile.text()).reminded ?? [], new Date()); } catch (e) {}
        }
    }
}
