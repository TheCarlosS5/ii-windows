import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// ii-windows: a small pill under the bar when Caps Lock, Num Lock or Scroll Lock is turned on or off
// ("Bloq Mayús activado"), so a mistyped password or a dead numpad is no longer a mystery.
Scope {
    id: root
    property string message: ""
    property string icon: "keyboard_capslock"
    property bool on: false

    Connections {
        target: LockKeys
        function onToggled(key, on) {
            if (!(Config.options.osd.lockKeys ?? true)) return;
            if (key === "caps") {
                root.message = on ? Translation.tr("Caps Lock on") : Translation.tr("Caps Lock off");
                root.icon = "keyboard_capslock";
            } else if (key === "num") {
                root.message = on ? Translation.tr("Num Lock on") : Translation.tr("Num Lock off");
                root.icon = "pin";
            } else {
                root.message = on ? Translation.tr("Scroll Lock on") : Translation.tr("Scroll Lock off");
                root.icon = "swap_vert";
            }
            root.on = on;
            hideTimer.restart();
            loader.shown = true; // before the window exists: its opacity binding reads it at creation
            loader.active = true;
        }
    }
    Timer {
        id: hideTimer
        interval: 1700
        onTriggered: loader.shown = false
    }

    Loader {
        id: loader
        property bool shown: false
        active: false
        onActiveChanged: if (active) shown = true
        sourceComponent: PanelWindow {
            id: osdRoot
            color: "transparent"
            WlrLayershell.namespace: "quickshell:lockKeysOsd"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            anchors {
                top: !Config.options.bar.bottom
                bottom: Config.options.bar.bottom
            }
            margins {
                top: Appearance.sizes.barHeight + 8
                bottom: Appearance.sizes.barHeight + 8
            }
            implicitWidth: pillWrap.implicitWidth
            implicitHeight: pillWrap.implicitHeight

            Item {
                id: pillWrap
                implicitWidth: pill.implicitWidth + Appearance.sizes.elevationMargin * 2
                implicitHeight: pill.implicitHeight + Appearance.sizes.elevationMargin * 2
                opacity: loader.shown ? 1 : 0
                onOpacityChanged: if (opacity === 0 && !loader.shown) loader.active = false
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                StyledRectangularShadow {
                    target: pill
                }
                Rectangle {
                    id: pill
                    anchors.centerIn: parent
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer0
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    implicitHeight: row.implicitHeight + 16
                    implicitWidth: row.implicitWidth + 36

                    RowLayout {
                        id: row
                        anchors.centerIn: parent
                        spacing: 10
                        Rectangle {
                            implicitWidth: 34
                            implicitHeight: 34
                            radius: width / 2
                            color: root.on ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: root.icon
                                iconSize: 22
                                fill: root.on ? 1 : 0
                                color: root.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                            }
                        }
                        StyledText {
                            text: root.message
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                }
            }
        }
    }
}
