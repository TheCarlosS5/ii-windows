"""P11: timers measure real time, and only refresh what can be seen.

TimerService (pomodoro + stopwatch) already stores timestamps rather than counting ticks. What is
changed here:
  - a monotonic clock that keeps counting through sleep (Quickshell.Win32 MonotonicClock) guards
    the wall-clock stamps: when the wall clock is set while a timer runs (user, time sync), the
    stamps move by the same amount, so no time appears or disappears and nothing goes negative;
    sleeping IS elapsed time: a pomodoro that ended while the PC slept ends once, on waking;
  - the stopwatch refreshes (every 33 ms, the precision it shows is 10 ms) only while a stopwatch
    view is on screen; hidden, nothing ticks and the value is recomputed when it is shown again;
  - the pomodoro refreshes once a second only while its view is on screen; hidden, it wakes once
    near the end of the lap (never later than 30 s apart, to notice clock changes), so the
    notification and the sound still come on time;
  - nothing is written to disk on a tick, only on start/pause/reset/lap transitions (as before).
Exact-match edits of the staged tree.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.join(ROOT, *parts)


edit(path('services', 'TimerService.qml'), [
    ('''import Quickshell
import Quickshell.Io
import QtQuick
''', '''import Quickshell
import Quickshell.Io
import Quickshell.Win32
import QtQuick
'''),

    ('''    property var stopwatchLaps: Persistent.states.timer.stopwatch.laps

    // General
    Component.onCompleted: {
        if (!stopwatchRunning)
            stopwatchReset();
    }
''', '''    property var stopwatchLaps: Persistent.states.timer.stopwatch.laps

    // ii-windows (P11) ------------------------------------------------------------------------
    // How many views of each timer are on screen. Only then is there anything to refresh.
    property int stopwatchObservers: 0
    property int pomodoroObservers: 0
    function observeStopwatch(on) {
        root.stopwatchObservers = Math.max(0, root.stopwatchObservers + (on ? 1 : -1));
        if (on) root.refreshStopwatch();
    }
    function observePomodoro(on) {
        root.pomodoroObservers = Math.max(0, root.pomodoroObservers + (on ? 1 : -1));
        if (on && root.pomodoroRunning) root.refreshPomodoro();
    }

    // Wall clock minus the monotonic clock (which counts through sleep). It only changes when the
    // wall clock is set; correctForClockChange moves the running timers' stamps by that change.
    property real clockSkewMs: Date.now() - MonotonicClock.nowMs()
    function correctForClockChange() {
        const skew = Date.now() - MonotonicClock.nowMs();
        const jump = skew - root.clockSkewMs;
        root.clockSkewMs = skew;
        if (Math.abs(jump) < 2000) return; // ordinary difference between two reads
        console.log("[TimerService] The system clock changed by " + Math.round(jump / 1000) + " s; running timers keep their real elapsed time");
        if (Persistent.states.timer.pomodoro.running)
            Persistent.states.timer.pomodoro.start += Math.round(jump / 1000);
        if (Persistent.states.timer.stopwatch.running)
            Persistent.states.timer.stopwatch.start += Math.round(jump / 10);
    }

    // General
    Component.onCompleted: {
        root.clockSkewMs = Date.now() - MonotonicClock.nowMs();
        if (!stopwatchRunning)
            stopwatchReset();
    }
'''),

    ('''    function refreshPomodoro() {
        // Work <-> break ?''', '''    function refreshPomodoro() {
        correctForClockChange();
        // Work <-> break ?'''),

    ('''    Timer {
        id: pomodoroTimer
        interval: 200
        running: root.pomodoroRunning
        repeat: true
        onTriggered: refreshPomodoro()
    }''', '''    Timer {
        id: pomodoroTimer
        // Seen: once a second (the minutes:seconds it shows). Not seen: wake near the end of the lap,
        // and at least every 30 s so a changed clock is noticed. The 60 ms keeps the wake from
        // landing just before the second boundary and being a second late.
        interval: root.pomodoroObservers > 0 ? 1000 : Math.min(30000, Math.max(1000, root.pomodoroSecondsLeft * 1000 + 60))
        running: root.pomodoroRunning
        repeat: true
        onTriggered: refreshPomodoro()
    }'''),

    ('''    function refreshStopwatch() {  // Stopwatch stores time in 10ms
        stopwatchTime = getCurrentTimeIn10ms() - stopwatchStart;
    }

    Timer {
        id: stopwatchTimer
        interval: 10
        running: root.stopwatchRunning
        repeat: true
        onTriggered: refreshStopwatch()
    }''', '''    function refreshStopwatch() {  // Stopwatch stores time in 10ms
        correctForClockChange();
        // The stamp is a 32-bit property, so the subtraction wraps; "| 0" makes that explicit
        // (right for up to 248 days) and a stamp slightly in the future can't show a negative time.
        stopwatchTime = Math.max(0, (getCurrentTimeIn10ms() - stopwatchStart) | 0);
    }

    // Only while a stopwatch view is on screen; the value is recomputed when one appears.
    Timer {
        id: stopwatchTimer
        interval: 33 // it shows hundredths: faster than a frame would only repaint the same pixels
        running: root.stopwatchRunning && root.stopwatchObservers > 0
        repeat: true
        onTriggered: refreshStopwatch()
    }'''),
])

# The views say when they are on screen.
OBSERVE = '''
    // ii-windows (P11): the timer only refreshes while this is on screen.
    readonly property bool onScreen: visible && ((QsWindow.window as QsWindow)?.visible ?? true)
    property bool observing: false
    onOnScreenChanged: updateObserving()
    Component.onCompleted: updateObserving()
    Component.onDestruction: { if (observing) TimerService.%(fn)s(false); }
    function updateObserving() {
        if (onScreen === observing) return;
        observing = onScreen;
        TimerService.%(fn)s(onScreen);
    }
'''

edit(path('modules', 'ii', 'sidebarRight', 'pomodoro', 'Stopwatch.qml'), [
    ('''Item {
    id: stopwatchTab
    Layout.fillWidth: true
    Layout.fillHeight: true
''', '''Item {
    id: stopwatchTab
    Layout.fillWidth: true
    Layout.fillHeight: true
''' + OBSERVE % {'fn': 'observeStopwatch'}),
])

edit(path('modules', 'ii', 'sidebarRight', 'pomodoro', 'PomodoroTimer.qml'), [
    ('''Item {
    id: root

    implicitHeight: contentColumn.implicitHeight''', '''Item {
    id: root
''' + OBSERVE % {'fn': 'observePomodoro'} + '''
    implicitHeight: contentColumn.implicitHeight'''),
])
