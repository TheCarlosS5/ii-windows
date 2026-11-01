import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows (plan 2026-10-31, E12): Configuración > Paneles > No molestar: its hours (services/DndSchedule.qml) and the
// apps that get through it anyway (Notifications.isVip).
ContentSection {
    id: root
    icon: "do_not_disturb_on"
    title: Translation.tr("Do not disturb")

    readonly property var days: [{ d: 1, n: "Mon" }, { d: 2, n: "Tue" }, { d: 3, n: "Wed" }, { d: 4, n: "Thu" }, { d: 5, n: "Fri" }, { d: 6, n: "Sat" }, { d: 0, n: "Sun" }]
    function setDnd(key, value) {
        const s = JSON.parse(JSON.stringify(Config.options.notifications.dnd));
        s[key] = value;
        Config.options.notifications.dnd = s;
    }

    ConfigSwitch {
        id: scheduleSwitch
        buttonIcon: "schedule"
        text: Translation.tr("Turn it on by itself at these hours")
        checked: Config.options.notifications.dnd.enable
        onCheckedChanged: if (checked !== Config.options.notifications.dnd.enable) root.setDnd("enable", checked)
    }
    Flow {
        Layout.fillWidth: true
        visible: scheduleSwitch.checked
        spacing: 4
        Repeater {
            model: root.days
            delegate: SelectionGroupButton {
                required property var modelData
                readonly property var selected: Config.options.notifications.dnd.days ?? [0, 1, 2, 3, 4, 5, 6]
                buttonText: Translation.tr(modelData.n)
                toggled: selected.includes(modelData.d)
                leftmost: true
                rightmost: true
                onClicked: root.setDnd("days", (toggled ? selected.filter(x => x !== modelData.d) : selected.concat([modelData.d])).sort())
            }
        }
    }
    RowLayout {
        visible: scheduleSwitch.checked
        spacing: 10
        StyledText { text: Translation.tr("From") }
        MaterialTextField {
            implicitWidth: 90
            placeholderText: "22:00"
            text: Config.options.notifications.dnd.from
            validator: RegularExpressionValidator { regularExpression: /^([01]?\d|2[0-3]):[0-5]\d$/ }
            onEditingFinished: if (acceptableInput && text !== Config.options.notifications.dnd.from) root.setDnd("from", text)
        }
        StyledText { text: Translation.tr("to") }
        MaterialTextField {
            implicitWidth: 90
            placeholderText: "07:00"
            text: Config.options.notifications.dnd.to
            validator: RegularExpressionValidator { regularExpression: /^([01]?\d|2[0-3]):[0-5]\d$/ }
            onEditingFinished: if (acceptableInput && text !== Config.options.notifications.dnd.to) root.setDnd("to", text)
        }
    }
    ContentSubsection {
        title: Translation.tr("Apps that get through")
        tooltip: Translation.tr("Their notices still pop up with Do not disturb on. The app's name as its notices show it (WhatsApp, Discord), one per line.")
        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("For example: WhatsApp")
            wrapMode: TextEdit.Wrap
            text: (Config.options.notifications.vipApps ?? []).join("\n")
            onActiveFocusChanged: {
                if (activeFocus) return;
                const apps = text.split(/[\n,;]+/).map(a => a.trim()).filter(a => a.length > 0);
                if (apps.join("\n") !== (Config.options.notifications.vipApps ?? []).join("\n")) Config.options.notifications.vipApps = apps;
            }
        }
    }
}
