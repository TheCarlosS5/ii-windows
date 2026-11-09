pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions

// One WASAPI capture/FFT feeds all visible subscribers, regardless of monitor count.
Singleton {
    id: root
    property var consumers: []
    property bool demand: false
    property list<real> points: []
    readonly property bool wanted: demand && !Config.options.appearance.reduceMotion && !GlobalStates.screenLocked
    onWantedChanged: if (!wanted) {
        points = [];
        // QProcess::terminate sends WM_CLOSE on Windows; a console audio producer has no window.
        capture.signal(9);
    }

    function setDemand(client, enabled) {
        const next = consumers.slice();
        const index = next.indexOf(client);
        if (enabled && index < 0) next.push(client);
        else if (!enabled && index >= 0) next.splice(index, 1);
        else return;
        consumers = next;
        demandSoon.restart();
    }

    function settleDemand() { demand = consumers.length > 0; }
    Timer {
        id: demandSoon
        interval: 30
        onTriggered: root.settleDemand()
    }

    Process {
        id: capture
        running: root.wanted
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        onRunningChanged: {
            if (!running) root.points = [];
            else if (!root.wanted) capture.signal(9);
        }
        stdout: SplitParser {
            onRead: data => {
                if (root.wanted) root.points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
            }
        }
    }
}
