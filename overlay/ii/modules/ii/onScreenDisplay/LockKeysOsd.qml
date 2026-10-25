import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Wayland

// ii-windows: a small pill under the bar when Caps Lock, Num Lock or Scroll Lock is turned on or off
// ("Bloq Mayús activado"), so a mistyped password or a dead numpad is no longer a mystery; and on a laptop when the
// charger is plugged in or out, with the battery level ("Cargando · 45 %").
Scope {
    id: root
    property string message: ""
    property string icon: "keyboard_capslock"
    property bool on: false

    function show(message, icon, on) {
        root.message = message;
        root.icon = icon;
        root.on = on;
        hideTimer.restart();
        loader.shown = true; // before the window exists: its opacity binding reads it at creation
        loader.active = true;
    }

    // The charger: Windows tells the battery service at once (GUID_ACDC_POWER_SOURCE). The first reading is the
    // state at start-up, not a change. The level and "charging" are read a moment later: they follow the plug a
    // little after it ("Plugged in" instead of "Charging", or the level from before).
    property var lastOnBattery: undefined
    function chargerChanged() {
        if (!Battery.available)
            return;
        const onBattery = UPower.onBattery;
        if (root.lastOnBattery === undefined || root.lastOnBattery === onBattery) {
            root.lastOnBattery = onBattery;
            return;
        }
        root.lastOnBattery = onBattery;
        if (Config.options.osd.charger ?? true)
            chargerSettle.restart();
    }
    Timer {
        id: chargerSettle
        interval: 1000
        onTriggered: root.showCharger()
    }
    function showCharger() {
        const onBattery = UPower.onBattery; // plugged in and out again meanwhile: what it is now
        const percent = Math.round(Battery.percentage * 100);
        if (onBattery)
            root.show(Translation.tr("On battery · %1%").arg(percent), "battery_full", false);
        else if (Battery.isCharging)
            root.show(Translation.tr("Charging · %1%").arg(percent), "battery_charging_full", true);
        else
            root.show(Translation.tr("Plugged in · %1%").arg(percent), "power", true);
    }
    Component.onCompleted: chargerChanged()
    Connections {
        target: UPower
        function onOnBatteryChanged() {
            root.chargerChanged();
        }
    }

    Connections {
        target: LockKeys
        function onToggled(key, on) {
            if (!(Config.options.osd.lockKeys ?? true)) return;
            if (key === "caps")
                root.show(on ? Translation.tr("Caps Lock on") : Translation.tr("Caps Lock off"), "keyboard_capslock", on);
            else if (key === "num")
                root.show(on ? Translation.tr("Num Lock on") : Translation.tr("Num Lock off"), "pin", on);
            else
                root.show(on ? Translation.tr("Scroll Lock on") : Translation.tr("Scroll Lock off"), "swap_vert", on);
        }
    }
    // The media keys, when ii takes them (shortcuts.ini [audio] mediakeys = ii, ii-host): the active player, and the
    // pill says what is playing instead of Windows' media flyout. The player's state follows a moment later.
    function media(action) {
        if (action === "play") MprisController.togglePlaying();
        else if (action === "next") MprisController.next();
        else MprisController.previous();
        mediaShow.action = action;
        mediaShow.restart();
    }
    Timer {
        id: mediaShow
        property string action: "play"
        interval: 400
        onTriggered: {
            const player = MprisController.activePlayer;
            if (!player) {
                root.show(Translation.tr("No media"), "music_off", false);
                return;
            }
            const title = player.trackTitle || player.identity || Translation.tr("Media");
            const icon = action === "next" ? "skip_next" : action === "previous" ? "skip_previous" : (player.isPlaying ? "play_arrow" : "pause");
            root.show(title, icon, player.isPlaying);
        }
    }
    GlobalShortcut {
        name: "mediaPlayPause"
        description: "Media key: play/pause (when ii takes the media keys)"
        onPressed: root.media("play")
    }
    GlobalShortcut {
        name: "mediaNext"
        description: "Media key: next track"
        onPressed: root.media("next")
    }
    GlobalShortcut {
        name: "mediaPrevious"
        description: "Media key: previous track"
        onPressed: root.media("previous")
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
