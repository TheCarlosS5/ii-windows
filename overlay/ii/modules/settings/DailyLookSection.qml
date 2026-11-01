import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows (plan 2026-10-31, E13): Configuración > Apariencia > Según el día (services/DailyLook.qml).
ContentSection {
    id: root
    icon: "routine"
    title: Translation.tr("Through the day")

    ConfigSwitch {
        buttonIcon: "image"
        text: Translation.tr("A new wallpaper every day (Bing's image of the day)")
        checked: Config.options.background.daily.enable
        onCheckedChanged: Config.options.background.daily.enable = checked
        StyledToolTip { text: Translation.tr("Downloaded once a day into Pictures\\Wallpapers; the colors follow it.") }
    }
    ConfigSwitch {
        id: autoDark
        buttonIcon: "contrast"
        text: Translation.tr("Light theme by day, dark by night")
        checked: Config.options.appearance.autoDark.enable
        onCheckedChanged: Config.options.appearance.autoDark.enable = checked
    }
    RowLayout {
        visible: autoDark.checked
        spacing: 10
        MaterialSymbol { text: "light_mode"; iconSize: 20; color: Appearance.colors.colOnLayer1 }
        StyledText { text: Translation.tr("Light from") }
        MaterialTextField {
            implicitWidth: 90
            placeholderText: "07:00"
            text: Config.options.appearance.autoDark.lightAt
            validator: RegularExpressionValidator { regularExpression: /^([01]?\d|2[0-3]):[0-5]\d$/ }
            onEditingFinished: if (acceptableInput) Config.options.appearance.autoDark.lightAt = text
        }
        MaterialSymbol { text: "dark_mode"; iconSize: 20; color: Appearance.colors.colOnLayer1 }
        StyledText { text: Translation.tr("dark from") }
        MaterialTextField {
            implicitWidth: 90
            placeholderText: "19:00"
            text: Config.options.appearance.autoDark.darkAt
            validator: RegularExpressionValidator { regularExpression: /^([01]?\d|2[0-3]):[0-5]\d$/ }
            onEditingFinished: if (acceptableInput) Config.options.appearance.autoDark.darkAt = text
        }
    }
}
