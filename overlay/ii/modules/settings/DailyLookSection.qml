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
        id: daily
        buttonIcon: "image"
        text: Translation.tr("A wallpaper that changes by itself")
        checked: Config.options.background.daily.enable
        onCheckedChanged: Config.options.background.daily.enable = checked
        StyledToolTip { text: Translation.tr("The colors follow it, as with any wallpaper.") }
    }
    ConfigSelectionArray {
        visible: daily.checked
        currentValue: Config.options.background.daily.source
        onSelected: newValue => Config.options.background.daily.source = newValue
        options: [
            { displayName: Translation.tr("Bing's image of the day"), icon: "public", value: "bing" },
            { displayName: Translation.tr("A folder of mine"), icon: "folder", value: "folder" }
        ]
    }
    RowLayout {
        visible: daily.checked && Config.options.background.daily.source === "folder"
        spacing: 10
        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Folder with your images (C:\\Users\\you\\Pictures\\Wallpapers)")
            text: Config.options.background.daily.folder
            onEditingFinished: Config.options.background.daily.folder = text.trim().replace(/^"|"$/g, "")
        }
    }
    ConfigSpinBox {
        visible: daily.checked && Config.options.background.daily.source === "folder"
        icon: "timer"
        text: Translation.tr("Next image every (minutes)")
        value: Config.options.background.daily.minutes
        from: 1
        to: 1440
        stepSize: 5
        onValueChanged: Config.options.background.daily.minutes = value
    }

    ConfigSwitch {
        id: autoDark
        buttonIcon: "contrast"
        text: Translation.tr("Light theme by day, dark by night")
        checked: Config.options.appearance.autoDark.enable
        onCheckedChanged: Config.options.appearance.autoDark.enable = checked
    }
    ConfigSelectionArray {
        visible: autoDark.checked
        currentValue: Config.options.appearance.autoDark.mode
        onSelected: newValue => Config.options.appearance.autoDark.mode = newValue
        options: [
            { displayName: Translation.tr("At these hours"), icon: "schedule", value: "hours" },
            { displayName: Translation.tr("With the sun"), icon: "wb_twilight", value: "sun" }
        ]
    }
    StyledText {
        visible: autoDark.checked && Config.options.appearance.autoDark.mode === "sun"
        Layout.fillWidth: true
        Layout.leftMargin: 4
        wrapMode: Text.Wrap
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
        text: DailyLook.hours.sun
            ? Translation.tr("Today: light from %1, dark from %2 (the weather's location).").arg(DailyLook.hours.light).arg(DailyLook.hours.dark)
            : Translation.tr("Sunrise and sunset come from the weather (Servicios > Clima); until then, the hours below.")
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
