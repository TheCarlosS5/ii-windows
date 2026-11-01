import QtQuick
import Quickshell
import qs.services
import qs.modules.common

// ii-windows (plan 2026-10-31, F6): Windows' HDR switch (Configuración > Pantalla > HDR) on every screen that has it.
QuickToggleModel {
    id: root
    readonly property DisplayInfo display: DisplayInfo {}
    name: Translation.tr("HDR")
    available: root.display.hdrSupported
    toggled: root.display.hdrOn
    icon: "hdr_on"
    statusText: !root.display.hdrSupported ? Translation.tr("Not supported") : root.display.hdrOn ? Translation.tr("On") : Translation.tr("Off")
    tooltipText: Translation.tr("HDR on the screens that support it (the same switch as Windows Settings)")
    mainAction: () => { if (root.display.hdrSupported && !root.display.busy) root.display.run(["hdr", root.display.hdrOn ? "off" : "on"]); }
    hasMenu: true
    altAction: () => Qt.openUrlExternally("ms-settings:display-hdr")
}
