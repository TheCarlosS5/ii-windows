import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows (plan 2026-10-31, F19/F20/H3): Configuración > Apariencia > Accesibilidad de Windows
// (modules/common/WindowsAccessibility.qml).
ContentSection {
    id: root
    icon: "accessibility_new"
    title: Translation.tr("Windows accessibility")

    ConfigSwitch {
        buttonIcon: "contrast_square"
        text: Translation.tr("Use Windows' contrast theme")
        checked: Config.options.appearance.followWindows.highContrast
        onCheckedChanged: Config.options.appearance.followWindows.highContrast = checked
        StyledToolTip { text: Translation.tr("When a contrast theme is on (Accessibility > Contrast themes), ii takes its colors and drops the transparency.") }
    }
    ConfigSwitch {
        buttonIcon: "format_size"
        text: Translation.tr("Follow Windows' text size")
        checked: Config.options.appearance.followWindows.textSize
        onCheckedChanged: Config.options.appearance.followWindows.textSize = checked
        StyledToolTip { text: Translation.tr("Accessibility > Text size; ii's text grows with it up to 150 %.") }
    }
    ConfigSwitch {
        buttonIcon: "animation"
        text: Translation.tr("No animations when Windows has them off")
        checked: Config.options.appearance.followWindows.animations
        onCheckedChanged: Config.options.appearance.followWindows.animations = checked
        StyledToolTip { text: Translation.tr("Accessibility > Visual effects > Animation effects. The transparency stays.") }
    }
    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        visible: WindowsAccessibility.loaded
        wrapMode: Text.Wrap
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
        text: Translation.tr("Now: contrast theme %1, text %2 %, animations %3.")
            .arg(WindowsAccessibility.windowsHighContrast ? Translation.tr("on") : Translation.tr("off"))
            .arg(Math.round(WindowsAccessibility.windowsTextScale * 100))
            .arg(WindowsAccessibility.windowsAnimations ? Translation.tr("on") : Translation.tr("off"))
    }
}
