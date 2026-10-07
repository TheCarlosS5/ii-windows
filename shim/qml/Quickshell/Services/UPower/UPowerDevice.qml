// Placeholder until the Windows backend exists. Same API as Quickshell's module.
import QtQuick

QtObject {
    property int type: 0
    property bool powerSupply: false
    property real energy: 0
    property real energyCapacity: 0
    property real changeRate: 0
    property real timeToEmpty: 0
    property real timeToFull: 0
    property real percentage: 0
    property bool isPresent: false
    property int state: 0
    property real healthPercentage: 0
    property bool healthSupported: false
    property string iconName: ""
    property bool isLaptopBattery: false
    property string nativePath: ""
    property string model: ""
    property bool ready: true
}
