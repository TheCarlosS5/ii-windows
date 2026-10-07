// Prototype A: an ii-shaped bar on the real stack (Quickshell for Windows).
// - PanelWindow anchored top, exclusive zone = bar height (AppBar reservation)
// - window is taller than the bar: the rounded screen corners under it are transparent
//   and click-through (mask: Region { item: barBackground }), exactly like ii's Bar.qml
// - "xray" blur: blurred wallpaper sampled at the bar's screen position (Hyprland xray=true)
// Quits by itself after 25 s.
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell

ShellRoot {
    id: root
    readonly property int barHeight: 40
    readonly property int rounding: 23
    readonly property color barColor: Qt.rgba(0.08, 0.07, 0.10, 0.62)
    readonly property color pill: Qt.rgba(0.17, 0.16, 0.19, 0.85)
    readonly property color primary: "#d0bcff"
    readonly property color textOnPrimary: "#381e72"
    readonly property color text: "#e6e1e9"

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            anchors { top: true; left: true; right: true }
            implicitHeight: root.barHeight + root.rounding
            exclusiveZone: root.barHeight
            color: "transparent"
            mask: Region { item: barBackground }

            // Blurred wallpaper, rendered once per screen, shown through the translucent bar.
            Image {
                id: wallpaper
                source: Qt.resolvedUrl("wallpaper.jpg")
                width: bar.screen.width
                height: bar.screen.height
                fillMode: Image.PreserveAspectCrop
                visible: false
            }
            MultiEffect {
                id: blurredWallpaper
                source: wallpaper
                width: wallpaper.width
                height: wallpaper.height
                blurEnabled: true
                blur: 1.0
                blurMax: 64
                saturation: 0.2
                visible: false
                layer.enabled: true
            }

            Item {
                id: barBackground
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: root.barHeight
                clip: true

                ShaderEffectSource {
                    sourceItem: blurredWallpaper
                    sourceRect: Qt.rect(0, 0, barBackground.width, barBackground.height)
                    anchors.fill: parent
                }
                Rectangle { anchors.fill: parent; color: root.barColor }

                Row {
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Rectangle {
                        width: 34; height: 30; radius: 15; color: root.pill
                        Text { anchors.centerIn: parent; text: "✦"; color: root.primary; font.pixelSize: 16 }
                    }
                    Rectangle {
                        width: title.implicitWidth + 24; height: 30; radius: 15; color: root.pill
                        Text { id: title; anchors.centerIn: parent; text: "Quickshell · Windows backend"; color: root.text; font.pixelSize: 14 }
                    }
                }

                Rectangle {
                    id: workspaces
                    anchors.centerIn: parent
                    width: wsRow.implicitWidth + 12; height: 30; radius: 15; color: root.pill
                    property int active: 0
                    Rectangle {
                        // the sliding active indicator, as in ii
                        x: 6 + workspaces.active * 30; y: 2; width: 26; height: 26; radius: 13
                        color: root.primary
                        Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
                    }
                    Row {
                        id: wsRow
                        x: 6; anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Repeater {
                            model: 6
                            Text {
                                width: 26; horizontalAlignment: Text.AlignHCenter
                                text: index + 1; font.pixelSize: 13
                                color: workspaces.active === index ? root.textOnPrimary : root.text
                            }
                        }
                    }
                    Timer { interval: 900; running: true; repeat: true; onTriggered: workspaces.active = (workspaces.active + 1) % 6 }
                }

                Rectangle {
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    width: clock.implicitWidth + 24; height: 30; radius: 15; color: root.pill
                    Text {
                        id: clock; anchors.centerIn: parent; color: root.text; font.pixelSize: 14
                        text: Qt.formatTime(new Date(), "hh:mm:ss")
                        Timer { interval: 1000; running: true; repeat: true; onTriggered: clock.text = Qt.formatTime(new Date(), "hh:mm:ss") }
                    }
                }
            }

            // Rounded screen corners under the bar (ii's RoundCorner), same blurred fill.
            Repeater {
                model: [0, 1]
                Item {
                    required property int modelData
                    width: root.rounding; height: root.rounding
                    y: root.barHeight
                    x: modelData === 0 ? 0 : bar.width - width
                    clip: true
                    ShaderEffectSource {
                        sourceItem: blurredWallpaper
                        sourceRect: Qt.rect(parent.x, parent.y, parent.width, parent.height)
                        anchors.fill: parent
                        layer.enabled: true
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: cornerMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                    }
                    Item {
                        id: cornerMask
                        anchors.fill: parent; visible: false; layer.enabled: true; layer.smooth: true
                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                fillColor: "white"; strokeWidth: -1
                                startX: modelData === 0 ? 0 : root.rounding; startY: 0
                                PathLine { x: modelData === 0 ? root.rounding : 0; y: 0 }
                                PathArc {
                                    x: modelData === 0 ? 0 : root.rounding; y: root.rounding
                                    radiusX: root.rounding; radiusY: root.rounding
                                    direction: modelData === 0 ? PathArc.Counterclockwise : PathArc.Clockwise
                                }
                                PathLine { x: modelData === 0 ? 0 : root.rounding; y: 0 }
                            }
                        }
                    }
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: root.barColor; strokeWidth: -1
                            startX: modelData === 0 ? 0 : root.rounding; startY: 0
                            PathLine { x: modelData === 0 ? root.rounding : 0; y: 0 }
                            PathArc {
                                x: modelData === 0 ? 0 : root.rounding; y: root.rounding
                                radiusX: root.rounding; radiusY: root.rounding
                                direction: modelData === 0 ? PathArc.Counterclockwise : PathArc.Clockwise
                            }
                            PathLine { x: modelData === 0 ? 0 : root.rounding; y: 0 }
                        }
                    }
                }
            }
        }
    }

    Timer { interval: 25000; running: true; onTriggered: Qt.quit() }
}
