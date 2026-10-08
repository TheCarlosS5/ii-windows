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
}
