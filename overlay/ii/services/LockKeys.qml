pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// ii-windows: the state of Caps Lock, Num Lock and Scroll Lock, from `ii-shim keystate` (one small process
// that prints a line when one of them changes). `toggled(key, on)` fires for each change after the first
// reading, so the shell can say "Caps Lock on" like Windows' own indicator does on some keyboards.
Singleton {
    id: root

    property bool capsLock: false
    property bool numLock: false
    property bool scrollLock: false
    property bool ready: false
    signal toggled(string key, bool on)

    function load() {
        if (!proc.running) proc.running = true;
    }

    Process {
        id: proc
        command: ["ii-shim", "keystate"]
        stdout: SplitParser {
            onRead: line => {
                const m = /caps=(\d) num=(\d) scroll=(\d)/.exec(line);
                if (!m) return;
                const caps = m[1] === "1";
                const num = m[2] === "1";
                const scroll = m[3] === "1";
                if (root.ready) {
                    if (caps !== root.capsLock) root.toggled("caps", caps);
                    if (num !== root.numLock) root.toggled("num", num);
                    if (scroll !== root.scrollLock) root.toggled("scroll", scroll);
                }
                root.capsLock = caps;
                root.numLock = num;
                root.scrollLock = scroll;
                root.ready = true;
            }
        }
        onExited: restart.restart()
    }
    // An older ii-shim has no `keystate`: it exits at once; try again rarely instead of in a loop.
    Timer {
        id: restart
        interval: 15000
        onTriggered: proc.running = true
    }
}
