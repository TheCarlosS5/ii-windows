import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common

// ii-windows (plan 2026-10-31, F4): Windows 11's energy saver. Its state comes from ii-shim power status (Windows sets
// SystemStatusFlag while it is on); Windows has no documented way for an app to switch it, so the button opens its
// page in Windows Settings (Sistema > Energía y batería > Ahorro de energía).
QuickToggleModel {
    id: root
    property bool saver: false
    property bool onBattery: false
    name: Translation.tr("Energy saver")
    toggled: root.saver
    icon: "energy_savings_leaf"
    statusText: root.saver ? Translation.tr("On") : Translation.tr("Off")
    tooltipText: Translation.tr("Windows' energy saver: fewer background tasks and a dimmer screen. Opens its settings")
    mainAction: () => Quickshell.execDetached(["ii-shim", "host", "ms-settings", "batterysaver"])

    Process {
        id: statusProc
        running: true
        command: ["ii-shim", "power", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const state = JSON.parse(text);
                    root.saver = state.saver === true;
                    root.onBattery = state.onBattery === true;
                } catch (e) {}
            }
        }
    }
    Timer {
        interval: 5000
        running: GlobalStates.sidebarRightOpen // only while it can be seen
        triggeredOnStart: true
        repeat: true
        onTriggered: if (!statusProc.running) statusProc.running = true
    }
}
