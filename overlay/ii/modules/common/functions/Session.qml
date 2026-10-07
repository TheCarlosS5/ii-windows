pragma Singleton
import Quickshell
import qs.services
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

    function lock() {
        Quickshell.execDetached(["ii-shim", "lock"]);
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
