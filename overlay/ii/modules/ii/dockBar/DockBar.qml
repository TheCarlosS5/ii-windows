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
// pills in the bottom corners, as tall as the dock and level with it, that never magnify. The same widgets and menus
// as the bar: bar.bottom is set with this mode, so their popups and the tray menus open upwards.
//   Left (scroll for brightness): left sidebar, virtual desktops, resources, utility buttons, media.
//   Right (scroll for volume): tray, indicators (network, sound, Bluetooth, notifications; they open the right
//   sidebar), battery, clock with the date.
// Only with the dock at the bottom (Appearance.barBesideDock); with the dock at a side ii shows the bar at the bottom.
//
// The pills never reach the dock: each gets the room between its corner and the dock, magnified icons included (the
// dock's span, GlobalStates.dockSpanLeft/Right), and shows the fullest set of its things that fits. Short of room the
// right one first drops the date, then gathers the whole tray behind its "more" button; the left one drops media,
// utility buttons, resources, then the desktops. Every thing sits in a Slot whose measured width does not depend on
// whether it is shown, so the choice is computed, never found by trying.
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
        clip: true
        transform: Translate {
            y: (1 - pill.enter) * (pill.height + Appearance.sizes.hyprlandGapsOut + 12)
        }
        Component.onCompleted: enter = 1
        Behavior on enter {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this) // M3 Expressive spring
        }
        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: 0
        }
    }

    // One thing in a pill. Closed, it takes no room (and no input) but keeps its measured width (full).
    component Slot: Item {
        id: slot
        property bool shown: true
        property real gap: 6 // room before it
        property real fixedWidth: -1 // for things as wide as their text (media): this width, elided
        default property alias content: inner.data
        readonly property Item thing: inner.children.length > 0 ? inner.children[0] : null
        readonly property real full: (slot.fixedWidth >= 0 ? slot.fixedWidth : (slot.thing?.implicitWidth ?? 0)) + slot.gap
        Layout.fillHeight: true
        implicitWidth: slot.shown ? slot.full : 0
        implicitHeight: slot.thing?.implicitHeight ?? 0
        opacity: slot.shown ? 1 : 0
        enabled: slot.shown
        clip: true
        Behavior on implicitWidth {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Item {
            id: inner
            x: slot.gap
            width: slot.full - slot.gap
            height: parent.height
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
                // The room for each pill: from its corner to the dock (its magnified span), with a gap.
                readonly property real screenWidth: barRoot.screen?.width ?? 1920
                readonly property real dockHalf: (Config.options.dock.enable ?? true) ? Math.max(0, (GlobalStates.dockSpanRight - GlobalStates.dockSpanLeft) / 2) : 0
                readonly property real room: barRoot.screenWidth / 2 - barRoot.dockHalf - barRoot.edgeGap - 12

                // The fullest level whose shown slots fit: levels[i] lists the slots shown at that level.
                function fit(levels, padding) {
                    for (let i = 0; i < levels.length; i++) {
                        const need = levels[i].reduce((sum, slot) => sum + (slot.thing?.visible === false ? 0 : slot.full), padding);
                        if (need <= barRoot.room)
                            return i;
                    }
                    return levels.length - 1;
                }
                readonly property int rightLevel: barRoot.fit([
                    [traySlot, indicatorsSlot, batterySlot, dateClockSlot],
                    [traySlot, indicatorsSlot, batterySlot, clockSlot],
                    [compactTraySlot, indicatorsSlot, batterySlot, clockSlot]
                ], 16 + 4)
                readonly property bool mediaPlaying: MprisController.activePlayer !== null && MprisController.activePlayer !== undefined
                readonly property int leftLevel: barRoot.fit([
                    [sidebarSlot, workspacesSlot, resourcesSlot, utilsSlot, mediaSlot],
                    [sidebarSlot, workspacesSlot, resourcesSlot, utilsSlot],
                    [sidebarSlot, workspacesSlot, resourcesSlot],
                    [sidebarSlot, workspacesSlot],
                    [sidebarSlot]
                ], 16 + 4)

                StyledRectangularShadow {
                    target: leftPill
                }
                Pill {
                    id: leftPill
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
                            anchors.fill: parent
                            spacing: 0
                            Slot {
                                id: sidebarSlot
                                gap: 2
                                shown: thing?.visible ?? false
                                LeftSidebarButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Slot {
                                id: workspacesSlot
                                shown: barRoot.leftLevel <= 3
                                Workspaces {
                                    vertical: false
                                    anchors.verticalCenter: parent.verticalCenter
                                    MouseArea { // right-click: the overview, as on the bar
                                        anchors.fill: parent
                                        acceptedButtons: Qt.RightButton
                                        onPressed: GlobalStates.toggleOverview("apps")
                                    }
                                }
                            }
                            Slot {
                                id: resourcesSlot
                                shown: barRoot.leftLevel <= 2
                                Resources {
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Slot {
                                id: utilsSlot
                                shown: barRoot.leftLevel <= 1 && Config.options.bar.verbose
                                UtilButtons {
                                    visible: Config.options.bar.verbose
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Slot {
                                id: mediaSlot
                                fixedWidth: 220
                                shown: barRoot.leftLevel === 0 && barRoot.mediaPlaying
                                Media {
                                    visible: barRoot.mediaPlaying
                                    width: 220
                                    height: parent.height
                                }
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
                        Layout.fillHeight: true
                        implicitWidth: rightRow.implicitWidth
                        implicitHeight: rightRow.implicitHeight
                        onScrollDown: Audio.decrementVolume()
                        onScrollUp: Audio.incrementVolume()
                        onMovedAway: GlobalStates.osdVolumeOpen = false
                        RowLayout {
                            id: rightRow
                            anchors.fill: parent
                            spacing: 0

                            Slot {
                                id: traySlot
                                gap: 4
                                shown: barRoot.rightLevel <= 1
                                SysTray {
                                    height: parent.height
                                    invertSide: true
                                    showSeparator: false
                                }
                            }
                            Slot { // short of room: the whole tray behind its "more" button
                                id: compactTraySlot
                                gap: 4
                                shown: barRoot.rightLevel === 2 && TrayService.pinnedItems.length + TrayService.unpinnedItems.length > 0
                                SysTray {
                                    height: parent.height
                                    invertSide: true
                                    showSeparator: false
                                    pinnedItems: []
                                    unpinnedItems: TrayService.pinnedItems.concat(TrayService.unpinnedItems)
                                }
                            }

                            Slot { // the right sidebar, with the bar's indicators
                                id: indicatorsSlot
                                RippleButton {
                                    id: rightSidebarButton
                                    anchors.verticalCenter: parent.verticalCenter
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
                            }

                            Slot {
                                id: batterySlot
                                shown: Battery.available
                                BatteryIndicator {
                                    visible: Battery.available
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            // The clock opens the right sidebar too, as on the bar. With the date, or without when
                            // short of room (two clocks, so each one's width is known whether shown or not).
                            Slot {
                                id: dateClockSlot
                                shown: barRoot.rightLevel === 0
                                MouseArea {
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitWidth: dateClock.implicitWidth + 4
                                    implicitHeight: dateClock.implicitHeight
                                    onPressed: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
                                    ClockWidget {
                                        id: dateClock
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        showDate: Config.options.bar.verbose
                                    }
                                }
                            }
                            Slot {
                                id: clockSlot
                                shown: barRoot.rightLevel > 0
                                MouseArea {
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitWidth: timeClock.implicitWidth + 4
                                    implicitHeight: timeClock.implicitHeight
                                    onPressed: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
                                    ClockWidget {
                                        id: timeClock
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        showDate: false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
