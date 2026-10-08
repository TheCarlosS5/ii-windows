import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    backgroundHeight: 620
    WindowDialogTitle { text: Translation.tr("Night Light") }
    WindowDialogSeparator {}
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: !Hyprsunset.available ? Translation.tr("Not available") + " (ii-host)"
            : Hyprsunset.errorCode ? "Windows: " + Translation.tr("Not available") + " (" + Hyprsunset.errorCode + ")"
            : `${Hyprsunset.effectiveTemperature} K · ${Translation.tr("Gamma")} ${Hyprsunset.effectiveGamma}% · ≥ ${Hyprsunset.minimumTemperature} K${Hyprsunset.minimumVerified ? " ✓" : " (?)"}`
    }
    Column {
        Layout.fillWidth: true
        ConfigSwitch {
            width: parent.width
            enabled: Hyprsunset.available
            text: Translation.tr("Enable now")
            buttonIcon: "bedtime"
            checked: Hyprsunset.temperatureActive
            // Only user clicks change the requested state; readback isn't a new command.
            onClicked: Hyprsunset.toggleTemperature(!Hyprsunset.requestedTemperature)
        }
        ConfigSwitch {
            width: parent.width
            text: Translation.tr("Automatic")
            buttonIcon: "night_sight_auto"
            checked: Config.options.light.night.automatic
            onClicked: Config.options.light.night.automatic = !Config.options.light.night.automatic
        }
        RowLayout {
            width: parent.width
            StyledText { text: Translation.tr("From") }
            MaterialTextField {
                Layout.fillWidth: true
                text: Config.options.light.night.from
                placeholderText: "19:00"
                onEditingFinished: {
                    if (/^([01]\d|2[0-3]):[0-5]\d$/.test(text)) Config.options.light.night.from = text;
                    else text = Config.options.light.night.from;
                }
            }
            StyledText { text: Translation.tr("To") }
            MaterialTextField {
                Layout.fillWidth: true
                text: Config.options.light.night.to
                placeholderText: "06:30"
                onEditingFinished: {
                    if (/^([01]\d|2[0-3]):[0-5]\d$/.test(text)) Config.options.light.night.to = text;
                    else text = Config.options.light.night.to;
                }
            }
        }
        WindowDialogSlider {
            width: parent.width
            enabled: Hyprsunset.available
            text: Translation.tr("Intensity")
            from: 6500
            to: Hyprsunset.minimumTemperature
            stopIndicatorValues: [5000, to].filter(v => v >= to)
            value: Math.max(to, Config.options.light.night.colorTemperature)
            onMoved: Config.options.light.night.colorTemperature = Math.round(value)
            tooltipContent: `${Math.round(value)} K`
        }
        WindowDialogSlider {
            width: parent.width
            enabled: Hyprsunset.available
            text: Translation.tr("Gamma")
            from: Hyprsunset.gammaLowerLimit / 100
            to: 1
            value: Hyprsunset.gamma / 100
            onMoved: Hyprsunset.setGamma(value * 100)
            tooltipContent: `${Math.round(value * 100)}%`
        }
    }
    Item { Layout.fillHeight: true }
    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Display settings")
            onClicked: Quickshell.execDetached(["xdg-open", "ms-settings:display"])
        }
        Item { Layout.fillWidth: true }
        DialogButton { buttonText: Translation.tr("Done"); onClicked: root.dismiss() }
    }
}
