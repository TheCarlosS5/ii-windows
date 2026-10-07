// Placeholder until the Windows backend exists. Same API as Quickshell's module.
import QtQuick

QtObject {
    property string id: ""
    property string title: ""
    property int status: 0
    property int category: 0
    property string icon: ""
    property string tooltipTitle: ""
    property string tooltipDescription: ""
    property var menu: null
    property bool hasMenu: false
    property bool onlyMenu: false
    function activate() {}
    function secondaryActivate() {}
    function scroll(delta, horizontal) {}
    function display(parentWindow, relativeX, relativeY) {}
}
