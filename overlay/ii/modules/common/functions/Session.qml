pragma Singleton
import QtQuick
import Quickshell
import qs.services
import qs
import qs.modules.common

/**
 * ii-windows: session actions with Windows' own mechanisms.
 * Upstream kills every window's process before powering off; on Windows the system already
 * asks applications to close (so they can save), so nothing is killed here.
 */
Singleton {
    id: root

    function closeAllWindows() {
        // Intentionally empty: Windows' shutdown asks applications to close gracefully.
    }

    function changePassword() {
        Quickshell.execDetached(["explorer.exe", "ms-settings:signinoptions"]);
    }

    // ii's lock animation first (LockScreen.qml's WlSessionLock locks Windows right after);
    // if that path isn't there, Windows locks directly a moment later anyway.
    function lock() {
        GlobalStates.screenLocked = true;
        lockFallback.restart();
    }
    property Timer lockFallback: Timer {
        interval: 2000
        // Not after a quick unlock (Windows Hello can be faster than this): unlocking resets it.
        onTriggered: if (GlobalStates.screenLocked) Quickshell.execDetached(["ii-shim", "lock"])
    }

    function suspend() {
        Quickshell.execDetached(["ii-shim", "suspend"]);
    }

    function logout() {
        Quickshell.execDetached(["shutdown.exe", "/l"]);
    }

    function launchTaskManager() {
        Quickshell.execDetached(["taskmgr.exe"]);
    }

    function hibernate() {
        Quickshell.execDetached(["shutdown.exe", "/h"]);
    }

    function poweroff() {
        Quickshell.execDetached(["shutdown.exe", "/s", "/t", "0"]);
    }

    function reboot() {
        Quickshell.execDetached(["shutdown.exe", "/r", "/t", "0"]);
    }

    function rebootToFirmware() {
        // Needs administrator rights; Windows shows its own error otherwise.
        Quickshell.execDetached(["shutdown.exe", "/r", "/fw", "/t", "0"]);
    }
}
