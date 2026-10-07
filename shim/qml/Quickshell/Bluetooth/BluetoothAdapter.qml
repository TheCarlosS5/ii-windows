// Placeholder until the Windows backend exists. Same API as Quickshell's module.
import QtQuick

QtObject {
    property string name: ""
    property string adapterId: ""
    property bool enabled: false
    property int state: 0
    property bool discoverable: false
    property bool discovering: false
    property bool pairable: false
    readonly property var devices: ListModel { property var values: [] }
}
