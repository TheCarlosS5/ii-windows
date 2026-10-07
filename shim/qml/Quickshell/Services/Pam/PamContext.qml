// Placeholder until the Windows backend exists. Same API as Quickshell's module.
import QtQuick

// No PAM on Windows; locking uses the Windows lock screen instead.
QtObject {
    property string config: "login"
    property string configDirectory: ""
    property string user: ""
    property bool active: false
    readonly property string message: ""
    readonly property bool messageIsError: false
    readonly property bool responseRequired: false
    readonly property bool responseVisible: false
    signal completed(int result)
    signal error(int error)
    signal pamMessage()
    function start() { completed(2) }
    function abort() {}
    function respond(response) {}
}
