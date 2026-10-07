// Placeholder until the Windows backend exists. Same API as Quickshell's module.
import QtQuick

QtObject {
    property string address: ""
    property string deviceName: ""
    property string name: ""
    property string icon: ""
    property bool connected: false
    property bool paired: false
    property bool bonded: false
    property bool trusted: false
    property bool blocked: false
    property bool pairing: false
    property bool batteryAvailable: false
    property real battery: 0
    property int state: 0
    function connect() {}
    function disconnect() {}
    function pair() {}
    function cancelPair() {}
    function forget() {}
}
