pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.modules.common

/**
 * ii-windows (plan 2026-10-31, D2): the time the desktop widgets show. The same as DateTime, but its clock stops
 * while apps cover every screen (DesktopCover.allCovered), so a clock with seconds does not repaint the wallpaper
 * window every second behind a maximized browser. It runs again, already on the right time, once the desktop shows,
 * and always on the lock screen.
 */
Singleton {
    id: root
    property var clock: SystemClock {
        enabled: !DesktopCover.allCovered || GlobalStates.screenLocked
        precision: DateTime.clock.precision
    }
    property string time: Qt.locale().toString(root.clock.date, Config.options?.time.format ?? "hh:mm")
    property string longDate: Qt.locale().toString(root.clock.date, Config.options?.time.dateFormat ?? "dddd, dd/MM")
}
