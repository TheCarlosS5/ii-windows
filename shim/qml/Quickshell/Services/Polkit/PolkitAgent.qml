// Placeholder until the Windows backend exists. Same API as Quickshell's module.
import QtQuick

// Windows elevation is UAC's job; this agent never receives requests.
QtObject {
    readonly property bool isActive: false
    readonly property bool isRegistered: false
    readonly property var flow: null
    property string path: ""
    signal authenticationRequestStarted()
}
