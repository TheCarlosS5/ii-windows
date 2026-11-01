import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows (plan 2026-10-31, E3): the left panel's "Hoy" tab. Your day at a glance: a greeting, the weather, the
// classes of today (with Join), the pending tasks, the battery and what is playing.
Item {
    id: root

    function greeting() {
        const h = DateTime.clock.hours;
        return h < 12 ? Translation.tr("Good morning") : h < 19 ? Translation.tr("Good afternoon") : Translation.tr("Good evening");
    }
    readonly property var pending: Todo.list.map((t, i) => ({ item: t, index: i })).filter(x => !x.item.done)

    StyledFlickable {
        anchors.fill: parent
        anchors.margins: 14
        contentHeight: column.implicitHeight
        clip: true

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 14

            // ---- greeting and weather
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: `${root.greeting()}, ${SystemInfo.username || Quickshell.env("USERNAME")}`
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Qt.locale().toString(DateTime.clock.date, "dddd d 'de' MMMM")
                        color: Appearance.colors.colSubtext
                    }
                }
                ColumnLayout {
                    visible: (Weather.data?.lastRefresh ?? 0) > 0
                    spacing: 0
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: Icons.getWeatherIcon(Weather.data.wCode) ?? "cloud"
                        iconSize: 32
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Weather.data.temp ?? ""
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            // ---- classes
            Card {
                title: Translation.tr("Classes today")
                icon: "school"
                visible: Timetable.enabled
                StyledText {
                    visible: Timetable.day.list.length === 0
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colSubtext
                    text: Timetable.classes.length === 0 ? Translation.tr("Add your classes in Configuración > Servicios > Horario de clases.")
                        : Translation.tr("No classes today.")
                }
                Repeater {
                    model: Timetable.day.list
                    delegate: RowLayout {
                        id: classRow
                        required property var modelData
                        readonly property bool now: Timetable.day.current?.id === modelData.id
                        readonly property bool next: Timetable.day.next?.id === modelData.id
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            implicitWidth: 4
                            Layout.fillHeight: true
                            radius: 2
                            color: classRow.now ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: classRow.modelData.subject
                                elide: Text.ElideRight
                                font.weight: classRow.now ? Font.Medium : Font.Normal
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: classRow.now ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                text: [`${classRow.modelData.from}–${classRow.modelData.to}`,
                                    classRow.now ? Translation.tr("now") : classRow.next ? Translation.tr("in %1 min").arg(Timetable.day.minutesToNext) : "",
                                    classRow.modelData.room ?? ""].filter(x => x).join(" · ")
                            }
                        }
                        RippleButtonWithIcon {
                            visible: Timetable.joinLink(classRow.modelData) !== "" && (classRow.now || classRow.next)
                            materialIcon: "videocam"
                            mainText: Translation.tr("Join")
                            onClicked: Timetable.join(classRow.modelData)
                        }
                    }
                }
            }

            // ---- tasks
            Card {
                title: Translation.tr("To do")
                icon: "checklist"
                StyledText {
                    visible: root.pending.length === 0
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Nothing pending.")
                }
                Repeater {
                    model: root.pending.slice(0, 6)
                    delegate: RowLayout {
                        id: taskRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 6
                        RippleButton {
                            implicitWidth: 28
                            implicitHeight: 28
                            buttonRadius: Appearance.rounding.full
                            onClicked: Todo.markDone(taskRow.modelData.index)
                            contentItem: MaterialSymbol { anchors.centerIn: parent; text: "radio_button_unchecked"; iconSize: 20; color: Appearance.colors.colOnLayer1 }
                            StyledToolTip { text: Translation.tr("Done") }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: taskRow.modelData.item.content
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
                StyledText {
                    visible: root.pending.length > 6
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: Translation.tr("and %1 more").arg(root.pending.length - 6)
                }
                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Add a task and press Enter")
                    onAccepted: {
                        if (text.trim().length > 0) Todo.addTask(text.trim());
                        text = "";
                    }
                }
            }

            // ---- battery and music
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: Battery.available || MprisController.activePlayer !== null
                MaterialSymbol {
                    visible: Battery.available
                    text: Battery.isCharging ? "battery_charging_full" : "battery_full"
                    iconSize: 20
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    visible: Battery.available
                    text: `${Math.round(Battery.percentage * 100)} %`
                    color: Appearance.colors.colOnLayer1
                }
                MaterialSymbol {
                    visible: MprisController.activePlayer !== null
                    text: MprisController.isPlaying ? "music_note" : "pause"
                    iconSize: 20
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: MprisController.activePlayer !== null
                    elide: Text.ElideRight
                    color: Appearance.colors.colSubtext
                    text: [MprisController.activePlayer?.trackTitle ?? "", MprisController.activePlayer?.trackArtist ?? ""].filter(x => x).join(" · ")
                }
            }
        }
    }

    component Card: ColumnLayout {
        id: card
        property string title
        property string icon
        default property alias content: inner.data
        Layout.fillWidth: true
        spacing: 6
        RowLayout {
            spacing: 6
            MaterialSymbol { text: card.icon; iconSize: 18; color: Appearance.colors.colPrimary }
            StyledText { text: card.title; font.weight: Font.Medium; color: Appearance.colors.colOnLayer1 }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: inner.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            ColumnLayout {
                id: inner
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                spacing: 6
            }
        }
    }
}
