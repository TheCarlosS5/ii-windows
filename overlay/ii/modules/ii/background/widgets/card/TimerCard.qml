import QtQuick

// ii's pomodoro timer and stopwatch (sidebar) on the desktop: the same running timers.
CardWidget {
    configEntryName: "timer"
    cardWidth: 360
    cardHeight: 360
    source: Qt.resolvedUrl("../../../sidebarRight/pomodoro/PomodoroWidget.qml")
}
