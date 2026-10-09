pragma Singleton
pragma ComponentBehavior: Bound

// ii-windows: the shortcuts ii-host actually maps (host/src/keyboard.cpp, keep in sync), plus
// the Windows ones that stay as they are, in the shape of `hyprctl binds -j` for the cheatsheet.

import QtQuick
import Quickshell

Singleton {
    id: root

    // Hyprland modmask bits
    readonly property int shift: 1 << 0
    readonly property int ctrl: 1 << 2
    readonly property int alt: 1 << 3
    readonly property int superKey: 1 << 6

    function bind(modmask, key, description) {
        return { "modmask": modmask, "key": key, "description": description };
    }

    property var keybinds: [
        bind(superKey, "SUPER_L", "Shell: Search apps, files and math (tap the key)"),
        bind(superKey, "Tab", "Shell: Overview of open windows"),
        bind(superKey, "V", "Shell: Clipboard history"),
        bind(superKey, "Period", "Shell: Emoji picker"),
        bind(superKey, "A", "Shell: Left sidebar"),
        bind(superKey, "N", "Shell: Right sidebar (quick settings, notifications)"),
        bind(superKey, "M", "Shell: Media controls"),
        bind(superKey, "G", "Shell: Overlay widgets"),
        bind(superKey, "J", "Shell: Show or hide the bar"),
        bind(superKey, "K", "Shell: On-screen keyboard"),
        bind(superKey, "Slash", "Shell: This cheatsheet"),
        bind(superKey, "D", "Shell: Show desktop (again to restore)"),
        bind(superKey | ctrl, "R", "Shell: Restart ii"),
        bind(superKey | shift, "C", "Shell: Color picker (copies #RRGGBB)"),
        bind(superKey | ctrl, "T", "Shell: Wallpaper selector"),
        bind(superKey | ctrl | alt, "T", "Shell: Random wallpaper"),
        bind(superKey | ctrl | shift, "D", "Shell: Toggle light/dark"),
        bind(superKey | shift, "S", "Screenshot: Region screenshot"),
        bind(superKey | shift, "A", "Screenshot: Search a region"),
        bind(superKey | shift, "X", "Screenshot: Text from a region (OCR)"),
        bind(superKey | shift, "T", "Screenshot: Translate a region"),
        bind(superKey | shift, "R", "Screenshot: Record a region"),
        bind(ctrl | alt, "End", "Session: Session menu (power, sign out, lock)"),
        bind(superKey, "L", "Session: Lock (Windows)"),
        bind(ctrl | alt, "Delete", "Session: Security options (Windows)"),
        bind(ctrl | shift, "Escape", "Session: Task Manager (Windows)"),
        bind(superKey, "E", "Windows: File Explorer"),
        bind(superKey, "R", "Windows: Run"),
        bind(superKey, "I", "Windows: Settings"),
        bind(alt, "Tab", "Windows: Switch windows"),
        bind(superKey, "Up", "Windows: Maximize / snap"),
        bind(ctrl | alt | shift, "R", "Safety: Panic: restore Windows' taskbar and desktop, stop ii"),
    ]

    property var keybindCategories: {
        const groups = [];
        for (const bind of keybinds) {
            const group = bind.description.substring(0, bind.description.indexOf(":"));
            if (group.length > 0 && !groups.includes(group)) groups.push(group);
        }
        return groups;
    }
}
