// Placeholder until the Windows backend exists. Same API as Quickshell's module.
pragma Singleton
import QtQuick

QtObject {
    readonly property UPowerDevice displayDevice: UPowerDevice {}
    readonly property var devices: ListModel { property var values: [] }
    readonly property bool onBattery: false
}
