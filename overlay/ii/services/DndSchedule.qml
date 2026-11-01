pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import "../modules/common/functions/modes_logic.js" as Logic

/**
 * ii-windows (plan 2026-10-31, E12): No molestar at its hours (Configuración > Paneles > No molestar). It is turned on
 * once when the hours begin and off when they end, only if it is still on: turned off by hand meanwhile, it stays off
 * until the next time. The hours may cross midnight (22:00–07:00).
 */
Singleton {
    id: root
    function load() {}
    property string appliedFor: "" // the start (date + time) of the hours it turned No molestar on for
    readonly property var schedule: Config.options?.notifications?.dnd ?? null

    Timer {
        interval: 30000
        running: Config.ready
        repeat: true
        triggeredOnStart: true
        onTriggered: root.check()
    }
    function startKey(now) { // which stretch of hours we are in: the date it began
        const s = root.schedule;
        const from = Logic.minutesOf(s.from), to = Logic.minutesOf(s.to);
        const t = now.getHours() * 60 + now.getMinutes();
        const began = from > to && t < to ? new Date(now.getTime() - 86400000) : now;
        return `${began.getFullYear()}-${began.getMonth() + 1}-${began.getDate()} ${s.from}`;
    }
    function check() {
        const s = root.schedule;
        if (!s) return;
        const inside = Logic.inSchedule({ schedule: s }, new Date());
        if (inside) {
            const key = root.startKey(new Date());
            if (root.appliedFor !== key) {
                root.appliedFor = key;
                if (!Notifications.silent) Notifications.silent = true;
            }
        } else if (root.appliedFor !== "") {
            root.appliedFor = "";
            if (Notifications.silent && Notifications.silentUntil === 0) Notifications.silent = false;
        }
    }
}
