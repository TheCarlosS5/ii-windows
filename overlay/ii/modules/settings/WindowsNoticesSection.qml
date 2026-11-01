import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows (plan 2026-10-31, F2/F14): Configuración > Sistema > Avisos de Windows. ii-host looks every hour at
// whether Windows waits for a restart to finish its updates and at the system drive's free space.
ContentSection {
    icon: "info"
    title: Translation.tr("Windows notices")

    ConfigSwitch {
        buttonIcon: "restart_alt"
        text: Translation.tr("Tell me when Windows needs a restart to finish its updates")
        checked: Config.options.iiSystem.restartNotice
        onCheckedChanged: Config.options.iiSystem.restartNotice = checked
    }
    ConfigSwitch {
        buttonIcon: "hard_drive"
        text: Translation.tr("Tell me when the system drive is running out of space")
        checked: Config.options.iiSystem.lowDiskNotice
        onCheckedChanged: Config.options.iiSystem.lowDiskNotice = checked
    }
    StyledText {
        Layout.fillWidth: true
        visible: SystemStatus.rebootRequired || SystemStatus.lowDisk
        wrapMode: Text.Wrap
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.small
        text: [
            SystemStatus.rebootRequired ? Translation.tr("Now: Windows is waiting for a restart.") : "",
            SystemStatus.lowDisk ? Translation.tr("Now: %1 has %2 GB free.").arg(SystemStatus.drive).arg((SystemStatus.freeBytes / 1073741824).toFixed(1)) : ""
        ].filter(t => t.length > 0).join(" ")
    }
}
