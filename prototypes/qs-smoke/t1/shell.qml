import QtQuick
import Quickshell
ShellRoot {
    FloatingWindow { implicitWidth: 300; implicitHeight: 120; color: "#6750a4"; Text { anchors.centerIn: parent; text: "t1 plain"; color: "white" } }
    Timer { interval: 6000; running: true; onTriggered: Qt.quit() }
}
