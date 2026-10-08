pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

// ii-windows: CPU, memory and swap use as ii's circular indicators, on the desktop.
AbstractBackgroundWidget {
    id: root

    configEntryName: "resources"
    readonly property bool showSwap: configEntry.showSwap ?? true
    implicitWidth: row.implicitWidth + 36
    implicitHeight: row.implicitHeight + 32

    function gb(kb) {
        return (kb / 1048576).toFixed(1);
    }

    StyledDropShadow {
        target: card
    }
    Rectangle {
        id: card
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer0

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 18

            Gauge {
                icon: "planner_review"
                label: Translation.tr("CPU")
                value: ResourceUsage.cpuUsage
                detail: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
            }
            Gauge {
                icon: "memory"
                label: Translation.tr("RAM")
                value: ResourceUsage.memoryUsedPercentage
                detail: `${root.gb(ResourceUsage.memoryUsed)} / ${root.gb(ResourceUsage.memoryTotal)} GB`
            }
            Gauge {
                visible: root.showSwap && ResourceUsage.swapTotal > 1
                icon: "swap_horiz"
                label: Translation.tr("Swap")
                value: ResourceUsage.swapUsedPercentage
                detail: `${root.gb(ResourceUsage.swapUsed)} / ${root.gb(ResourceUsage.swapTotal)} GB`
            }
        }
    }

    component Gauge: ColumnLayout {
        id: gauge
        property string icon
        property string label
        property real value
        property string detail
        spacing: 6

        CircularProgress {
            Layout.alignment: Qt.AlignHCenter
            implicitSize: 76
            lineWidth: 7
            value: gauge.value
            colPrimary: gauge.value > 0.9 ? Appearance.colors.colError : Appearance.colors.colPrimary
            colSecondary: Appearance.colors.colSecondaryContainer

            MaterialSymbol {
                anchors.centerIn: parent
                text: gauge.icon
                iconSize: 26
                fill: 1
                color: Appearance.colors.colOnLayer1
            }
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: gauge.label
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: gauge.detail
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
