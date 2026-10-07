import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland

ShellRoot {
    FloatingWindow {
        implicitWidth: 400; implicitHeight: 120; color: "#202020"
        TextField { id: a; anchors.centerIn: parent; width: 300; placeholderText: "floating"; focus: true; Component.onCompleted: forceActiveFocus() }
    }
    PanelWindow {
        anchors { top: true }
        margins.top: 300
        implicitWidth: 400; implicitHeight: 120; color: "#203020"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        TextField { id: b; anchors.centerIn: parent; width: 300; placeholderText: "panel"; focus: true; Component.onCompleted: forceActiveFocus() }
    }
}
