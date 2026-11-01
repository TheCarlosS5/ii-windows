import QtQuick
import Quickshell
import qs.services
import qs.modules.common

// ii-windows (plan 2026-10-31, F7): the main screen between its highest refresh rate and 60 Hz (on battery 60 Hz lasts
// longer). Only for this session: Windows' saved rate comes back after a restart.
QuickToggleModel {
    id: root
    readonly property DisplayInfo display: DisplayInfo {}
    readonly property int top: root.display.rates.length ? root.display.rates[root.display.rates.length - 1] : 0
    // The low rate: 60 if offered, else the lowest one from 50 up.
    readonly property int low: root.display.rates.indexOf(60) >= 0 ? 60 : (root.display.rates.find(r => r >= 50) ?? 0)
    name: Translation.tr("Refresh rate")
    available: root.top > 0 && root.low > 0 && root.top > root.low
    toggled: root.display.hz > 0 && root.display.hz === root.top
    icon: root.toggled ? "speed" : "battery_saver"
    statusText: root.display.hz > 0 ? `${root.display.hz} Hz` : ""
    tooltipText: Translation.tr("The screen between %1 Hz and %2 Hz (until the next restart)").arg(root.top).arg(root.low)
    mainAction: () => { if (root.available && !root.display.busy) root.display.run(["hz", String(root.toggled ? root.low : root.top)]); }
    hasMenu: true
    altAction: () => Qt.openUrlExternally("ms-settings:display-advanced")
}
