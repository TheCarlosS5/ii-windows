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

// ii-windows: the search of the overview, GNOME / macOS style: a pill, and under it the best match as a
// big app tile, the other apps as a grid of icons and everything else (math, clipboard, commands, web)
// as rows. Keyboard: Down/Up/Left/Right move through the results, Enter opens, Esc closes.
Item {
    id: root

    property string searchingText: LauncherSearch.query
    property bool showResults: searchingText != ""

    readonly property real windowWidth: root.QsWindow.window?.width ?? 1280
    readonly property real windowHeight: root.QsWindow.window?.height ?? 800
    readonly property real resultsWidth: Math.min(960, Math.max(460, windowWidth * 0.72))
    readonly property real maxResultsHeight: Math.max(240, windowHeight * 0.5)
    readonly property real tileWidth: 112
    readonly property real tileHeight: 116
    readonly property int columns: Math.max(2, Math.floor((resultsWidth - 40) / (tileWidth + 6)))

    implicitWidth: Math.max(pill.implicitWidth, showResults ? resultsWidth : 0) + Appearance.sizes.elevationMargin * 2
    implicitHeight: pill.implicitHeight + (showResults ? card.implicitHeight + 10 : 0) + Appearance.sizes.elevationMargin * 2

    // ---- data ---------------------------------------------------------------------------------
    readonly property var allResults: (LauncherSearch.results ?? []).slice(0, 36)
    readonly property var appResults: allResults.filter(r => r.id !== "")
    readonly property var otherResults: allResults.filter(r => r.id === "")
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
        root.activate(root.flat[root.currentIndex]);
    }
    function move(direction) {
        const n = root.flat.length;
        if (n === 0)
            return;
        const A = root.appResults.length;
        const cols = root.columns;
        let i = root.currentIndex;
        if (direction === "down") {
            if (i === 0 && A > 0)
                i = A > 1 ? 1 : (n > A ? A : 0);
            else if (i < A) {
                const next = i + cols;
                i = next < A ? next : (A < n ? A : i);
            } else
                i = Math.min(n - 1, i + 1);
        } else if (direction === "up") {
            if (i >= A && A > 0)
                i = i > A ? i - 1 : A - 1;
            else if (i >= A)
                i = Math.max(0, i - 1);
            else if (i > 0)
                i = (i - cols >= 1) ? i - cols : 0;
        } else if (direction === "left") {
            i = Math.max(0, i - 1);
        } else if (direction === "right") {
            i = Math.min(n - 1, i + 1);
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
        searchBar.searchInput.selectAll();
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
        color: Appearance.colors.colBackgroundSurfaceContainer

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
        color: Appearance.colors.colBackgroundSurfaceContainer
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

                // Best match.
                Loader {
                    width: parent.width
                    active: root.appResults.length > 0
                    visible: active
                    sourceComponent: BestTile {
                        entry: root.appResults[0]
                        flatIndex: 0
                    }
                }

                // The other apps.
                Item {
                    width: parent.width
                    height: appGrid.implicitHeight
                    visible: root.appResults.length > 1
                    Flow {
                        id: appGrid
                        width: root.columns * (root.tileWidth + 6)
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 6
                        Repeater {
                            model: root.appResults.slice(1)
                            delegate: AppTile {
                                required property var modelData
                                required property int index
                                entry: modelData
                                flatIndex: index + 1
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

    component BestTile: RippleButton {
        id: best
        required property var entry
        required property int flatIndex
        readonly property bool current: root.currentIndex === flatIndex
        implicitHeight: 108
        buttonRadius: Appearance.rounding.large
        colBackground: current ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
        colRipple: Appearance.colors.colPrimaryContainerActive
        onClicked: root.activate(best.entry)
        PointingHandInteraction {}

        contentItem: RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 16
            IconImage {
                Layout.alignment: Qt.AlignVCenter
                implicitSize: 80
                mipmap: true
                source: Quickshell.iconPath(best.entry.iconName, "image-missing")
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: best.entry.name
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.weight: Font.DemiBold
                    color: best.current ? Appearance.colors.colOnPrimaryContainer : Appearance.m3colors.m3onSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: best.entry.comment || best.entry.genericName || ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: best.current ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                }
                RowLayout {
                    Layout.topMargin: 4
                    spacing: 6
                    Repeater {
                        model: (best.entry.actions ?? []).slice(0, 3)
                        delegate: RippleButton {
                            id: actionChip
                            required property var modelData
                            implicitHeight: 28
                            implicitWidth: chipLabel.implicitWidth + 24
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            onClicked: {
                                GlobalStates.overviewOpen = false;
                                actionChip.modelData.execute();
                            }
                            contentItem: StyledText {
                                id: chipLabel
                                anchors.centerIn: parent
                                text: actionChip.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                visible: best.current
                text: Translation.tr("Open") + "  ↵"
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnPrimaryContainer
            }
        }
    }
}
