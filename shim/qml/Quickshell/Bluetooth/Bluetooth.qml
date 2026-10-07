// Placeholder until the Windows backend exists. Same API as Quickshell's module.
pragma Singleton
import QtQuick

QtObject {
    readonly property var defaultAdapter: null
    readonly property var adapters: ListModel { property var values: [] }
    readonly property var devices: ListModel { property var values: [] }
}
