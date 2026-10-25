pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar

// ii-windows (plan 2.1): the bar's things at the bottom, beside the dock, instead of a bar along the top
// (Settings > Bar > Bar position > Beside the dock, bar.besideDock). A panel of its own, not part of the dock: two
// pills in the bottom corners, as tall as the dock and level with it, that never magnify. Left: the left sidebar and
// the resources (scroll for brightness). Right: the tray, the indicators (network, sound, Bluetooth, notifications;
// they open the right sidebar), the battery and the clock (scroll for volume). The same widgets and menus as the bar:
// bar.bottom is set with this mode, so their popups and the tray menus open upwards.
//
// This panel reserves the bottom strip (Appearance.sizes.dockBarThickness, the pinned dock's own thickness) and the
// dock sits in that same strip without reserving it again (Dock.qml), so neither pushes the other up.
Scope {
    id: root

    component Pill: Rectangle {
        id: pill
        default property alias items: pillRow.data
        property real enter: 0 // 0 = below the screen, 1 = in place
        height: Appearance.sizes.dockBarPillHeight
        implicitWidth: pillRow.implicitWidth + 16
        width: implicitWidth
        radius: Appearance.rounding.large // as the dock
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        transform: Translate {
            y: (1 - pill.enter) * (pill.height + Appearance.sizes.hyprlandGapsOut + 12)
        }
        Behavior on width {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Component.onCompleted: enter = 1
        Behavior on enter {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this) // M3 Expressive spring
        }
        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: 4
        }
    }

    Variants {
        // For each monitor the bar is on
        model: {
            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }
        LazyLoader {
            id: barLoader
            active: GlobalStates.barOpen && !GlobalStates.screenLocked
            required property ShellScreen modelData
            component: PanelWindow {
                id: barRoot
                screen: barLoader.modelData
                WlrLayershell.namespace: "quickshell:dockBar"
                color: "transparent"
                anchors {
                    bottom: true
                    left: true
                    right: true
                }
                // Room above the pills for their shadow; only the pills take the mouse.
                implicitHeight: Appearance.sizes.dockBarThickness + Appearance.sizes.elevationMargin
                exclusiveZone: Appearance.sizes.dockBarThickness
                mask: Region {
                    regions: [
                        Region { item: leftPill },
                        Region { item: rightPill }
                    ]
                }

                Component.onCompleted: GlobalFocusGrab.addPersistent(barRoot)
                Component.onDestruction: GlobalFocusGrab.removePersistent(barRoot)

                readonly property real edgeGap: Appearance.sizes.hyprlandGapsOut + 1
                readonly property bool narrow: (barRoot.screen?.width ?? 1920) < 1280

                StyledRectangularShadow {
                    target: leftPill
                    visible: leftPill.visible
                }
                Pill {
                    id: leftPill
                    visible: leftSidebarButton.visible || resources.visible
                    anchors {
                        left: parent.left
                        bottom: parent.bottom
                        leftMargin: barRoot.edgeGap
                        bottomMargin: barRoot.edgeGap
                    }

                    FocusedScrollMouseArea { // scroll to change brightness, as on the bar's left side
                        Layout.fillHeight: true
                        implicitWidth: leftRow.implicitWidth
                        implicitHeight: leftRow.implicitHeight
                        onScrollDown: Brightness.decreaseBrightness()
                        onScrollUp: Brightness.increaseBrightness()
                        onMovedAway: GlobalStates.osdBrightnessOpen = false
                        RowLayout {
                            id: leftRow
                            anchors.centerIn: parent
                            spacing: 4
                            LeftSidebarButton {
                                id: leftSidebarButton
                                Layout.alignment: Qt.AlignVCenter
                            }
                            Resources {
                                id: resources
                                visible: !barRoot.narrow
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                    }
                }

                StyledRectangularShadow {
                    target: rightPill
                }
                Pill {
                    id: rightPill
                    anchors {
                        right: parent.right
                        bottom: parent.bottom
                        rightMargin: barRoot.edgeGap
                        bottomMargin: barRoot.edgeGap
                    }

                    FocusedScrollMouseArea { // scroll to change volume, as on the bar's right side
                        id: rightArea
                        Layout.fillHeight: true
                        implicitWidth: rightRow.implicitWidth
                        implicitHeight: rightRow.implicitHeight
                        onScrollDown: Audio.decrementVolume()
                        onScrollUp: Audio.incrementVolume()
                        onMovedAway: GlobalStates.osdVolumeOpen = false
                        RowLayout {
                            id: rightRow
                            anchors.centerIn: parent
                            spacing: 6

                            SysTray {
                                Layout.fillHeight: true
                                invertSide: true
                            }

                            RippleButton { // the right sidebar, with the bar's indicators
                                id: rightSidebarButton
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: indicators.implicitWidth + 10 * 2
                                implicitHeight: indicators.implicitHeight + 5 * 2
                                buttonRadius: Appearance.rounding.full
                                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                                colBackgroundHover: Appearance.colors.colLayer1Hover
                                colRipple: Appearance.colors.colLayer1Active
                                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                                colRippleToggled: Appearance.colors.colSecondaryContainerActive
                                toggled: GlobalStates.sidebarRightOpen
                                property color colText: toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0
                                onPressed: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen

                                RowLayout {
                                    id: indicators
                                    anchors.centerIn: parent
                                    spacing: 12
                                    MaterialSymbol {
                                        visible: Audio.sink?.audio?.muted ?? false
                                        text: "volume_off"
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: rightSidebarButton.colText
                                    }
                                    MaterialSymbol {
                                        visible: Audio.source?.audio?.muted ?? false
                                        text: "mic_off"
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: rightSidebarButton.colText
                                    }
                                    NotificationUnreadCount {
                                        visible: Notifications.silent || Notifications.unread > 0
                                    }
                                    MaterialSymbol {
                                        text: Network.materialSymbol
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: rightSidebarButton.colText
                                    }
                                    MaterialSymbol {
                                        visible: BluetoothStatus.available
                                        text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: rightSidebarButton.colText
                                    }
                                }
                            }

                            BatteryIndicator {
                                visible: Battery.available
                                Layout.alignment: Qt.AlignVCenter
                            }

                            MouseArea { // the clock opens the right sidebar too, as on the bar
                                Layout.alignment: Qt.AlignVCenter
                                Layout.rightMargin: 4
                                implicitWidth: clock.implicitWidth
                                implicitHeight: clock.implicitHeight
                                onPressed: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
                                ClockWidget {
                                    id: clock
                                    anchors.centerIn: parent
                                    showDate: Config.options.bar.verbose && !barRoot.narrow
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
