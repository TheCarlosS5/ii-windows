import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// ii-windows (plan 2026-10-31, E2): the modes as chips in the right panel. A tap turns one on (by hand) or off; the line
// under them says why the active one is on ("por su horario", "osu! está abierto").
ColumnLayout {
    id: root
    visible: Modes.enabled && Modes.list.length > 0
    spacing: 4

    RowLayout {
        Layout.fillWidth: true
        spacing: 4
        Repeater {
            model: Modes.list
            delegate: GroupButton {
                id: chip
                required property var modelData
                readonly property bool on: Modes.activeId === modelData.id
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                horizontalPadding: 6
                verticalPadding: 8
                bounce: false
                toggled: chip.on
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundActive: Appearance.colors.colLayer2Active
                onClicked: Modes.toggle(modelData.id)
                contentItem: RowLayout {
                    spacing: 4
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: chip.modelData.icon || "auto_mode"
                        iconSize: Appearance.font.pixelSize.larger
                        fill: chip.on ? 1 : 0
                        color: chip.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Modes.nameOf(chip.modelData).split(" / ")[0]
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: chip.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                }
                StyledToolTip {
                    text: chip.on ? Translation.tr("%1 mode: tap to turn it off").arg(Modes.nameOf(chip.modelData))
                        : Translation.tr("Turn on %1 mode").arg(Modes.nameOf(chip.modelData))
                }
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        visible: Modes.active !== null && Modes.reason !== "manual"
        elide: Text.ElideRight
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: Modes.reason === "app" ? Translation.tr("On because %1 is open").arg(Modes.reasonDetail)
            : Modes.reason === "schedule" ? Translation.tr("On by its hours (%1)").arg(Modes.reasonDetail)
            : Modes.reason === "presenting" ? Translation.tr("On while Windows is presenting") : ""
    }
}
