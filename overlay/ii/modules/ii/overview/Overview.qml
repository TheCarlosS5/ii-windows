import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false
    // ii-windows: Win opens the app grid (GNOME's "Show applications"), Win+Tab the windows.
    readonly property bool showApps: GlobalStates.overviewMode === "apps"
    // Room from `top` (a position inside the column) down to the buttons at the bottom (the app grid and the
    // search card must not run under them). Measured from the button itself: how tall this window is depends
    // on the work area, so a sum of margins was wrong at 125 % / 150 %.
    function heightBelow(top) {
        return appsButton.y - 16 - top;
    }

    PanelWindow {
        id: panelWindow
        property string searchingText: ""
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
        property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
        visible: GlobalStates.overviewOpen

        WlrLayershell.namespace: "quickshell:overview"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: GlobalStates.overviewOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        // ii-windows: the dimmed backdrop takes the clicks (a click outside closes the overview).
        mask: Region {
            item: GlobalStates.overviewOpen ? backdrop : null
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Connections {
            target: GlobalStates
            function onOverviewOpenChanged() {
                if (!GlobalStates.overviewOpen) {
                    // Whatever opens it next (the bar, a script) gets the grid, unless it asks for windows.
                    GlobalStates.overviewMode = "apps";
                    searchWidget.disableExpandAnimation();
                    overviewScope.dontAutoCancelSearch = false;
                    GlobalFocusGrab.dismiss();
                } else {
                    if (!overviewScope.dontAutoCancelSearch) {
                        searchWidget.cancelSearch();
                    }
                    GlobalFocusGrab.addDismissable(panelWindow);
                }
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                if (GlobalStates.overviewOpen)
                    GlobalStates.overviewDismissedAt = Date.now();
                GlobalStates.overviewOpen = false;
            }
        }
        implicitWidth: columnLayout.implicitWidth
        implicitHeight: columnLayout.implicitHeight

        function setSearchingText(text) {
            searchWidget.setSearchingText(text);
            searchWidget.focusFirstItem();
        }

        // Dimmed backdrop, like GNOME's Activities.
        Rectangle {
            id: backdrop
            anchors.fill: parent
            // A light veil only (the full scrim, 50 % black, made the overview much darker than the bar and the
            // dock, which are glass over the wallpaper): the same transparency everywhere.
            color: ColorUtils.transparentize(Appearance.colors.colScrim, 0.75)
            opacity: GlobalStates.overviewOpen ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: GlobalStates.overviewOpen = false
            }
        }

        Column {
            id: columnLayout
            visible: GlobalStates.overviewOpen
            // ii-windows: pops in, as Hyprland animates the layer on Linux.
            opacity: GlobalStates.overviewOpen ? 1 : 0
            scale: GlobalStates.overviewOpen ? 1 : 0.94
            transformOrigin: Item.Top
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on scale {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
            }
            spacing: 4

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    // First Esc clears the search, like GNOME; the next one closes.
                    if (panelWindow.searchingText !== "")
                        searchWidget.cancelSearch();
                    else
                        GlobalStates.overviewOpen = false;
                }
            }

            // The desktops, small, on top (GNOME's workspace strip).
            Loader {
                anchors.horizontalCenter: parent.horizontalCenter
                active: GlobalStates.overviewOpen && (Config?.options.overview.enable ?? true)
                sourceComponent: DesktopStrip {
                    screen: panelWindow.screen
                }
            }

            SearchWidget {
                id: searchWidget
                anchors.horizontalCenter: parent.horizontalCenter
                gridNavigator: appGridLoader.item
                availableHeight: overviewScope.heightBelow(searchWidget.y)
                Synchronizer on searchingText {
                    property alias source: panelWindow.searchingText
                }
            }

            Loader {
                id: overviewLoader
                anchors.horizontalCenter: parent.horizontalCenter
                // The big windows only in the "windows" mode (Win+Tab); the grid mode never builds them.
                active: GlobalStates.overviewOpen && (Config?.options.overview.enable ?? true) && !overviewScope.showApps && panelWindow.searchingText == ""
                // An inactive Loader keeps the height of the item it had: hidden, the Column skips it (else the
                // app grid opened after Win+Tab sat ~570 px lower, under the buttons at the bottom).
                visible: active
                sourceComponent: OverviewWidget {
                    screen: panelWindow.screen
                    // ii-windows: never taller than the room above the buttons at the bottom (laptops at 125 %
                    // and more: the windows' box ran under them). Same size maths as OverviewWidget's own.
                    scale: {
                        const wanted = Config.options.overview.scale;
                        const m = panelWindow.monitor;
                        const screenH = (m?.height ?? 1080) / (m?.scale ?? 1);
                        const rows = Math.max(1, Config.options.overview.rows);
                        const room = overviewScope.heightBelow(overviewLoader.y) - 2 * Appearance.sizes.elevationMargin - 40;
                        return Math.max(0.15, Math.min(wanted, room / (rows * screenH)));
                    }
                }
            }

            Loader {
                id: appGridLoader
                anchors.horizontalCenter: parent.horizontalCenter
                active: GlobalStates.overviewOpen && overviewScope.showApps && panelWindow.searchingText == ""
                visible: active
                sourceComponent: AppGrid {
                    availableHeight: overviewScope.heightBelow(appGridLoader.y)
                }
            }
        }

        // The app store, next to it.
        RippleButton {
            id: storeButton
            visible: GlobalStates.overviewOpen
            opacity: columnLayout.opacity
            anchors {
                verticalCenter: appsButton.verticalCenter
                left: appsButton.right
                leftMargin: 12
            }
            implicitWidth: 56
            implicitHeight: 56
            focusPolicy: Qt.NoFocus // a button that takes the focus leaves Esc and typing without a target
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colBackgroundSurfaceContainer
            onClicked: {
                GlobalStates.overviewOpen = false;
                Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("store.qml")]);
            }
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "storefront"
                iconSize: 28
                color: Appearance.colors.colOnLayer1
            }
            StyledToolTip {
                text: Translation.tr("App store")
            }
        }

        // "Show applications", bottom centre (GNOME's dash button).
        RippleButton {
            id: appsButton
            visible: GlobalStates.overviewOpen
            opacity: columnLayout.opacity
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: GlobalStates.dockInsetBottom + 36
            }
            implicitWidth: 56
            implicitHeight: 56
            focusPolicy: Qt.NoFocus
            buttonRadius: Appearance.rounding.full
            toggled: overviewScope.showApps
            colBackground: Appearance.colors.colBackgroundSurfaceContainer
            colBackgroundToggled: Appearance.colors.colPrimary
            // Switches between the grid and the windows (the open overview keeps its search field).
            onClicked: {
                GlobalStates.overviewMode = overviewScope.showApps ? "windows" : "apps";
                searchWidget.cancelSearch();
                searchWidget.focusSearchInput();
            }
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: overviewScope.showApps ? "select_window" : "apps"
                iconSize: 28
                color: appsButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            }
            StyledToolTip {
                text: overviewScope.showApps ? Translation.tr("Show windows") : Translation.tr("Show applications")
            }
        }
    }

    function toggleClipboard() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.clipboard);
        GlobalStates.overviewMode = "apps";
        GlobalStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.emojis);
        GlobalStates.overviewMode = "apps";
        GlobalStates.overviewOpen = true;
    }

    IpcHandler {
        target: "search"

        function toggle() {
            GlobalStates.toggleOverview("apps");
        }
        function workspacesToggle() {
            GlobalStates.toggleOverview("windows");
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            GlobalStates.overviewMode = "apps";
            GlobalStates.overviewOpen = true;
        }
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
        function clipboardToggle() {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            GlobalStates.toggleOverview("apps");
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            GlobalStates.overviewOpen = false;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            GlobalStates.toggleOverview("windows");
        }
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            GlobalStates.toggleOverview("apps");
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }
    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"

        onPressed: {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            overviewScope.toggleEmojis();
        }
    }
}
