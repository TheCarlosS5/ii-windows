pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

// ii-windows: one slot of the dock (an app, a separator or the overview button). The slot spans
// the window across the dock, its position and size along the dock come from DockApps.layout.
Item {
    id: slot

    property var appToplevel
    required property int slotIndex
    required property var appListRoot // DockApps

    readonly property bool isSeparator: appToplevel.appId === "SEPARATOR" || appToplevel.appId === "SEPARATOR_END"
    readonly property bool isLaunchpad: appToplevel.appId === "LAUNCHPAD"
    readonly property bool isStore: appToplevel.appId === "STORE"
    readonly property bool isSpecial: isLaunchpad || isStore // the two tiles that are not apps
    readonly property var windows: appToplevel.toplevels ?? []
    readonly property bool appIsActive: windows.find(t => t.activated === true) !== undefined
    // Bumped when the Start menu list changes, so the lookup below runs again (a binding, not an assignment).
    property int entriesRevision: 0
    readonly property var desktopEntry: {
        slot.entriesRevision;
        return isSeparator || isSpecial ? null : DesktopEntries.heuristicLookup(appToplevel.appId);
    }
    property int lastFocused: -1

    // The icon. The Start menu entry's when there is one; else the icon of the running program itself, as
    // Windows' own taskbar shows it (a window class only guesses: "Valve.Steam.Client" matched nothing and the
    // dock drew the generic "program" icon); only then the guess by name.
    readonly property string iconName: {
        if (desktopEntry && desktopEntry.icon)
            return desktopEntry.icon;
        return AppSearch.iconForWindow(appToplevel.appId, windows.length > 0 ? windows[0].executable : "");
    }

    readonly property var edge: appListRoot.edge
    readonly property bool vertical: appListRoot.vertical
    readonly property bool dragged: appListRoot.dragIndex === slotIndex
    readonly property real iconSize: appListRoot.iconSize
    readonly property real maxScale: appListRoot.maxScale
    readonly property real s: dragged ? Math.min(maxScale, 1.12) : (appListRoot.layout.scales[slotIndex] ?? 1)
    readonly property real sizeMain: appListRoot.layout.sizes[slotIndex] ?? (iconSize + appListRoot.gap)
    readonly property real posMain: dragged
        ? appListRoot.dragPointer - sizeMain / 2
        : (appListRoot.layout.pos[slotIndex] ?? 0)
    readonly property real centerMain: posMain + sizeMain / 2
    readonly property real vis: iconSize * maxScale // size of the rendered icon at full magnification
    readonly property real iconBase: edge === "bottom" ? appListRoot.crossLen - appListRoot.edgeGap - appListRoot.dotZone
        : edge === "left" ? appListRoot.edgeGap + appListRoot.dotZone
        : appListRoot.crossLen - appListRoot.edgeGap - appListRoot.dotZone

    x: vertical ? 0 : posMain
    y: vertical ? posMain : 0
    width: vertical ? appListRoot.crossLen : sizeMain
    height: vertical ? sizeMain : appListRoot.crossLen
    z: dragged ? 50 : 0

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            slot.entriesRevision++;
        }
    }

    // --- separator ------------------------------------------------------------------------------
    Rectangle {
        visible: slot.isSeparator
        width: slot.vertical ? slot.iconSize * 0.7 : 1
        height: slot.vertical ? 1 : slot.iconSize * 0.7
        radius: 1
        color: Appearance.colors.colOutlineVariant
        x: slot.vertical ? (slot.width - width) / 2 : (slot.width - width) / 2
        y: slot.vertical ? (slot.height - height) / 2
            : slot.iconBase - slot.iconSize / 2 - height / 2
    }

    // --- the icon ---------------------------------------------------------------------------------
    Item {
        id: visual
        visible: !slot.isSeparator
        width: slot.vis
        height: slot.vis
        scale: slot.s / slot.maxScale
        transformOrigin: slot.edge === "bottom" ? Item.Bottom : slot.edge === "left" ? Item.Left : Item.Right
        x: slot.edge === "bottom" ? (slot.width - width) / 2
            : slot.edge === "left" ? slot.iconBase : slot.iconBase - width
        y: slot.vertical ? (slot.height - height) / 2 : slot.iconBase - height

        property real bounce: 0
        transform: Translate {
            x: slot.edge === "left" ? visual.bounce : slot.edge === "right" ? -visual.bounce : 0
            y: slot.edge === "bottom" ? -visual.bounce : 0
        }
        SequentialAnimation {
            id: bounceAnim
            loops: 2
            NumberAnimation { target: visual; property: "bounce"; to: slot.iconSize * 0.45; duration: 230; easing.type: Easing.OutQuad }
            NumberAnimation { target: visual; property: "bounce"; to: 0; duration: 230; easing.type: Easing.InQuad }
        }

        // Icon of an app.
        Loader {
            id: iconLoader
            anchors.fill: parent
            active: !slot.isSpecial && !slot.isSeparator
            sourceComponent: IconImage {
                implicitSize: slot.vis
                mipmap: true
                source: Quickshell.iconPath(slot.iconName, "image-missing")
            }
        }
        Loader {
            active: Config.options.dock.monochromeIcons && iconLoader.active
            anchors.fill: parent
            sourceComponent: Item {
                Desaturate {
                    id: desaturatedIcon
                    visible: false // There's already color overlay
                    anchors.fill: parent
                    source: iconLoader
                    desaturation: 0.8
                }
                ColorOverlay {
                    anchors.fill: desaturatedIcon
                    source: desaturatedIcon
                    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                }
            }
        }

        // The overview button (apps) and the store: tiles like macOS' Launchpad.
        Rectangle {
            visible: slot.isSpecial
            anchors.fill: parent
            anchors.margins: slot.vis * 0.06
            radius: slot.vis * 0.24
            color: Appearance.m3colors.m3primaryContainer
            MaterialSymbol {
                anchors.centerIn: parent
                text: slot.isStore ? "storefront" : "apps"
                iconSize: slot.vis * 0.58
                color: Appearance.m3colors.m3onPrimaryContainer
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            property real pressMain: 0
            property point pressPoint: Qt.point(0, 0)
            property bool wasDragged: false
            // Qt delivers released before clicked: wasDragged is already cleared when clicked runs, so a
            // press that moved keeps its own flag until the next press (a drag must not minimize or launch).
            property bool suppressClick: false

            onEntered: {
                if (slot.windows.length > 0) {
                    slot.appListRoot.lastHoveredButton = slot;
                    slot.appListRoot.buttonHovered = true;
                    slot.lastFocused = slot.windows.length - 1;
                }
            }
            onExited: {
                if (slot.appListRoot.lastHoveredButton === slot)
                    slot.appListRoot.buttonHovered = false;
            }
            onPressed: mouse => {
                wasDragged = false;
                suppressClick = false;
                pressPoint = mapToItem(slot.appListRoot, mouse.x, mouse.y);
                pressMain = slot.vertical ? pressPoint.y : pressPoint.x;
            }
            onPositionChanged: mouse => {
                if (!(mouse.buttons & Qt.LeftButton))
                    return;
                const p = mapToItem(slot.appListRoot, mouse.x, mouse.y);
                // Moved away from where it was pressed: not a click, whether the icon can be dragged or not.
                if (Math.abs(p.x - pressPoint.x) > 10 || Math.abs(p.y - pressPoint.y) > 10)
                    suppressClick = true;
                if (!slot.appToplevel.pinned)
                    return;
                const m = slot.vertical ? p.y : p.x;
                if (!wasDragged && Math.abs(m - pressMain) > 10) {
                    wasDragged = true;
                    slot.appListRoot.beginDrag(slot.slotIndex);
                }
                if (wasDragged)
                    slot.appListRoot.updateDrag(m);
            }
            onReleased: mouse => {
                if (wasDragged) {
                    slot.appListRoot.endDrag(true);
                    wasDragged = false;
                }
            }
            onCanceled: {
                if (wasDragged) {
                    slot.appListRoot.endDrag(false);
                    wasDragged = false;
                }
            }
            onClicked: mouse => {
                if (suppressClick)
                    return;
                if (mouse.button === Qt.RightButton) {
                    if (slot.isSpecial)
                        slot.appListRoot.openContextMenu(null);
                    else
                        slot.appListRoot.openContextMenu(slot);
                } else if (mouse.button === Qt.MiddleButton) {
                    if (!slot.isSpecial) {
                        AppUsage.launch(slot.desktopEntry);
                        bounceAnim.restart();
                    }
                } else {
                    slot.activateApp();
                }
            }
        }
    }

    function activateApp() {
        if (isLaunchpad) {
            GlobalStates.toggleOverview("apps");
            return;
        }
        if (isStore) {
            bounceAnim.restart();
            // One store at a time: a second click within a few seconds is a double click, not a second window.
            if (Date.now() - slot.appListRoot.storeLaunchedAt < 4000)
                return;
            slot.appListRoot.storeLaunchedAt = Date.now();
            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("store.qml")]);
            return;
        }
        // The dock shows with the launcher open (Win): picking an app there leaves the launcher.
        if (GlobalStates.overviewOpen)
            GlobalStates.overviewOpen = false;
        if (windows.length === 0) {
            AppUsage.launch(desktopEntry);
            bounceAnim.restart();
            return;
        }
        // Like the Windows taskbar: the app whose window is in front minimizes.
        if (windows.length === 1 && windows[0].activated && !windows[0].minimized) {
            windows[0].minimized = true;
            return;
        }
        lastFocused = (lastFocused + 1) % windows.length;
        windows[lastFocused].activate();
    }

    // Running indicator (a dot on the side of the screen edge).
    Rectangle {
        visible: !slot.isSeparator && !slot.isSpecial && slot.windows.length > 0
        radius: height / 2
        width: slot.vertical ? 4 : (slot.appIsActive ? 12 : 4)
        height: slot.vertical ? (slot.appIsActive ? 12 : 4) : 4
        color: slot.appIsActive ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.35)
        x: slot.edge === "bottom" ? (slot.width - width) / 2
            : slot.edge === "left" ? slot.iconBase - 8
            : slot.iconBase + 8 - width
        y: slot.vertical ? (slot.height - height) / 2 : slot.iconBase + 5
        Behavior on width { NumberAnimation { duration: 150 } }
        Behavior on height { NumberAnimation { duration: 150 } }
    }
}
