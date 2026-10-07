import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    Variants {
        model: Quickshell.screens
        FloatingWindow {
            required property var modelData
            screen: modelData
            implicitWidth: 520
            implicitHeight: 200
            color: "#1c1b1f"
            Column {
                anchors.centerIn: parent
                spacing: 8
                Text { color: "#e6e1e5"; font.pixelSize: 20; text: "Quickshell on Windows — screen " + modelData.name }
                Text { color: "#d0bcff"; font.pixelSize: 16; text: "Singleton says: " + Greeter.message }
                Text { color: "#cac4d0"; font.pixelSize: 14; text: "Process: " + proc.out }
                Text { color: "#cac4d0"; font.pixelSize: 14; text: "FileView bytes: " + file.text().length }
            }
        }
    }
    Process {
        id: proc
        property string out: "…"
        running: true
        command: ["cmd", "/c", "ver"]
        stdout: StdioCollector { onStreamFinished: proc.out = text.trim() }
    }
    FileView { id: file; path: Quickshell.shellPath("shell.qml") }
    Timer { interval: 9000; running: true; onTriggered: Qt.quit() }
}
