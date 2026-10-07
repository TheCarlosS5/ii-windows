import QtQuick
import Quickshell
ShellRoot {
    Variants { model: Quickshell.screens
      FloatingWindow { required property var modelData; screen: modelData; visible: true; implicitWidth: 300; implicitHeight: 120; color: "#386a20"; Text { anchors.centerIn: parent; text: "t2 variants"; color: "white" } } }
    Timer { interval: 6000; running: true; onTriggered: Qt.quit() }
}
