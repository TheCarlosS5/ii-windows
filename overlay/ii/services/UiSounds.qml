pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Windows
import qs
import qs.modules.common

/**
 * ii-windows: interface sounds (assets/sounds/ui, made for this port by
 * tools/sounds/make_sounds.py): panels opening and closing, notifications, switching virtual
 * desktops, editing the desktop. Off with Config.options.sounds.ui; volume sounds.uiVolume.
 * Quiet while a fullscreen app (a game) is in front, during startup and in "do not disturb"
 * for notifications.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.ready && (Config.options.sounds.ui ?? true)
    readonly property real volume: Config.options.sounds.uiVolume ?? 0.4
    property bool started: false

    function load() {}

    function play(name) {
        if (!root.enabled || !root.started) return;
        if (HyprlandData.activeWorkspace?.hasfullscreen) return;
        UiSound.play(Quickshell.shellPath(`assets/sounds/ui/${name}.wav`), root.volume);
    }

    // No sounds for the panels' and desktops' initial state.
    Timer {
        running: true
        interval: 5000
        onTriggered: root.started = true
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() { root.play(GlobalStates.overviewOpen ? "open" : "close"); }
        function onSidebarRightOpenChanged() { root.play(GlobalStates.sidebarRightOpen ? "open" : "close"); }
        function onSidebarLeftOpenChanged() { root.play(GlobalStates.sidebarLeftOpen ? "open" : "close"); }
        function onSessionOpenChanged() { root.play(GlobalStates.sessionOpen ? "open" : "close"); }
        function onMediaControlsOpenChanged() { root.play(GlobalStates.mediaControlsOpen ? "open" : "close"); }
        function onWallpaperSelectorOpenChanged() { root.play(GlobalStates.wallpaperSelectorOpen ? "open" : "close"); }
        function onOverlayOpenChanged() { root.play(GlobalStates.overlayOpen ? "open" : "close"); }
        function onDesktopEditModeChanged() { root.play(GlobalStates.desktopEditMode ? "edit" : "close"); }
    }

    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() { root.play("switch"); }
    }

    Connections {
        target: Notifications
        function onNotify(notification) {
            if (!Notifications.silent && (Config.options.sounds.uiNotifications ?? false)) root.play("notify");
        }
    }
}
