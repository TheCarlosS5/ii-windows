import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows (plan 2026-10-31, E11): Configuración > Sistema > Bienestar. Limits per app, eye breaks and the weekly
// summary (services/Wellbeing.qml). The apps to choose from are today's, from screen time.
ContentSection {
    id: root
    icon: "self_improvement"
    title: Translation.tr("Wellbeing")

    function goals() {
        return JSON.parse(JSON.stringify(Config.options.wellbeing.goals ?? []));
    }
    readonly property var todayApps: {
        const t = Wellbeing.today;
        if (!t || !t.apps) return [];
        return Object.keys(t.apps).sort((a, b) => t.apps[b] - t.apps[a]).slice(0, 12)
            .map(k => ({ exe: k, name: (t.names && t.names[k]) || k.replace(/\.exe$/i, ""), minutes: Math.round(t.apps[k] / 60) }));
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Appearance.colors.colSubtext
        text: Translation.tr("Kind reminders from your screen time (the right panel's Usage tab). Everything stays on this PC.")
    }
    ConfigSwitch {
        buttonIcon: "visibility"
        text: Translation.tr("Remind me to rest my eyes (20-20-20)")
        checked: Config.options.wellbeing.eyeBreaks
        onCheckedChanged: Config.options.wellbeing.eyeBreaks = checked
        StyledToolTip { text: Translation.tr("Every 20 minutes of use: look at something 6 meters away for 20 seconds.") }
    }
    ConfigSwitch {
        buttonIcon: "date_range"
        text: Translation.tr("A summary of my week on Sunday evening")
        checked: Config.options.wellbeing.weekly
        onCheckedChanged: Config.options.wellbeing.weekly = checked
    }

    ContentSubsection {
        title: Translation.tr("Daily limits")
        tooltip: Translation.tr("A notice once a day when an app passes its time.")
        Repeater {
            model: Config.options.wellbeing.goals ?? []
            delegate: RowLayout {
                id: goalRow
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 8
                StyledText {
                    Layout.fillWidth: true
                    text: (root.todayApps.find(a => a.exe.toLowerCase() === String(goalRow.modelData.exe).toLowerCase())?.name) ?? goalRow.modelData.exe
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("minutes")
                    from: 5
                    to: 960
                    stepSize: 15
                    value: goalRow.modelData.minutes
                    onValueChanged: {
                        if (value === goalRow.modelData.minutes) return;
                        const list = root.goals();
                        list[goalRow.index].minutes = value;
                        Config.options.wellbeing.goals = list;
                    }
                }
                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    onClicked: {
                        const list = root.goals();
                        list.splice(goalRow.index, 1);
                        Config.options.wellbeing.goals = list;
                    }
                    contentItem: MaterialSymbol { anchors.centerIn: parent; text: "delete"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                    StyledToolTip { text: Translation.tr("Remove") }
                }
            }
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: root.todayApps.length > 0 ? Translation.tr("Add a limit to one of today's apps:")
                : Translation.tr("No screen time today yet: once ii has counted a while, today's apps show here to choose from.")
        }
        Flow {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: root.todayApps.filter(a => !(Config.options.wellbeing.goals ?? []).some(g => String(g.exe).toLowerCase() === a.exe.toLowerCase()))
                delegate: SelectionGroupButton {
                    required property var modelData
                    leftmost: true
                    rightmost: true
                    buttonIcon: "add"
                    buttonText: `${modelData.name} · ${modelData.minutes} min`
                    onClicked: Config.options.wellbeing.goals = root.goals().concat([{ exe: modelData.exe, minutes: 120 }])
                }
            }
        }
    }
}
