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

    // ii-windows (plan 2026-10-31, D2): what the card shows stays still while an app covers this screen (no repaint
    // of the wallpaper window each time the numbers change), and catches up as soon as the desktop shows.
    readonly property var liveUsage: ({
        cpu: ResourceUsage.cpuUsage,
        memory: ResourceUsage.memoryUsedPercentage,
        memoryUsed: ResourceUsage.memoryUsed,
        memoryTotal: ResourceUsage.memoryTotal,
        swap: ResourceUsage.swapUsedPercentage,
        swapUsed: ResourceUsage.swapUsed,
        swapTotal: ResourceUsage.swapTotal
    })
    property var usage: root.liveUsage
    Binding {
        target: root
        property: "usage"
        value: root.liveUsage
        when: !root.desktopCovered
        restoreMode: Binding.RestoreNone
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
                value: root.usage.cpu
                detail: `${Math.round(root.usage.cpu * 100)}%`
            }
            Gauge {
                icon: "memory"
                label: Translation.tr("RAM")
                value: root.usage.memory
                detail: `${root.gb(root.usage.memoryUsed)} / ${root.gb(root.usage.memoryTotal)} GB`
            }
            Gauge {
                visible: root.showSwap && root.usage.swapTotal > 1
                icon: "swap_horiz"
                label: Translation.tr("Swap")
                value: root.usage.swap
                detail: `${root.gb(root.usage.swapUsed)} / ${root.gb(root.usage.swapTotal)} GB`
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
