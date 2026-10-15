import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows: the pill shown at the top while editing the desktop: what to do, and "Done".
Item {
    id: root
    anchors.fill: parent
    visible: opacity > 0
    opacity: GlobalStates.desktopEditMode ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    StyledRectangularShadow {
        target: pill
    }
    Rectangle {
        id: pill
        anchors {
            top: parent.top
            topMargin: Appearance.sizes.barHeight + 16
            horizontalCenter: parent.horizontalCenter
        }
        implicitWidth: row.implicitWidth + 20
        implicitHeight: row.implicitHeight + 12
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 10

            MaterialSymbol {
                Layout.leftMargin: 6
                text: "dashboard_customize"
                iconSize: 22
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                text: Translation.tr("Editing the desktop: drag widgets, use − and + to resize them")
                color: Appearance.colors.colOnLayer0
                font.pixelSize: Appearance.font.pixelSize.normal
            }
            RippleButton {
                implicitHeight: 34
                implicitWidth: doneText.implicitWidth + 32
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                onClicked: GlobalStates.desktopEditMode = false
                contentItem: StyledText {
                    id: doneText
                    anchors.centerIn: parent
                    text: Translation.tr("Done")
                    color: Appearance.colors.colOnPrimary
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    // Which widgets are on the desktop: switched on and off here (not from the right-click menu).
    function widgetEnabled(key) {
        return Config.options.background.widgets[key]?.enable ?? false;
    }
    function toggleWidget(key) {
        const entry = Config.options.background.widgets[key];
        const enabling = !entry.enable;
        // Free-placed widgets come up in the middle of the screen, ready to be dragged.
        if (enabling && entry.placementStrategy === "free") {
            entry.x = Math.round(root.width / 2 - 100);
            entry.y = Math.round(root.height / 2 - 100);
        }
        entry.enable = enabling;
    }

    StyledRectangularShadow {
        target: chips
    }
    Rectangle {
        id: chips
        anchors {
            top: pill.bottom
            topMargin: 10
            horizontalCenter: parent.horizontalCenter
        }
        width: Math.min(parent.width - 40, chipFlow.implicitWidth + 24)
        implicitHeight: chipFlow.implicitHeight + 20
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        Flow {
            id: chipFlow
            anchors.centerIn: parent
            width: Math.min(root.width - 64, 760)
            spacing: 6
            Repeater {
                model: [
                    { icon: "schedule", text: Translation.tr("Clock"), widget: "clock" },
                    { icon: "music_note", text: Translation.tr("Music"), widget: "media" },
                    { icon: "image", text: Translation.tr("Photo"), widget: "photo" },
                    { icon: "folder", text: Translation.tr("Recent"), widget: "folder" },
                    { icon: "partly_cloudy_day", text: Translation.tr("Weather"), widget: "weather" },
                    { icon: "apps", text: Translation.tr("Icons"), widget: "desktopIcons" },
                    { icon: "calendar_month", text: Translation.tr("Calendar"), widget: "calendar" },
                    { icon: "checklist", text: Translation.tr("To Do"), widget: "todo" },
                    { icon: "timer", text: Translation.tr("Timer"), widget: "timer" },
                    { icon: "monitoring", text: Translation.tr("Resources"), widget: "resources" },
                    { icon: "sticky_note_2", text: Translation.tr("Note"), widget: "notes" },
                    { icon: "translate", text: Translation.tr("Japanese clock"), widget: "japaneseClock" },
                ]
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool on: root.widgetEnabled(modelData.widget)
                    height: 34
                    width: chipRow.implicitWidth + 22
                    radius: Appearance.rounding.full
                    color: on ? (chipMouse.containsMouse ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
                         : chipMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                    border.width: on ? 0 : 1
                    border.color: Appearance.colors.colOutlineVariant
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.on ? "check" : chip.modelData.icon
                            iconSize: Appearance.font.pixelSize.larger
                            color: chip.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.text
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: chip.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                        }
                    }
                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.toggleWidget(chip.modelData.widget)
                    }
                }
            }
        }
    }
}
