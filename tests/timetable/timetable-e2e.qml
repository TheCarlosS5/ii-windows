//@ pragma UseQApplication
import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.ii.sidebarLeft
import qs.services

// Plan 2026-10-31, E3 end to end: a class that starts in 5 minutes (with a Meet link) is written into the config; the
// Hoy tab shows it and the reminder arrives at the notification server with its Join button (command class-join).
// tools/sandbox/tests/test-timetable.ps1 backs up config.json and puts it back.
ShellRoot {
    id: root
    property int step: 0
    Component.onCompleted: { Notifications.silent; Timetable.load(); }
    FloatingWindow {
        implicitWidth: 420
        implicitHeight: 620
        color: Appearance.colors.colLayer1
        title: "ii-today-probe"
        Today { anchors.fill: parent }
    }
    Timer {
        interval: 1000
        running: Config.ready
        repeat: true
        onTriggered: {
            root.step += 1;
            if (root.step === 1) {
                const now = new Date(Date.now() + 5 * 60000);
                const hh = String(now.getHours()).padStart(2, "0"), mm = String(now.getMinutes()).padStart(2, "0");
                const end = new Date(now.getTime() + 3600000);
                Config.options.timetable.enable = true;
                Config.options.timetable.remindMinutes = 10;
                Config.options.timetable.classes = [{ id: "probe", subject: "Programación", day: now.getDay(), from: `${hh}:${mm}`,
                    to: `${String(end.getHours()).padStart(2, "0")}:${String(end.getMinutes()).padStart(2, "0")}`, room: "Aula virtual",
                    link: "https://meet.google.com/abc-defg-hij" }];
            }
            if (root.step === 40) {
                const n = Notifications.list.find(x => x.summary.indexOf("Programación") >= 0);
                console.log("TT next=" + (Timetable.day.next?.subject ?? "") + " minutes=" + Timetable.day.minutesToNext
                    + " notice=" + (n ? n.summary : "none") + " actions=" + (n ? JSON.stringify(n.actions.map(a => a.identifier + ":" + a.text)) : "[]"));
                Qt.quit();
            }
        }
    }
}
