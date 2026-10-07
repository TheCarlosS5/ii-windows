// Placeholder until the Windows backend exists. Same API as Quickshell's module.
pragma Singleton
import QtQuick

QtObject {
    property int profile: 1
    readonly property bool hasPerformanceProfile: false
    readonly property int degradationReason: 0
    readonly property var holds: []
}
