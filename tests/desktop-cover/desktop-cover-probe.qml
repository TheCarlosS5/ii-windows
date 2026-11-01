// Test config (plan 2026-10-31, D2), copied next to the staged ii (build\ii) by tools\sandbox\tests\test-desktop-cover.ps1
// so that qs.services resolves: logs what DesktopCover and DesktopTime say, and how often the desktop clock ticks.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

ShellRoot {
    id: root
    property int ticks: 0
    Connections {
        target: DesktopTime.clock
        function onDateChanged() { root.ticks++; }
    }
    Component.onCompleted: DesktopTime.clock.precision = SystemClock.Seconds
    Timer {
        interval: 250
        running: true
        repeat: true
        onTriggered: console.info(`cover covered=${DesktopCover.coveredScreens.join(",")} all=${DesktopCover.allCovered} clock=${DesktopTime.clock.enabled} ticks=${root.ticks} t=${Date.now()}`)
    }
    Timer { // what the cover is computed from (II_TEST_VERBOSE)
        interval: 1000
        running: Quickshell.env("II_TEST_VERBOSE") === "1"
        repeat: true
        onTriggered: console.info(`windows ws=${Hyprland.focusedWorkspace?.id} screens=${Quickshell.screens.map(s => s.name)} `
            + ToplevelManager.toplevels.values.map(t => `${t.title.slice(0, 20)}:max=${t.maximized}:min=${t.minimized}:fs=${t.fullscreen}:d=${t.desktop}:s=${(t.screens ?? []).map(s => s?.name)}`).join(" | "))
    }
}
