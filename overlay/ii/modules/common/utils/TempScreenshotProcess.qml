import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

// ii-windows: the monitor is captured by ii-shim (GDI + WIC) instead of grim.
Process {
    id: screenshotProc
    running: true
    property string screenshotDir: Directories.screenshotTemp
    required property ShellScreen screen
    property string screenshotPath: `${screenshotDir}/image-${screen.name}`
    command: ["ii-shim", "screenshot", "--output", screen.name, screenshotPath]
}
