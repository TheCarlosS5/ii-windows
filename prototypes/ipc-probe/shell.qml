// No windows: only an IPC target, to test `qs ipc` on Windows.
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    IpcHandler {
        target: "probe"
        function ping(): string { return "pong"; }
    }
}
