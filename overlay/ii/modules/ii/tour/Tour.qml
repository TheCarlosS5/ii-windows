pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// ii-windows: a short guided tour, the first time ii starts (and from Settings > About, or
// `qs ipc call tour open`). Many people find ii "like flying a helicopter" at first: more things on the
// screen than Windows has. Each step lights up one part of the screen and says what it is for.
Scope {
    id: root
    property bool open: false
    property int step: 0
    property bool offerLight: false // decided when the tour starts, so the steps do not change under the user

    // spot: which part of the screen is lit: none | bar | barCenter | barRight | dock | right | left | desktop
    // The light-mode step goes before the last one, only on a modest PC that does not use it yet.
    readonly property var steps: offerLight ? baseSteps.slice(0, -1).concat([lightStep], baseSteps.slice(-1)) : baseSteps
    readonly property var lightStep: ({
            icon: "speed",
            spot: "none",
            title: Translation.tr("A lighter ii for this PC?"),
            text: Translation.tr("This PC has %1. The light mode turns off animations and transparencies so ii answers faster and leaves more for your programs. You can change it any time in Settings > Appearance > Performance.").arg(Performance.hardwareText),
            keys: [],
            action: "light"
        })
    readonly property var baseSteps: [
        {
            icon: "waving_hand",
            spot: "none",
            title: Translation.tr("Welcome to ii"),
            text: Translation.tr("ii replaces Windows' taskbar, Start menu and desktop with a different layout. Your apps, files and settings are still Windows'. This tour takes one minute and shows what is where."),
            keys: []
        },
        {
            icon: "toast",
            spot: "bar",
            title: Translation.tr("The top bar"),
            text: Translation.tr("On the left, the active app and the button for the AI sidebar. In the centre, CPU and memory, the desktops and the clock. On the right, the system tray, battery and the quick settings."),
            keys: []
        },
        {
            icon: "view_carousel",
            spot: "barCenter",
            title: Translation.tr("Desktops"),
            text: Translation.tr("Each dot is a virtual desktop with its own windows. Click a dot to go there, or scroll over them. Only the desktops that exist are shown."),
            keys: [["Win", "1…9"]]
        },
        {
            icon: "search",
            spot: "desktop",
            title: Translation.tr("Search and open apps"),
            text: Translation.tr("Press the Windows key: type to find apps, files or do maths, then Enter. Press Win+Tab for the windows of this desktop, and the button at the bottom for all the apps."),
            keys: [["Win"], ["Win", "Tab"]]
        },
        {
            icon: "call_to_action",
            spot: "dock",
            title: Translation.tr("The dock"),
            text: Translation.tr("Your pinned and running apps. The icons grow under the cursor. Click opens, right click offers more, drag to reorder, and the pin keeps it always visible. It can sit at the bottom, left or right (Settings > Dock)."),
            keys: []
        },
        {
            icon: "tune",
            spot: "right",
            title: Translation.tr("Quick settings and notifications"),
            text: Translation.tr("Wi-Fi, Bluetooth, volume, night light, notifications and the calendar. The switches act right there; open it from the top-right corner."),
            keys: [["Win", "N"]]
        },
        {
            icon: "smart_toy",
            spot: "left",
            title: Translation.tr("AI assistant and tools"),
            text: Translation.tr("Chat with an AI model (add your free Gemini key with /key), translate text and more. Open it from the top-left button."),
            keys: [["Win", "A"]]
        },
        {
            icon: "dashboard_customize",
            spot: "desktop",
            title: Translation.tr("Your desktop"),
            text: Translation.tr("Right click on the desktop for new folders, personalising, the Windows menu and more. \"Edit desktop\" adds clocks, weather, notes and other widgets and lets you move them."),
            keys: []
        },
        {
            icon: "keyboard",
            spot: "none",
            title: Translation.tr("Shortcuts"),
            text: Translation.tr("Win+/ shows every shortcut. Win+I opens ii's settings, where you can change almost everything, including this tour."),
            keys: [["Win", "/"], ["Win", "I"]]
        },
        {
            icon: "health_and_safety",
            spot: "none",
            title: Translation.tr("If something goes wrong"),
            text: Translation.tr("Ctrl+Alt+Shift+R brings Windows' taskbar and desktop back at once and stops ii. You can start ii again from the Start menu."),
            keys: [["Ctrl", "Alt", "Shift", "R"]]
        }
    ]
    readonly property var current: steps[Math.max(0, Math.min(step, steps.length - 1))]

    function start() {
        step = 0;
        offerLight = Performance.suggested;
        if (offerLight)
            Persistent.states.performance.lightOffered = true;
        open = true;
    }
    function finish() {
        open = false;
        Persistent.states.tour.done = true;
    }

    // The first time: a few seconds after the shell is up, when nothing else is opening.
    Timer {
        id: firstRun
        interval: 7000
        running: true
        onTriggered: {
            if (Persistent.ready && !Persistent.states.tour.done && (Config.options.tour?.showOnFirstStart ?? true))
                root.start();
        }
    }

    IpcHandler {
        target: "tour"
        function open(): void {
            root.start();
        }
        function close(): void {
            root.finish();
        }
    }

    LazyLoader {
        active: root.open
        PanelWindow {
            id: tourWindow
            screen: Quickshell.screens[0]
            color: "transparent"
            WlrLayershell.namespace: "quickshell:tour"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            readonly property real barH: Appearance.sizes.barHeight
            readonly property real dockInset: Config.options.dock.enable ? GlobalStates.dockInsetBottom : 0

            // The lit part of the screen, in window coordinates.
            readonly property rect spotRect: {
                const w = width, h = height;
                switch (root.current.spot) {
                case "bar": return Qt.rect(8, 6, w - 16, barH);
                case "barCenter": return Qt.rect(w / 2 - 300, 6, 600, barH);
                case "barRight": return Qt.rect(w - 420, 6, 412, barH);
                case "dock": return Qt.rect(w / 2 - 260, h - 110, 520, 100);
                case "right": return Qt.rect(w - Appearance.sizes.sidebarWidth - 8, barH + 8, Appearance.sizes.sidebarWidth, h - barH - dockInset - 24);
                case "left": return Qt.rect(8, barH + 8, Appearance.sizes.sidebarWidth, h - barH - dockInset - 24);
                case "desktop": return Qt.rect(w * 0.18, h * 0.22, w * 0.64, h * 0.5);
                default: return Qt.rect(w / 2, h / 2, 0, 0);
                }
            }
            readonly property bool hasSpot: root.current.spot !== "none"

            // Backdrop that follows the lit rectangle: four dark panes around a hole.
            Item {
                anchors.fill: parent
                readonly property rect r: tourWindow.spotRect
                Rectangle { x: 0; y: 0; width: parent.width; height: Math.max(0, parent.r.y); color: Appearance.colors.colScrim }
                Rectangle { x: 0; y: parent.r.y + parent.r.height; width: parent.width; height: Math.max(0, parent.height - parent.r.y - parent.r.height); color: Appearance.colors.colScrim }
                Rectangle { x: 0; y: parent.r.y; width: Math.max(0, parent.r.x); height: parent.r.height; color: Appearance.colors.colScrim }
                Rectangle { x: parent.r.x + parent.r.width; y: parent.r.y; width: Math.max(0, parent.width - parent.r.x - parent.r.width); height: parent.r.height; color: Appearance.colors.colScrim }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {}
                }
            }
            Rectangle {
                id: spot
                x: tourWindow.spotRect.x
                y: tourWindow.spotRect.y
                width: tourWindow.spotRect.width
                height: tourWindow.spotRect.height
                radius: Appearance.rounding.large
                color: "transparent"
                border.width: tourWindow.hasSpot ? 3 : 0
                border.color: Appearance.colors.colPrimary
                opacity: tourWindow.hasSpot ? 1 : 0
                Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200 } }
                // Soft pulse so the eye finds it.
                SequentialAnimation on border.width {
                    loops: Animation.Infinite
                    running: tourWindow.hasSpot && !(Config.options.appearance.reduceMotion ?? false)
                    NumberAnimation { to: 6; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 3; duration: 700; easing.type: Easing.InOutSine }
                }
            }

            // The card, away from what it talks about.
            StyledRectangularShadow {
                target: card
            }
            Rectangle {
                id: card
                readonly property real wide: Math.min(520, tourWindow.width - 48)
                width: wide
                implicitHeight: cardColumn.implicitHeight + 40
                radius: Appearance.rounding.large + 4
                color: Appearance.colors.colBackgroundSurfaceContainer
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                x: {
                    const s = root.current.spot;
                    if (s === "right") return tourWindow.spotRect.x - width - 24;
                    if (s === "left") return tourWindow.spotRect.x + tourWindow.spotRect.width + 24;
                    return (tourWindow.width - width) / 2;
                }
                y: {
                    const s = root.current.spot;
                    if (s === "bar" || s === "barCenter" || s === "barRight") return tourWindow.barH + 40;
                    if (s === "dock") return tourWindow.height - tourWindow.dockInset - 110 - height - 30;
                    if (s === "right" || s === "left") return tourWindow.barH + 40;
                    if (s === "desktop") return tourWindow.height * 0.76 - 20 > 0 ? Math.min(tourWindow.height - height - tourWindow.dockInset - 24, tourWindow.height * 0.74) : 80;
                    return (tourWindow.height - height) / 2;
                }
                Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    id: cardColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 20
                    }
                    spacing: 12

                    RowLayout {
                        spacing: 14
                        Rectangle {
                            implicitWidth: 52
                            implicitHeight: 52
                            radius: 18
                            color: Appearance.colors.colPrimaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: root.current.icon
                                iconSize: 30
                                fill: 1
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.current.title
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.huge
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.current.text
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer0
                    }
                    Flow {
                        Layout.fillWidth: true
                        visible: root.current.keys.length > 0
                        spacing: 14
                        Repeater {
                            model: root.current.keys
                            delegate: Row {
                                id: combo
                                required property var modelData
                                spacing: 4
                                Repeater {
                                    model: combo.modelData
                                    delegate: Rectangle {
                                        id: keycap
                                        required property string modelData
                                        height: 30
                                        width: Math.max(30, keyText.implicitWidth + 16)
                                        radius: 8
                                        color: Appearance.colors.colSecondaryContainer
                                        border.width: 1
                                        border.color: Appearance.colors.colOutlineVariant
                                        StyledText {
                                            id: keyText
                                            anchors.centerIn: parent
                                            text: keycap.modelData
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Medium
                                            color: Appearance.colors.colOnSecondaryContainer
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.topMargin: 4
                        spacing: 8
                        Row {
                            spacing: 5
                            Repeater {
                                model: root.steps.length
                                delegate: Rectangle {
                                    required property int index
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: index === root.step ? 18 : 7
                                    height: 7
                                    radius: 4
                                    color: index === root.step ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                    Behavior on width { NumberAnimation { duration: 160 } }
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        RippleButton {
                            visible: root.current.action === "light"
                            enabled: !Performance.light
                            implicitHeight: 38
                            implicitWidth: lightText.implicitWidth + 28
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            onClicked: Performance.setLight(true)
                            contentItem: StyledText {
                                id: lightText
                                anchors.centerIn: parent
                                text: Performance.light ? Translation.tr("Light mode on") : Translation.tr("Use light mode")
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                        RippleButton {
                            visible: root.step < root.steps.length - 1
                            implicitHeight: 38
                            implicitWidth: skipText.implicitWidth + 28
                            buttonRadius: Appearance.rounding.full
                            onClicked: root.finish()
                            contentItem: StyledText {
                                id: skipText
                                anchors.centerIn: parent
                                text: Translation.tr("Skip")
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                        RippleButton {
                            visible: root.step > 0
                            implicitHeight: 38
                            implicitWidth: backText.implicitWidth + 28
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            onClicked: root.step = Math.max(0, root.step - 1)
                            contentItem: StyledText {
                                id: backText
                                anchors.centerIn: parent
                                text: Translation.tr("Back")
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                        RippleButton {
                            implicitHeight: 38
                            implicitWidth: nextText.implicitWidth + 36
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            onClicked: {
                                if (root.step >= root.steps.length - 1) root.finish();
                                else root.step += 1;
                            }
                            contentItem: StyledText {
                                id: nextText
                                anchors.centerIn: parent
                                text: root.step >= root.steps.length - 1 ? Translation.tr("Start using ii") : Translation.tr("Next")
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
            }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.finish();
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        if (root.step >= root.steps.length - 1) root.finish();
                        else root.step += 1;
                    } else if (event.key === Qt.Key_Left) {
                        root.step = Math.max(0, root.step - 1);
                    }
                    event.accepted = true;
                }
            }
        }
    }
}
