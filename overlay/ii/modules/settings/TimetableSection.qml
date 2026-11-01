import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../common/functions/timetable_logic.js" as Logic

// ii-windows (plan 2026-10-31, E3): Configuración > Servicios > Horario de clases. The week's classes (services/
// Timetable.qml reminds of them and the left panel's Hoy tab shows them). Every change writes a new copy of the list.
ContentSection {
    id: root
    icon: "school"
    title: Translation.tr("Class timetable")

    readonly property var days: [{ d: 1, n: "Monday" }, { d: 2, n: "Tuesday" }, { d: 3, n: "Wednesday" }, { d: 4, n: "Thursday" },
        { d: 5, n: "Friday" }, { d: 6, n: "Saturday" }, { d: 0, n: "Sunday" }]
    function dayName(d) {
        return Translation.tr(root.days.find(x => x.d === d)?.n ?? "");
    }
    function classes() {
        return JSON.parse(JSON.stringify(Config.options.timetable.classes ?? []));
    }
    function save(list) {
        Config.options.timetable.classes = list;
    }

    ConfigSwitch {
        buttonIcon: "notifications_active"
        text: Translation.tr("Remind me before each class")
        checked: Config.options.timetable.enable
        onCheckedChanged: Config.options.timetable.enable = checked
    }
    ConfigSpinBox {
        visible: Config.options.timetable.enable
        icon: "timer"
        text: Translation.tr("Minutes before")
        from: 1
        to: 60
        value: Config.options.timetable.remindMinutes
        onValueChanged: Config.options.timetable.remindMinutes = value
    }

    // The week, sorted by day and hour.
    Repeater {
        model: root.days.map(x => ({ day: x.d, list: Logic.classesOn(Config.options.timetable.classes, x.d) })).filter(x => x.list.length > 0)
        delegate: ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 2
            ContentSubsectionLabel { text: root.dayName(modelData.day) }
            Repeater {
                model: modelData.list
                delegate: RowLayout {
                    id: classRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialSymbol { text: Logic.joinLink(classRow.modelData) ? "videocam" : "school"; iconSize: 20; color: Appearance.colors.colOnLayer1 }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: `${classRow.modelData.from}–${classRow.modelData.to}  ${classRow.modelData.subject}` + (classRow.modelData.room ? `  · ${classRow.modelData.room}` : "")
                    }
                    RippleButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        onClicked: root.save(root.classes().filter(c => c.id !== classRow.modelData.id))
                        contentItem: MaterialSymbol { anchors.centerIn: parent; text: "delete"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                        StyledToolTip { text: Translation.tr("Remove") }
                    }
                }
            }
        }
    }
    StyledText {
        visible: (Config.options.timetable.classes ?? []).length === 0
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Appearance.colors.colSubtext
        text: Translation.tr("No classes yet. Add them below: they show in the left panel (Hoy) and you get a notice before each one.")
    }

    ContentSubsection {
        title: Translation.tr("Add a class")
        MaterialTextField {
            id: subject
            Layout.fillWidth: true
            placeholderText: Translation.tr("Subject")
        }
        ConfigSelectionArray {
            id: dayChoice
            currentValue: 1
            onSelected: newValue => currentValue = newValue
            options: root.days.map(x => ({ displayName: Translation.tr(x.n).slice(0, 3), value: x.d }))
        }
        RowLayout {
            spacing: 10
            StyledText { text: Translation.tr("From") }
            MaterialTextField {
                id: fromField
                implicitWidth: 90
                placeholderText: "18:00"
                validator: RegularExpressionValidator { regularExpression: /^([01]?\d|2[0-3]):[0-5]\d$/ }
            }
            StyledText { text: Translation.tr("to") }
            MaterialTextField {
                id: toField
                implicitWidth: 90
                placeholderText: "20:00"
                validator: RegularExpressionValidator { regularExpression: /^([01]?\d|2[0-3]):[0-5]\d$/ }
            }
        }
        MaterialTextField {
            id: room
            Layout.fillWidth: true
            placeholderText: Translation.tr("Room or teacher (optional)")
        }
        MaterialTextField {
            id: link
            Layout.fillWidth: true
            placeholderText: Translation.tr("Meet / Teams / Zoom link (optional)")
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                id: problem
                Layout.fillWidth: true
                color: Appearance.m3colors.m3error
                wrapMode: Text.Wrap
            }
            RippleButtonWithIcon {
                materialIcon: "add"
                mainText: Translation.tr("Add")
                onClicked: {
                    const c = { id: Timetable.newId(), subject: subject.text.trim(), day: dayChoice.currentValue,
                        from: fromField.text.trim(), to: toField.text.trim(), room: room.text.trim(), link: link.text.trim() };
                    if (!Logic.valid(c)) {
                        problem.text = Translation.tr("It needs a subject and a start before its end (24 h, like 18:00).");
                        return;
                    }
                    if (c.link && !Logic.joinLink(c)) {
                        problem.text = Translation.tr("The link has to start with https://");
                        return;
                    }
                    problem.text = "";
                    root.save(root.classes().concat([c]));
                    subject.text = ""; room.text = ""; link.text = ""; fromField.text = ""; toField.text = "";
                }
            }
        }
    }
}
