pragma ComponentBehavior: Bound

import Qt.labs.synchronizer
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions

// ii-windows: the search of the overview, GNOME style: a pill, and under it the apps as a grid of equal
// square tiles (icon and name; the first one is the one Enter opens) and everything else (math, clipboard,
// commands, web) as rows. Keyboard: Down/Up/Left/Right move through the results, Enter opens, Esc clears.
Item {
    id: root

    property string searchingText: LauncherSearch.query
    property bool showResults: searchingText != ""
    // With no text the keys drive the app grid (Overview.qml sets it): move(direction) and activateCurrent().
    property var gridNavigator: null
    // Room for the card: the overview's free height (set by Overview.qml), else half the window.
    property real availableHeight: 0

    readonly property real windowWidth: root.QsWindow.window?.width ?? 1280
    readonly property real windowHeight: root.QsWindow.window?.height ?? 800
    readonly property real resultsWidth: Math.min(960, Math.max(460, windowWidth * 0.72))
    // The card must not run under the buttons at the bottom: what is free, minus the pill and the card's padding.
    readonly property real maxResultsHeight: Math.max(160, availableHeight > 0
        ? availableHeight - pill.implicitHeight - Appearance.sizes.elevationMargin * 2 - 34
        : windowHeight * 0.5)
    readonly property real tileWidth: 112
    readonly property real tileHeight: 116
    readonly property int columns: Math.max(2, Math.floor((resultsWidth - 40) / (tileWidth + 6)))

    implicitWidth: Math.max(pill.implicitWidth, showResults ? resultsWidth : 0) + Appearance.sizes.elevationMargin * 2
    implicitHeight: pill.implicitHeight + (showResults ? card.implicitHeight + 10 : 0) + Appearance.sizes.elevationMargin * 2

    // ---- data ---------------------------------------------------------------------------------
    // Two rows of app tiles at most, and the other providers (math, commands, web...) are never cut by the apps.
    readonly property int maxAppTiles: columns * 2
    readonly property var allResults: LauncherSearch.results ?? []
    readonly property var appResults: allResults.filter(r => r.id !== "").slice(0, maxAppTiles)
    readonly property var otherResults: allResults.filter(r => r.id === "").slice(0, 12)
    readonly property var flat: appResults.concat(otherResults)
    property int currentIndex: 0
    onFlatChanged: currentIndex = 0

    function activate(entry) {
        if (!entry)
            return;
        GlobalStates.overviewOpen = false;
        entry.execute();
    }
    function activateCurrent() {
        if (!root.showResults) {
            root.gridNavigator?.activateCurrent();
            return;
        }
        root.activate(root.flat[root.currentIndex]);
    }
    // The tiles first (A of them, `cols` per row), then the rows of the other providers.
    function move(direction) {
        if (!root.showResults) {
            root.gridNavigator?.move(direction);
            return;
        }
        const n = root.flat.length;
        if (n === 0)
            return;
        const A = root.appResults.length;
        const cols = root.columns;
        let i = root.currentIndex;
        if (direction === "down") {
            if (i < A) {
                const next = i + cols;
                i = next < A ? next : (A < n ? A : i);
            } else
                i = Math.min(n - 1, i + 1);
        } else if (direction === "up") {
            if (i > A)
                i = i - 1;
            else if (i === A)
                i = Math.max(0, A - 1);
            else
                i = (i - cols >= 0) ? i - cols : i;
        } else if (direction === "left") {
            if (i < A)
                i = Math.max(0, i - 1);
        } else if (direction === "right") {
            if (i < A)
                i = Math.min(A - 1, i + 1);
        }
        root.currentIndex = i;
    }
    function ensureVisible(item) {
        const p = item.mapToItem(flick.contentItem, 0, 0);
        if (p.y < flick.contentY)
            flick.contentY = Math.max(0, p.y - 8);
        else if (p.y + item.height > flick.contentY + flick.height)
            flick.contentY = p.y + item.height - flick.height + 8;
    }

    // ---- API used by Overview.qml -----------------------------------------------------------------
    function focusFirstItem() {
        root.currentIndex = 0;
    }
    function focusSearchInput() {
        searchBar.forceFocus();
    }
    function disableExpandAnimation() {
        searchBar.animateWidth = false;
    }
    function cancelSearch() {
        // Clear the field too (upstream only selected the text): with the app grid under it, a leftover
        // "calc" in the field would look like a search that is not there.
        searchBar.searchInput.text = "";
        LauncherSearch.query = "";
        searchBar.animateWidth = true;
    }
    function setSearchingText(text) {
        searchBar.searchInput.text = text;
        LauncherSearch.query = text;
    }

    // Typing anywhere starts a search (the input may not have the focus yet).
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape)
            return;
        if (event.key === Qt.Key_Backspace) {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                const text = searchBar.searchInput.text;
                const pos = searchBar.searchInput.cursorPosition;
                if (pos > 0) {
                    searchBar.searchInput.text = text.slice(0, pos - 1) + text.slice(pos);
                    searchBar.searchInput.cursorPosition = pos - 1;
                }
                searchBar.searchInput.cursorPosition = searchBar.searchInput.text.length;
                event.accepted = true;
            }
            return;
        }
        if (event.text && event.text.length === 1 && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Return && event.key !== Qt.Key_Delete && event.text.charCodeAt(0) >= 0x20) {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition) + event.text + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                searchBar.searchInput.cursorPosition += 1;
                event.accepted = true;
                root.focusFirstItem();
            }
        }
    }

    // ---- the pill ------------------------------------------------------------------------------------
    StyledRectangularShadow {
        target: pill
    }
    Rectangle {
        id: pill
        anchors {
            top: parent.top
            topMargin: Appearance.sizes.elevationMargin
            horizontalCenter: parent.horizontalCenter
        }
        implicitWidth: searchBar.implicitWidth + 24
        implicitHeight: searchBar.implicitHeight + 10
        radius: height / 2
        // Same glass as the bar and the dock (colLayer0 and its border).
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        WallpaperBlur { anchors.fill: parent; radius: parent.radius; tint: parent.color; inset: parent.border.width } // ii-windows: frosted glass

        SearchBar {
            id: searchBar
            anchors.centerIn: parent
            Synchronizer on searchingText {
                property alias source: root.searchingText
            }
            onNavigate: direction => root.move(direction)
            onActivate: root.activateCurrent()
        }
    }

    // ---- the results ----------------------------------------------------------------------------------
    StyledRectangularShadow {
        target: card
        visible: card.visible
    }
    Rectangle {
        id: card
        visible: root.showResults
        anchors {
            top: pill.bottom
            topMargin: 10
            horizontalCenter: parent.horizontalCenter
        }
        width: root.resultsWidth
        implicitHeight: Math.min(flick.contentHeight, root.maxResultsHeight) + 24
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        WallpaperBlur { anchors.fill: parent; radius: parent.radius; tint: parent.color; inset: parent.border.width } // ii-windows: frosted glass
        clip: true

        Behavior on implicitHeight {
            enabled: GlobalStates.overviewOpen && root.showResults
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 12
            contentHeight: resultsColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: resultsColumn
                width: flick.width
                spacing: 12

                // The apps: equal square tiles, the first one is what Enter opens (like GNOME).
                Item {
                    width: parent.width
                    height: appGrid.implicitHeight
                    visible: root.appResults.length > 0
                    Flow {
                        id: appGrid
                        width: Math.min(root.columns, Math.max(1, root.appResults.length)) * (root.tileWidth + 6)
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 6
                        Repeater {
                            model: root.appResults
                            delegate: AppTile {
                                required property var modelData
                                required property int index
                                entry: modelData
                                flatIndex: index
                            }
                        }
                    }
                }

                // Math, clipboard, commands, web search, actions.
                Column {
                    width: parent.width
                    spacing: 2
                    visible: root.otherResults.length > 0
                    Repeater {
                        model: root.otherResults
                        delegate: SearchItem {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property int flatIndex: root.appResults.length + index
                            width: parent.width
                            entry: modelData
                            forcedSelected: root.currentIndex === flatIndex
                            query: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch])
                            onForcedSelectedChanged: if (forcedSelected) root.ensureVisible(row)
                        }
                    }
                }
            }
        }
    }

    // ---- delegates --------------------------------------------------------------------------------------
    component AppTile: RippleButton {
        id: tile
        required property var entry
        required property int flatIndex
        readonly property bool current: root.currentIndex === flatIndex
        implicitWidth: root.tileWidth
        implicitHeight: root.tileHeight
        buttonRadius: Appearance.rounding.large
        colBackground: current ? Appearance.colors.colPrimaryContainer : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 1)
        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
        colRipple: Appearance.colors.colPrimaryContainerActive
        onCurrentChanged: if (current) root.ensureVisible(tile)
        onClicked: root.activate(tile.entry)
        PointingHandInteraction {}

        contentItem: Column {
            anchors.centerIn: parent
            spacing: 6
            IconImage {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitSize: 56
                mipmap: true
                source: Quickshell.iconPath(tile.entry.iconName, "image-missing")
            }
            StyledText {
                width: tile.root_width
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: tile.entry.name
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: tile.current ? Appearance.colors.colOnPrimaryContainer : Appearance.m3colors.m3onSurface
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
        readonly property real root_width: root.tileWidth - 12
    }

}
