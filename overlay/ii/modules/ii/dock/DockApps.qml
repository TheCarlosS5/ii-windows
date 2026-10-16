pragma ComponentBehavior: Bound
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// ii-windows: the whole dock inside its panel window, macOS style. Icons grow under the cursor
// (parabolic bell around the pointer), the dock sits at the bottom or at the left/right edge,
// pinned apps can be dragged to reorder. Window management (mask, hide/show, reserved space)
// lives in Dock.qml; this item fills the window and draws everything.
Item {
    id: root

    required property string edge // "bottom" | "left" | "right"
    property bool revealed: true
    readonly property bool vertical: edge !== "bottom"

    // --- configuration -------------------------------------------------------------------
    readonly property real iconSize: Math.max(24, Config.options.dock.iconSize)
    readonly property real maxScale: Math.max(1, Config.options.dock.magnification)
    readonly property real magRange: iconSize * Math.max(1, Config.options.dock.magnificationRange)
    readonly property real gap: 4
    readonly property real pad: 8
    readonly property real dotZone: 10
    readonly property real edgeGap: Appearance.sizes.hyprlandGapsOut + 1
    readonly property real labelZone: Config.options.dock.showLabels ? 40 : 0
    readonly property real bgThick: iconSize + pad + dotZone
    readonly property real overflow: iconSize * (maxScale - 1)
    // Cross size of the panel window: everything the dock can draw, magnified.
    readonly property real thickness: edgeGap + bgThick + overflow + labelZone + Appearance.sizes.elevationMargin
    // Space a pinned dock takes from the work area (not the magnified part).
    readonly property real reservedThickness: edgeGap + bgThick // windows and panels stop at the dock's top edge

    readonly property real mainLen: vertical ? height : width
    readonly property real crossLen: vertical ? width : height

    // --- state exposed to Dock.qml ----------------------------------------------------------
    readonly property bool hovering: hover.hovered
    // The pointer is over the dock itself (not only over the empty margin of the window).
    readonly property bool active: hover.hovered && crossDistance <= edgeGap + bgThick + overflow + 6
    readonly property bool requestDockShow: previewPopup.show || contextMenu.shown
    readonly property real stripMain: layout.total + pad * 2
    readonly property real stripMainOrigin: layout.origin - pad
    property real slide: 0 // pixels the dock is slid out of the screen (0 = visible)

    // --- pointer ----------------------------------------------------------------------------
    property real pointer: -100000 // along the main axis, window coordinates
    property real pointerCross: 100000
    readonly property real crossDistance: edge === "bottom" ? crossLen - pointerCross
        : edge === "left" ? pointerCross : crossLen - pointerCross
    property real magnitude: 0
    Behavior on magnitude {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
    property int dragIndex: -1
    property var dragOrder: null
    property real dragPointer: 0
    readonly property bool dragging: dragIndex >= 0

    HoverHandler {
        id: hover
        onPointChanged: {
            root.pointer = root.vertical ? point.position.y : point.position.x;
            root.pointerCross = root.vertical ? point.position.x : point.position.y;
        }
    }
    readonly property bool wantMagnify: root.active && !root.dragging && root.revealed
    onWantMagnifyChanged: magnitude = wantMagnify ? 1 : 0

    // --- model --------------------------------------------------------------------------------
    readonly property var entries: {
        const apps = TaskbarApps.apps;
        const list = apps.slice();
        if (apps.length > 0)
            list.push({ appId: "SEPARATOR_END", toplevels: [], pinned: false });
        list.push({ appId: "LAUNCHPAD", toplevels: [], pinned: false });
        if (Config.options.dock.showStore ?? true)
            list.push({ appId: "STORE", toplevels: [], pinned: false });
        return list;
    }
    property real storeLaunchedAt: 0 // the store button ignores a second click within a few seconds
    function isSeparator(e) {
        return e.appId === "SEPARATOR" || e.appId === "SEPARATOR_END";
    }
    function restSize(e) {
        return isSeparator(e) ? 14 : iconSize + gap;
    }

    // Everything about where each slot is and how big, for the current pointer.
    readonly property var layout: {
        const n = entries.length;
        const order = (dragOrder && dragOrder.length === n) ? dragOrder : Array.from({ length: n }, (_, i) => i);
        const restStart = new Array(n);
        const restSz = new Array(n);
        let restTotal = 0;
        for (let k = 0; k < n; k++) {
            const i = order[k];
            restSz[i] = restSize(entries[i]);
            restStart[i] = restTotal;
            restTotal += restSz[i];
        }
        const restOrigin = mainLen / 2 - restTotal / 2;
        const mag = magnitude;
        const scales = new Array(n);
        const sizes = new Array(n);
        const pos = new Array(n);
        let total = 0;
        for (let k = 0; k < n; k++) {
            const i = order[k];
            const e = entries[i];
            let s = 1;
            if (!isSeparator(e) && mag > 0 && maxScale > 1 && i !== dragIndex) {
                const c = restOrigin + restStart[i] + restSz[i] / 2;
                const t = Math.abs(pointer - c) / magRange;
                if (t < 1)
                    s = 1 + (maxScale - 1) * mag * (0.5 + 0.5 * Math.cos(Math.PI * t));
            }
            scales[i] = s;
            sizes[i] = isSeparator(e) ? restSz[i] : iconSize * s + gap;
            pos[i] = total;
            total += sizes[i];
        }
        const origin = mainLen / 2 - total / 2;
        for (let i = 0; i < n; i++)
            pos[i] += origin;
        return { scales, sizes, pos, total, origin, restTotal, restOrigin, order };
    }

    // The icon under the pointer (labels).
    readonly property int hoveredIndex: {
        if (!active || dragging)
            return -1;
        let best = -1, bestDist = 1e9;
        for (let i = 0; i < entries.length; i++) {
            if (isSeparator(entries[i]))
                continue;
            const c = layout.pos[i] + layout.sizes[i] / 2;
            const d = Math.abs(pointer - c);
            if (d < bestDist) { bestDist = d; best = i; }
        }
        return bestDist <= (iconSize * maxScale) ? best : -1;
    }

    // --- drag to reorder pinned apps ----------------------------------------------------------
    function beginDrag(index) {
        dragIndex = index;
        dragPointer = pointer;
        dragOrder = Array.from({ length: entries.length }, (_, i) => i);
        previewPopup.show = false;
        lastHoveredButton = null;
        buttonHovered = false;
    }
    function updateDrag(mainPointer) {
        if (dragIndex < 0)
            return;
        dragPointer = mainPointer;
        const n = entries.length;
        let pinnedCount = 0;
        while (pinnedCount < n && entries[pinnedCount].pinned) pinnedCount++;
        // Insertion index among the pinned apps from the pointer (rest layout).
        const others = [];
        for (let i = 0; i < pinnedCount; i++)
            if (i !== dragIndex) others.push(i);
        let target = 0;
        let acc = layout.restOrigin;
        for (const i of others) {
            const mid = acc + restSize(entries[i]) / 2;
            if (mainPointer > mid) target++;
            acc += restSize(entries[i]);
        }
        const order = others.slice(0, target).concat([dragIndex], others.slice(target));
        for (let i = pinnedCount; i < n; i++) order.push(i);
        dragOrder = order;
    }
    function endDrag(commit) {
        if (dragIndex < 0)
            return;
        const order = dragOrder;
        const moved = entries;
        dragIndex = -1;
        dragOrder = null;
        if (!commit || !order)
            return;
        const pinsCfg = Config.options.dock.pinnedApps;
        const keys = [];
        for (const i of order)
            if (moved[i].pinned) keys.push(moved[i].appId);
        const next = [];
        for (const key of keys) {
            const original = pinsCfg.find(id => TaskbarApps.canonicalId(id) === key.toLowerCase());
            if (original !== undefined) next.push(original);
        }
        for (const id of pinsCfg)
            if (next.indexOf(id) === -1) next.push(id);
        if (next.join("|") !== pinsCfg.join("|"))
            Config.options.dock.pinnedApps = next;
    }

    // --- previews / menus ------------------------------------------------------------------
    property Item lastHoveredButton: null
    property bool buttonHovered: false
    property real maxWindowPreviewHeight: 200
    property real maxWindowPreviewWidth: 300
    property real windowControlsHeight: 30

    // Main-axis centre of a slot, in window coordinates (what popups anchor to).
    function centerOfButton(button) {
        return button ? button.centerMain : 0;
    }
    function openContextMenu(button) {
        previewPopup.show = false;
        contextMenu.open(button);
    }

    DockContextMenu {
        id: contextMenu
        dockApps: root
    }

    // --- drawing -----------------------------------------------------------------------------
    Item {
        id: content
        anchors.fill: parent
        transform: Translate {
            x: root.edge === "left" ? -root.slide : root.edge === "right" ? root.slide : 0
            y: root.edge === "bottom" ? root.slide : 0
        }

        // Background strip: follows the magnified width.
        StyledRectangularShadow {
            target: bgRect
        }
        Rectangle {
            id: bgRect
            readonly property real len: root.stripMain
            readonly property real start: root.stripMainOrigin
            width: root.vertical ? root.bgThick : len
            height: root.vertical ? len : root.bgThick
            x: root.edge === "bottom" ? start : root.edge === "left" ? root.edgeGap : root.width - root.edgeGap - width
            y: root.edge === "bottom" ? root.height - root.edgeGap - height : start
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            radius: Appearance.rounding.large

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onPressed: mouse => {
                    root.openContextMenu(null);
                }
            }
        }

        Repeater {
            model: ScriptModel {
                objectProp: "appId"
                values: root.entries
            }
            delegate: DockAppButton {
                required property var modelData
                required property int index
                appToplevel: modelData
                slotIndex: index
                appListRoot: root
            }
        }

        // Name of the icon under the pointer (macOS shows it above the icon).
        Rectangle {
            id: labelBubble
            readonly property int i: root.hoveredIndex
            readonly property var entry: i >= 0 ? root.entries[i] : null
            readonly property bool wanted: Config.options.dock.showLabels && entry !== null
                && !previewPopup.show && !contextMenu.shown
            property string label: ""
            opacity: wanted ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 120 } }
            radius: Appearance.rounding.small
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            implicitWidth: labelText.implicitWidth + 20
            implicitHeight: labelText.implicitHeight + 10
            width: implicitWidth
            height: implicitHeight
            readonly property real iconTop: i >= 0 ? root.iconSize * root.layout.scales[i] : 0
            readonly property real centerMain: i >= 0 ? root.layout.pos[i] + root.layout.sizes[i] / 2 : 0
            x: root.edge === "bottom" ? centerMain - width / 2
                : root.edge === "left" ? root.edgeGap + root.dotZone + iconTop + 12
                : root.width - root.edgeGap - root.dotZone - iconTop - 12 - width
            y: root.edge === "bottom" ? root.height - root.edgeGap - root.dotZone - iconTop - 12 - height
                : centerMain - height / 2
            onEntryChanged: {
                if (entry)
                    label = root.nameFor(entry);
            }
            StyledText {
                id: labelText
                anchors.centerIn: parent
                text: labelBubble.label
                color: Appearance.m3colors.m3onSurface
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }

    function nameFor(entry) {
        if (entry.appId === "LAUNCHPAD")
            return Translation.tr("Overview");
        if (entry.appId === "STORE")
            return Translation.tr("App store");
        const de = DesktopEntries.heuristicLookup(entry.appId);
        if (de && de.name)
            return de.name;
        const win = entry.toplevels && entry.toplevels.length > 0 ? entry.toplevels[0] : null;
        return win?.title || entry.appId;
    }

    // Window previews on hover (running apps).
    PopupWindow {
        id: previewPopup
        property var appTopLevel: root.lastHoveredButton?.appToplevel

        property bool shouldShow: (popupMouseArea.containsMouse || root.buttonHovered) && appTopLevel && appTopLevel.toplevels && appTopLevel.toplevels.length > 0 && !contextMenu.shown && !root.dragging

        property bool show: false
        property real cachedCenter: 0

        Connections {
            target: root
            function onLastHoveredButtonChanged() {
                if (root.lastHoveredButton && root.QsWindow)
                    previewPopup.cachedCenter = root.centerOfButton(root.lastHoveredButton);
            }
            function onButtonHoveredChanged() {
                if (root.buttonHovered && root.lastHoveredButton && root.QsWindow)
                    previewPopup.cachedCenter = root.centerOfButton(root.lastHoveredButton);
                updateTimer.restart();
            }
        }

        onShouldShowChanged: updateTimer.restart()

        Timer {
            id: updateTimer
            interval: 120
            onTriggered: previewPopup.show = previewPopup.shouldShow
        }

        // Anchored at the outer limit of the magnified dock, so the popup sits just above (beside) it.
        anchor {
            window: root.QsWindow.window
            adjustment: PopupAdjustment.None
            rect.x: root.edge === "left" ? root.edgeGap + root.bgThick + root.overflow + 4
                : root.edge === "right" ? root.width - (root.edgeGap + root.bgThick + root.overflow + 4) : 0
            rect.y: root.edge === "bottom" ? root.height - (root.edgeGap + root.bgThick + root.overflow + 4) : 0
            rect.width: 1
            rect.height: 1
            gravity: root.edge === "bottom" ? (Edges.Top | Edges.Right) : root.edge === "left" ? (Edges.Bottom | Edges.Right) : (Edges.Bottom | Edges.Left)
            edges: Edges.Top | Edges.Left
        }

        visible: popupBackground.opacity > 0
        color: "transparent"
        implicitWidth: root.vertical ? popupMouseArea.implicitWidth : (root.QsWindow.window?.width ?? 1)
        implicitHeight: root.vertical ? (root.QsWindow.window?.height ?? 1) : popupMouseArea.implicitHeight

        MouseArea {
            id: popupMouseArea
            implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: popupBackground.implicitHeight + Appearance.sizes.elevationMargin * 2
            hoverEnabled: true
            x: root.edge === "bottom" ? previewPopup.cachedCenter - width / 2
                : root.edge === "left" ? 0 : parent.width - width
            y: root.edge === "bottom" ? parent.height - height
                : Math.max(0, Math.min(parent.height - height, previewPopup.cachedCenter - height / 2))

            StyledRectangularShadow {
                target: popupBackground
                opacity: previewPopup.show ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            Rectangle {
                id: popupBackground
                property real padding: 5
                opacity: previewPopup.show ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                clip: true
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.normal
                x: Appearance.sizes.elevationMargin
                y: Appearance.sizes.elevationMargin
                implicitHeight: previewRowLayout.implicitHeight + padding * 2
                implicitWidth: previewRowLayout.implicitWidth + padding * 2
                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on implicitHeight {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                RowLayout {
                    id: previewRowLayout
                    anchors.centerIn: parent
                    Repeater {
                        model: ScriptModel {
                            values: previewPopup.appTopLevel?.toplevels ?? []
                        }
                        RippleButton {
                            id: windowButton
                            Layout.fillHeight: true
                            required property var modelData
                            padding: 0
                            middleClickAction: () => {
                                windowButton.modelData?.close();
                            }
                            onClicked: {
                                windowButton.modelData?.activate();
                            }
                            contentItem: ColumnLayout {
                                implicitWidth: screencopyView.implicitWidth
                                implicitHeight: screencopyView.implicitHeight

                                ButtonGroup {
                                    contentWidth: parent.width - anchors.margins * 2
                                    StyledText {
                                        Layout.margins: 5
                                        Layout.fillWidth: true
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        text: windowButton.modelData?.title
                                        elide: Text.ElideRight
                                        color: Appearance.m3colors.m3onSurface
                                    }
                                    GroupButton {
                                        id: closeButton
                                        colBackground: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer)
                                        baseWidth: root.windowControlsHeight
                                        baseHeight: root.windowControlsHeight
                                        buttonRadius: Appearance.rounding.full
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            horizontalAlignment: Text.AlignHCenter
                                            text: "close"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                        onClicked: {
                                            windowButton.modelData?.close();
                                        }
                                    }
                                }
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    implicitHeight: screencopyView.height
                                    implicitWidth: screencopyView.width
                                    ScreencopyView {
                                        id: screencopyView
                                        anchors.centerIn: parent
                                        captureSource: windowButton.modelData
                                        live: true
                                        paintCursor: true
                                        constraintSize: Qt.size(root.maxWindowPreviewWidth, root.maxWindowPreviewHeight)
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: screencopyView.width
                                                height: screencopyView.height
                                                radius: Appearance.rounding.small
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
    }
}
