//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.store
import "modules/ii/store/catalog.js" as Catalog

// ii-windows: the app store. Featured apps by category, a search of the whole winget catalogue, what is installed
// and what can be updated; install / update / uninstall with a click (winget does the work, one app at a time).
ApplicationWindow {
    id: root
    visible: true
    onClosing: Qt.quit()
    title: "ii-windows"
    property bool customTitleBar: true
    color: Appearance.m3colors.m3background
    minimumWidth: 760
    minimumHeight: 520
    width: 1100
    height: 750
    property real contentPadding: 8

    // 0 = featured, 1..n = Catalog.categories[i - 1], then Installed, then Updates
    property int page: 0
    readonly property int installedPage: Catalog.categories.length + 1
    readonly property int updatesPage: Catalog.categories.length + 2
    property string query: ""
    readonly property bool searching: page !== installedPage && query.trim().length >= 2

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        Config.readWriteDelay = 0;
        Winget.check();
    }

    Timer {
        id: searchDelay
        interval: 450
        onTriggered: Winget.search(root.query)
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.contentPadding
        }

        Item { // Title bar
            Layout.fillWidth: true
            implicitHeight: Math.max(titleText.implicitHeight, closeButton.implicitHeight)
            DragHandler {
                target: null
                onActiveChanged: if (active) root.startSystemMove()
            }
            TapHandler {
                onDoubleTapped: root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized()
            }
            StyledText {
                id: titleText
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("App store")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.font.variableAxes.title
                }
            }
            RippleButton {
                id: closeButton
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                buttonRadius: Appearance.rounding.full
                implicitWidth: 35
                implicitHeight: 35
                onClicked: root.close()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "close"
                    iconSize: 20
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.contentPadding

            // --- navigation -----------------------------------------------------------------------------------
            Item {
                id: railWrapper
                Layout.fillHeight: true
                Layout.margins: 5
                implicitWidth: rail.expanded ? 190 : 72
                NavigationRail {
                    id: rail
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                    }
                    spacing: 6
                    expanded: root.width > 900

                    NavigationRailExpandButton {
                        focus: root.visible
                    }
                    NavigationRailTabArray {
                        currentIndex: root.page
                        expanded: rail.expanded
                        // Featured
                        NavigationRailButton {
                            toggled: root.page === 0
                            onPressed: root.page = 0
                            expanded: rail.expanded
                            buttonIcon: "star"
                            buttonText: Translation.tr("Featured")
                            showToggledHighlight: false
                        }
                        Repeater {
                            model: Catalog.categories
                            NavigationRailButton {
                                required property int index
                                required property var modelData
                                toggled: root.page === index + 1
                                onPressed: root.page = index + 1
                                expanded: rail.expanded
                                buttonIcon: modelData.icon
                                buttonText: Translation.tr(modelData.name)
                                showToggledHighlight: false
                            }
                        }
                        NavigationRailButton {
                            toggled: root.page === root.installedPage
                            onPressed: root.page = root.installedPage
                            expanded: rail.expanded
                            buttonIcon: "download_done"
                            buttonText: Translation.tr("Installed")
                            showToggledHighlight: false
                        }
                        NavigationRailButton {
                            toggled: root.page === root.updatesPage
                            onPressed: root.page = root.updatesPage
                            expanded: rail.expanded
                            buttonIcon: "update"
                            buttonText: Winget.upgrades.length > 0 ? Translation.tr("Updates") + ` (${Winget.upgrades.length})` : Translation.tr("Updates")
                            showToggledHighlight: false
                        }
                    }
                    Item {
                        Layout.fillHeight: true
                    }
                }
            }

            // --- content ------------------------------------------------------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding

                ColumnLayout {
                    anchors {
                        fill: parent
                        margins: 18
                    }
                    spacing: 12

                    // winget missing
                    NoticeBox {
                        Layout.fillWidth: true
                        visible: Winget.checked && !Winget.available
                        text: Translation.tr("winget is not available on this PC") + "\n" + Translation.tr("winget comes with Windows 11 as \"App Installer\". Install or update it from the Microsoft Store and open this window again.")
                    }

                    // search
                    ToolbarTextField {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: 42
                        implicitHeight: 42
                        enabled: Winget.available
                        placeholderText: root.page === root.installedPage ? Translation.tr("Filter installed apps") : Translation.tr("Search apps (winget)")
                        onTextChanged: {
                            root.query = text;
                            if (root.page !== root.installedPage) searchDelay.restart();
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: !root.searching && root.page !== root.installedPage
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Apps come from the winget catalogue (the same as `winget install`). Some ask for administrator permission.")
                    }

                    // --- the list ---------------------------------------------------------------------------------------
                    StyledFlickable {
                        id: flick
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: listColumn.implicitHeight + 20
                        clip: true

                        ColumnLayout {
                            id: listColumn
                            width: flick.width
                            spacing: 10

                            // Section titles and states
                            StyledText {
                                visible: root.searching
                                text: Winget.searching ? Translation.tr("Searching...") : (Winget.results.length === 0 ? Translation.tr("Nothing found") : Translation.tr("Search results"))
                                font.pixelSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                            RowLayout {
                                visible: root.page === root.updatesPage && !root.searching
                                Layout.fillWidth: true
                                StyledText {
                                    Layout.fillWidth: true
                                    text: Winget.listing ? Translation.tr("Checking...") : (Winget.upgrades.length === 0 ? Translation.tr("Everything is up to date") : Translation.tr("%1 updates").arg(Winget.upgrades.length))
                                    font.pixelSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnLayer1
                                }
                                RippleButton {
                                    visible: Winget.upgrades.length > 0
                                    implicitHeight: 38
                                    implicitWidth: allText.implicitWidth + 32
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colPrimary
                                    colBackgroundHover: Appearance.colors.colPrimaryHover
                                    onClicked: Winget.upgradeAll()
                                    contentItem: StyledText {
                                        id: allText
                                        anchors.centerIn: parent
                                        text: Translation.tr("Update all")
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnPrimary
                                    }
                                }
                            }
                            StyledText {
                                visible: root.page === root.installedPage && !root.searching
                                text: Translation.tr("Installed apps on this PC")
                                font.pixelSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }

                            // Search results
                            Repeater {
                                model: root.searching ? Winget.results : []
                                delegate: StoreCard {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    appId: modelData.id
                                    name: modelData.name
                                    description: modelData.id + (modelData.version ? "  ·  " + modelData.version : "")
                                    site: Catalog.byId(modelData.id)?.site ?? ""
                                }
                            }

                            // Featured and categories
                            Repeater {
                                model: !root.searching && root.page <= Catalog.categories.length ? (root.page === 0 ? Catalog.featured() : Catalog.categories[root.page - 1].apps) : []
                                delegate: StoreCard {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    appId: modelData.id
                                    name: modelData.name
                                    description: Translation.tr(modelData.desc)
                                    site: modelData.site
                                    aka: modelData.aka ?? []
                                }
                            }

                            // Updates
                            Repeater {
                                model: !root.searching && root.page === root.updatesPage ? Winget.upgrades : []
                                delegate: StoreCard {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    appId: modelData.id
                                    name: modelData.name
                                    description: `${modelData.version}  →  ${modelData.available}`
                                    site: Catalog.byId(modelData.id)?.site ?? ""
                                }
                            }

                            // Installed
                            Repeater {
                                model: root.page === root.installedPage ? Winget.installedList.filter(a => root.query.trim().length === 0 || a.name.toLowerCase().includes(root.query.trim().toLowerCase())) : []
                                delegate: StoreCard {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    appId: modelData.id
                                    name: modelData.name
                                    description: `${modelData.id}  ·  ${modelData.version}`
                                    site: Catalog.byId(modelData.id)?.site ?? ""
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
