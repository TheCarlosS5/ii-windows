//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

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

// ii-windows: the app store. A front page with a carousel and a row of every category, the categories as grids, a
// search of the whole winget catalogue, what is installed and what can be updated; install / update / uninstall
// with a click (winget does the work, one app at a time, shown in the bar at the bottom).
ApplicationWindow {
    id: root
    visible: true
    onClosing: Qt.quit()
    title: Translation.tr("App store")
    property bool customTitleBar: true
    color: Appearance.m3colors.m3background
    minimumWidth: 780
    minimumHeight: 540
    width: 1180
    height: 800
    property real contentPadding: 8

    // 0 = front page, 1..n = Catalog.categories[i - 1], then Installed, then Updates
    property int page: parseInt(Quickshell.env("II_STORE_PAGE") || "0") || 0 // II_STORE_PAGE: open on a page (updates...)
    readonly property int installedPage: Catalog.categories.length + 1
    readonly property int updatesPage: Catalog.categories.length + 2
    readonly property bool categoryPage: page >= 1 && page <= Catalog.categories.length
    property string query: ""
    readonly property bool searching: page !== installedPage && query.trim().length >= 2
    readonly property var heroes: Catalog.heroes()
    readonly property var installedShown: Winget.installedList.filter(a => root.query.trim().length === 0 || a.name.toLowerCase().includes(root.query.trim().toLowerCase()))

    onPageChanged: flick.contentY = 0

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        Config.readWriteDelay = 0;
        Winget.check();
    }

    Timer {
        id: searchDelay
        interval: 400
        onTriggered: Winget.search(root.query)
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.contentPadding
        }
        spacing: root.contentPadding

        Item { // Title bar
            Layout.fillWidth: true
            implicitHeight: 44
            DragHandler {
                target: null
                onActiveChanged: if (active) root.startSystemMove()
            }
            TapHandler {
                onDoubleTapped: root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized()
            }
            RowLayout {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                    leftMargin: 10
                }
                spacing: 12
                MaterialShape {
                    implicitSize: 36
                    shape: MaterialShape.Shape.Cookie9Sided
                    color: Appearance.colors.colPrimaryContainer
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "storefront"
                        iconSize: 20
                        fill: 1
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }
                StyledText {
                    color: Appearance.colors.colOnLayer0
                    text: Translation.tr("App store")
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.title
                        variableAxes: Appearance.font.variableAxes.title
                    }
                }
            }
            RowLayout {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                spacing: 2
                TitleButton {
                    symbol: "remove"
                    onClicked: root.showMinimized()
                }
                TitleButton {
                    symbol: root.visibility === Window.Maximized ? "close_fullscreen" : "open_in_full"
                    onClicked: root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized()
                }
                TitleButton {
                    symbol: "close"
                    onClicked: root.close()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.contentPadding

            // --- navigation -----------------------------------------------------------------------------------
            Item {
                Layout.fillHeight: true
                Layout.margins: 5
                implicitWidth: rail.expanded ? 200 : 72
                NavigationRail {
                    id: rail
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                    }
                    spacing: 6
                    expanded: root.width > 940

                    NavigationRailExpandButton {
                        focus: root.visible
                    }
                    NavigationRailTabArray {
                        currentIndex: root.page
                        expanded: rail.expanded
                        NavigationRailButton {
                            toggled: root.page === 0
                            onPressed: root.page = 0
                            expanded: rail.expanded
                            buttonIcon: "home"
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
                clip: true

                ColumnLayout {
                    anchors {
                        fill: parent
                        margins: 18
                        bottomMargin: 12
                    }
                    spacing: 14

                    // The search bar (Material 3: a pill with the magnifier and a clear button).
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.maximumWidth: 760
                        Layout.alignment: Qt.AlignHCenter
                        implicitHeight: 52
                        radius: height / 2
                        color: searchField.activeFocus ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                        border.width: searchField.activeFocus ? 2 : 0
                        border.color: Appearance.colors.colPrimary
                        Behavior on color {
                            ColorAnimation { duration: 160 }
                        }
                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 18
                                rightMargin: 8
                            }
                            spacing: 10
                            MaterialSymbol {
                                text: "search"
                                iconSize: 22
                                color: Appearance.colors.colSubtext
                            }
                            TextField {
                                id: searchField
                                Layout.fillWidth: true
                                background: null
                                enabled: Winget.available
                                color: Appearance.colors.colOnLayer1
                                placeholderTextColor: Appearance.colors.colSubtext
                                font.family: Appearance.font.family.main
                                font.pixelSize: Appearance.font.pixelSize.normal
                                selectByMouse: true
                                placeholderText: root.page === root.installedPage ? Translation.tr("Filter installed apps") : Translation.tr("Search any app (winget catalogue)")
                                onTextChanged: {
                                    root.query = text;
                                    if (root.page !== root.installedPage) searchDelay.restart();
                                }
                                Keys.onEscapePressed: text = ""
                            }
                            MaterialLoadingIndicator {
                                visible: Winget.searching && root.searching
                                loading: visible
                                implicitSize: 30
                            }
                            RippleButton {
                                visible: searchField.text.length > 0
                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.full
                                onClicked: searchField.text = ""
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "close"
                                    iconSize: 20
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }

                    // winget missing
                    NoticeBox {
                        Layout.fillWidth: true
                        visible: Winget.checked && !Winget.available
                        text: Translation.tr("winget is not available on this PC") + "\n" + Translation.tr("winget comes with Windows 11 as \"App Installer\". Install or update it from the Microsoft Store and open this window again.")
                    }

                    // --- the page ---------------------------------------------------------------------------------------
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Flickable {
                            id: flick
                            anchors.fill: parent
                            contentHeight: pageColumn.implicitHeight + 24
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: StyledScrollBar {}

                            ColumnLayout {
                                id: pageColumn
                                width: flick.width - 14
                                spacing: 14
                                readonly property int columns: Math.max(2, Math.floor((width + 12) / 220))
                                readonly property real tileWidth: (width - (columns - 1) * 12) / columns

                                // ---- front page ----
                                StoreHero {
                                    visible: root.page === 0 && !root.searching
                                    Layout.fillWidth: true
                                    apps: root.heroes
                                }
                                Repeater {
                                    model: root.page === 0 && !root.searching ? Catalog.categories : []
                                    delegate: ColumnLayout {
                                        id: section
                                        required property int index
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.topMargin: 8
                                        spacing: 10
                                        SectionHeader {
                                            icon: section.modelData.icon
                                            title: Translation.tr(section.modelData.name)
                                            actionText: Translation.tr("See all")
                                            onAction: root.page = section.index + 1
                                        }
                                        Flow {
                                            Layout.fillWidth: true
                                            spacing: 12
                                            Repeater {
                                                model: section.modelData.apps.slice(0, pageColumn.columns)
                                                delegate: StoreTile {
                                                    required property var modelData
                                                    width: pageColumn.tileWidth
                                                    appId: modelData.id
                                                    name: modelData.name
                                                    description: Translation.tr(modelData.desc)
                                                    site: modelData.site
                                                    aka: modelData.aka ?? []
                                                }
                                            }
                                        }
                                    }
                                }

                                // ---- a category ----
                                PageHeader {
                                    visible: root.categoryPage && !root.searching
                                    icon: root.categoryPage ? Catalog.categories[root.page - 1].icon : ""
                                    title: root.categoryPage ? Translation.tr(Catalog.categories[root.page - 1].name) : ""
                                    subtitle: root.categoryPage ? Translation.tr("%1 apps").arg(Catalog.categories[root.page - 1].apps.length) : ""
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    visible: root.categoryPage && !root.searching
                                    spacing: 12
                                    Repeater {
                                        model: root.categoryPage && !root.searching ? Catalog.categories[root.page - 1].apps : []
                                        delegate: StoreTile {
                                            required property var modelData
                                            width: pageColumn.tileWidth
                                            appId: modelData.id
                                            name: modelData.name
                                            description: Translation.tr(modelData.desc)
                                            site: modelData.site
                                            aka: modelData.aka ?? []
                                        }
                                    }
                                }

                                // ---- search ----
                                PageHeader {
                                    visible: root.searching
                                    icon: "search"
                                    title: Winget.searching ? Translation.tr("Searching…") : (Winget.results.length === 0 ? Translation.tr("Nothing found") : Translation.tr("Search results"))
                                    subtitle: !Winget.searching && Winget.results.length === 0 ? Translation.tr("Try another name, or a shorter one.") : ""
                                }
                                Skeleton {
                                    visible: root.searching && Winget.searching && Winget.results.length === 0
                                }
                                Repeater {
                                    model: root.searching ? Winget.results : []
                                    delegate: StoreCard {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        opacity: Winget.searching ? 0.5 : 1
                                        appId: modelData.id
                                        name: modelData.name
                                        description: Catalog.byId(modelData.id) ? Translation.tr(Catalog.byId(modelData.id).desc) : modelData.id + (modelData.version ? "  ·  " + modelData.version : "")
                                        site: Catalog.byId(modelData.id)?.site ?? ""
                                        aka: Catalog.byId(modelData.id)?.aka ?? []
                                    }
                                }

                                // ---- installed ----
                                PageHeader {
                                    visible: root.page === root.installedPage
                                    icon: "download_done"
                                    title: Translation.tr("Installed apps on this PC")
                                    subtitle: Winget.listedOnce ? Translation.tr("%1 apps").arg(root.installedShown.length) : Translation.tr("Asking winget what is installed…")
                                    actionText: Winget.listing ? "" : Translation.tr("Refresh")
                                    onAction: Winget.refreshInstalled()
                                }
                                Skeleton {
                                    visible: root.page === root.installedPage && !Winget.listedOnce
                                }
                                Repeater {
                                    model: root.page === root.installedPage ? root.installedShown : []
                                    delegate: StoreCard {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        appId: modelData.id
                                        name: modelData.name
                                        description: `${modelData.id}  ·  ${modelData.version}`
                                        site: Catalog.byId(modelData.id)?.site ?? ""
                                    }
                                }

                                // ---- updates ----
                                PageHeader {
                                    visible: root.page === root.updatesPage && !root.searching
                                    icon: "update"
                                    title: Winget.listing && Winget.upgrades.length === 0 ? Translation.tr("Checking…") : (Winget.upgrades.length === 0 ? Translation.tr("Everything is up to date") : Translation.tr("%1 updates").arg(Winget.upgrades.length))
                                    subtitle: Winget.upgrades.length > 0 ? Translation.tr("Updates install one after another; some ask for administrator permission.") : ""
                                    actionText: Winget.upgrades.length > 0 ? Translation.tr("Update all") : ""
                                    actionPrimary: true
                                    onAction: Winget.upgradeAll()
                                }
                                Skeleton {
                                    visible: root.page === root.updatesPage && !root.searching && Winget.listing && Winget.upgrades.length === 0
                                }
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

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 6
                                    visible: root.page === 0 && !root.searching
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    text: Translation.tr("Apps come from the winget catalogue (the same as `winget install`). Some ask for administrator permission.")
                                }
                            }
                        }
                        SmoothWheelArea {
                            anchors.fill: flick
                            flickable: flick
                        }
                    }

                    OperationsBar {
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    // ---- pieces ----------------------------------------------------------------------------------------------------
    component TitleButton: RippleButton {
        id: titleButton
        property string symbol
        buttonRadius: Appearance.rounding.full
        implicitWidth: 36
        implicitHeight: 36
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: titleButton.symbol
            iconSize: 20
            color: Appearance.colors.colOnLayer0
        }
    }

    component SectionHeader: RowLayout {
        id: header
        property string icon
        property string title
        property string actionText
        signal action()
        Layout.fillWidth: true
        spacing: 10
        MaterialSymbol {
            text: header.icon
            iconSize: 22
            fill: 1
            color: Appearance.colors.colPrimary
        }
        StyledText {
            Layout.fillWidth: true
            text: header.title
            font.pixelSize: Appearance.font.pixelSize.huge
            font.weight: Font.Medium
            color: Appearance.colors.colOnLayer1
        }
        RippleButton {
            visible: header.actionText !== ""
            implicitHeight: 36
            implicitWidth: seeAll.implicitWidth + 28
            buttonRadius: Appearance.rounding.full
            onClicked: header.action()
            contentItem: RowLayout {
                id: seeAll
                anchors.centerIn: parent
                spacing: 4
                StyledText {
                    text: header.actionText
                    font.weight: Font.Medium
                    color: Appearance.colors.colPrimary
                }
                MaterialSymbol {
                    text: "arrow_forward"
                    iconSize: 18
                    color: Appearance.colors.colPrimary
                }
            }
        }
    }

    component PageHeader: RowLayout {
        id: pageHeader
        property string icon
        property string title
        property string subtitle
        property string actionText
        property bool actionPrimary: false
        signal action()
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        spacing: 14
        MaterialShape {
            implicitSize: 52
            shape: MaterialShape.Shape.Cookie7Sided
            color: Appearance.colors.colSecondaryContainer
            MaterialSymbol {
                anchors.centerIn: parent
                text: pageHeader.icon
                iconSize: 24
                fill: 1
                color: Appearance.colors.colOnSecondaryContainer
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: pageHeader.title
                elide: Text.ElideRight
                font.pixelSize: 26
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: pageHeader.subtitle
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
        RippleButton {
            visible: pageHeader.actionText !== ""
            implicitHeight: 40
            implicitWidth: headerAction.implicitWidth + 32
            buttonRadius: Appearance.rounding.full
            colBackground: pageHeader.actionPrimary ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
            colBackgroundHover: pageHeader.actionPrimary ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
            onClicked: pageHeader.action()
            contentItem: StyledText {
                id: headerAction
                anchors.centerIn: parent
                text: pageHeader.actionText
                font.weight: Font.Medium
                color: pageHeader.actionPrimary ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            }
        }
    }

    // Rows that breathe while winget answers (it takes a few seconds the first time).
    component Skeleton: ColumnLayout {
        id: skeleton
        Layout.fillWidth: true
        spacing: 10
        Repeater {
            model: 4
            delegate: Rectangle {
                required property int index
                Layout.fillWidth: true
                implicitHeight: 84
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1
                SequentialAnimation on opacity {
                    running: skeleton.visible
                    loops: Animation.Infinite
                    PauseAnimation { duration: index * 120 }
                    NumberAnimation { from: 1; to: 0.45; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.45; to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
                Rectangle {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 52
                    height: 52
                    radius: 15
                    color: Appearance.colors.colLayer2
                }
                Column {
                    x: 80
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Rectangle { width: 180 + (index % 3) * 40; height: 14; radius: 7; color: Appearance.colors.colLayer2 }
                    Rectangle { width: 260 + (index % 2) * 60; height: 10; radius: 5; color: Appearance.colors.colLayer2 }
                }
            }
        }
    }

    // What winget is doing now: the app, a wavy progress bar, how many wait; the last failure with "Try again".
    component OperationsBar: Rectangle {
        id: ops
        readonly property var job: Winget.current
        readonly property var jobState: job ? Winget.stateOf(job.id) : null
        readonly property var failure: {
            const p = Winget.progress;
            for (const key in p) if (p[key].state === "error") return { id: key, op: p[key].op, message: p[key].message };
            return null;
        }
        readonly property bool shown: job !== null || failure !== null
        implicitHeight: shown ? 64 : 0
        visible: implicitHeight > 0
        clip: true
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3inverseSurface
        Behavior on implicitHeight {
            NumberAnimation { duration: 260 * Appearance.motionFactor; easing.type: Easing.OutCubic }
        }

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 18
                rightMargin: 10
            }
            spacing: 14
            MaterialSymbol {
                text: ops.job ? (ops.job.op === "uninstall" ? "delete" : ops.job.op === "upgrade" ? "update" : "download") : "error"
                iconSize: 24
                color: ops.job ? Appearance.m3colors.m3inversePrimary : Appearance.m3colors.m3error
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: Appearance.m3colors.m3inverseOnSurface
                    text: {
                        if (ops.job) {
                            const w = ops.job.op === "install" ? Translation.tr("Installing %1") : ops.job.op === "upgrade" ? Translation.tr("Updating %1") : Translation.tr("Uninstalling %1");
                            const waiting = Winget.queue.length > 0 ? "  ·  " + Translation.tr("%1 waiting").arg(Winget.queue.length) : "";
                            return w.arg(ops.job.name) + waiting;
                        }
                        if (ops.failure) return Translation.tr("winget could not finish (%1). Some apps need you to accept a permission prompt.").arg(ops.failure.message);
                        return "";
                    }
                }
                StyledProgressBar {
                    Layout.fillWidth: true
                    visible: ops.job !== null && (ops.jobState?.percent ?? -1) >= 0
                    wavy: true
                    highlightColor: Appearance.m3colors.m3inversePrimary
                    trackColor: Qt.alpha(Appearance.m3colors.m3inverseOnSurface, 0.2)
                    value: Math.max(0, ops.jobState?.percent ?? 0) / 100
                }
                StyledIndeterminateProgressBar {
                    Layout.fillWidth: true
                    visible: ops.job !== null && (ops.jobState?.percent ?? -1) < 0
                }
            }
            RippleButton {
                visible: ops.job === null && ops.failure !== null
                implicitHeight: 36
                implicitWidth: dismissText.implicitWidth + 28
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Qt.alpha(Appearance.m3colors.m3inverseOnSurface, 0.1)
                onClicked: Winget.dismiss(ops.failure.id)
                contentItem: StyledText {
                    id: dismissText
                    anchors.centerIn: parent
                    text: Translation.tr("Dismiss")
                    font.weight: Font.Medium
                    color: Appearance.m3colors.m3inversePrimary
                }
            }
        }
    }
}
