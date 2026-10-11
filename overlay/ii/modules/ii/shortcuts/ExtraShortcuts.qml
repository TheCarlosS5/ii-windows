import QtQuick
import Quickshell
import Quickshell.Hyprland

// ii-windows (U02): shell actions the Windows keyboard asks for that upstream's Hyprland setup
// reaches another way. Names match shared/actions.json.
Scope {
    // Win+I: ii's own settings window (not Windows' Settings app).
    GlobalShortcut {
        name: "settingsOpen"
        description: "Opens ii's settings"
        onPressed: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("settings.qml")])
    }
}
