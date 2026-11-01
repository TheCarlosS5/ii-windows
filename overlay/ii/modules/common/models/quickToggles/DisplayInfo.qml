import QtQuick
import Quickshell
import Quickshell.Io
import qs

// ii-windows (plan 2026-10-31, F6/F7): what `ii-shim display` says (HDR, the main screen's rate), read while the right
// panel is open; shared by HdrToggle and RefreshRateToggle.
QtObject {
    id: root
    property bool hdrSupported: false
    property bool hdrOn: false
    property int hz: 0
    property var rates: []
    property bool busy: false
    function refresh() { if (!proc.running) proc.running = true; }
    function run(args) {
        root.busy = true;
        setProc.command = ["ii-shim", "display"].concat(args);
        setProc.running = true;
    }
    property Process proc: Process {
        running: true
        command: ["ii-shim", "display"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.hdrSupported = d.hdr?.supported === true;
                    root.hdrOn = d.hdr?.on === true;
                    root.hz = d.hz ?? 0;
                    root.rates = d.rates ?? [];
                } catch (e) { console.warn("display: " + e + " " + text); }
            }
        }
    }
    property Process setProc: Process {
        onExited: { root.busy = false; root.refresh(); }
    }
    property Timer timer: Timer {
        interval: 5000
        running: GlobalStates.sidebarRightOpen
        triggeredOnStart: true
        repeat: true
        onTriggered: root.refresh()
    }
}
