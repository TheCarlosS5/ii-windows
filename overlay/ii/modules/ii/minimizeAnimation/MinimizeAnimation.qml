import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland

// ii-windows (plan 2.2): minimizing a window sends a card with its app's icon from where the window was down into the
// dock (towards the side the dock is on). Windows' own animation is off meanwhile (ii-host, minanim.cpp, in memory
// only). ii cannot animate other programs' windows without injecting into them, which is ruled out: the real window is
// minimized at once and what moves is ii's own. (A card, not the window's picture: DWM shows nothing for a window that
// is already minimized, and asking it stalled the shell.)
// Restoring has no animation of ii's: the real window is back in full at once, and anything flying out of the dock
// on top of it showed the window twice (review). Windows' restore animation is the same setting, so it is off too.
// Settings > Interface > Window animations: on/off, duration, curve. Nothing in the lightweight mode (reduceMotion).
Scope {
    id: root

    readonly property bool enabled: (Config.options.windowAnimations?.minimizeToDock ?? true) && !(Config.options.appearance.reduceMotion ?? false)
    readonly property int duration: Math.max(100, Math.min(600, Config.options.windowAnimations?.duration ?? 320))
    readonly property bool expressive: (Config.options.windowAnimations?.curve ?? "expressive") !== "linear"

    // One flight at a time per screen is plenty; a new one replaces the old.
    signal fly(var toplevel, rect from)

    // Where each window was before it was minimized (the tracker reports the minimized state before the
    // off-screen geometry, so the last on-screen rectangle is known when the minimize arrives).
    Instantiator {
        model: ToplevelManager.toplevels
        delegate: QtObject {
            id: tracked
            required property var modelData
            property rect last: Qt.rect(0, 0, 0, 0)
            function remember() {
                const g = tracked.modelData.geometry;
                if (!tracked.modelData.minimized && g.width > 0 && g.x > -30000)
                    tracked.last = Qt.rect(g.x, g.y, g.width, g.height);
            }
            Component.onCompleted: remember()
            property Connections watch: Connections {
                target: tracked.modelData
                function onGeometryChanged() {
                    tracked.remember();
                }
                function onMinimizedChanged() {
                    if (root.enabled && tracked.modelData.minimized && tracked.last.width > 0)
                        root.fly(tracked.modelData, tracked.last);
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlay
            required property var modelData
            screen: modelData
            // Shown once at start-up, empty and click-through, so the first minimize does not wait for the window
            // to be created (that took longer than the whole flight).
            property bool warming: true
            Timer {
                running: true
                interval: 1500
                onTriggered: overlay.warming = false
            }
            visible: flight.flying || overlay.warming
            color: "transparent"
            WlrLayershell.namespace: "quickshell:minimizeAnimation"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            mask: Region {} // never takes a click

            readonly property real dpr: overlay.modelData.devicePixelRatio ?? 1
            // The screen's size, not the window's: hidden between flights, the window has no size yet.
            readonly property real screenW: overlay.modelData.width
            readonly property real screenH: overlay.modelData.height
            // Physical (GetWindowRect) to this window's logical coordinates. Qt on Windows keeps each screen's
            // top-left in native pixels and scales only its size.
            function toLocal(r) {
                return Qt.rect((r.x - overlay.modelData.x) / overlay.dpr, (r.y - overlay.modelData.y) / overlay.dpr, r.width / overlay.dpr, r.height / overlay.dpr);
            }
            // The dock's middle on its edge (the whole dock, not the app's icon: close enough at this speed).
            function dockPoint() {
                const edge = Config.options.dock.position ?? "bottom";
                const w = overlay.screenW, h = overlay.screenH;
                if (!(Config.options.dock.enable ?? true))
                    return Qt.point(w / 2, h - 24);
                if (edge === "left")
                    return Qt.point(Math.max(24, GlobalStates.dockInsetLeft / 2), h / 2);
                if (edge === "right")
                    return Qt.point(w - Math.max(24, GlobalStates.dockInsetRight / 2), h / 2);
                return Qt.point(w / 2, h - Math.max(24, GlobalStates.dockInsetBottom / 2));
            }

            Connections {
                target: root
                function onFly(toplevel, from) {
                    const local = overlay.toLocal(from);
                    const cx = local.x + local.width / 2, cy = local.y + local.height / 2;
                    // Only the screen the window was on.
                    if (cx < 0 || cy < 0 || cx > overlay.screenW || cy > overlay.screenH)
                        return;
                    flight.finish();
                    card.icon = Quickshell.iconPath(AppSearch.iconForWindow(toplevel.appId ?? "", toplevel.executable ?? ""), "application-x-executable");
                    card.baseWidth = local.width;
                    card.baseHeight = local.height;
                    const target = overlay.dockPoint();
                    const end = Math.min(1, 48 / Math.max(1, local.width));
                    const startX = local.x, startY = local.y;
                    const endX = target.x - local.width * end / 2, endY = target.y - local.height * end / 2;
                    flight.from = [startX, startY, 1, 1];
                    flight.to = [endX, endY, end, 0.25];
                    flight.begin();
                }
            }

            // The minimizing window as a card in ii's surface colour with its app's icon (M3 Expressive shapes).
            Rectangle {
                id: card
                property real baseWidth: 0
                property real baseHeight: 0
                property real s: 1
                property string icon: ""
                visible: flight.flying
                width: baseWidth * s
                height: baseHeight * s
                radius: Math.min(Appearance.rounding.windowRounding, width / 4)
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                IconImage {
                    anchors.centerIn: parent
                    implicitSize: Math.max(16, Math.min(96, Math.min(card.width, card.height) * 0.6))
                    source: card.icon
                }
            }

            // Driven by a timer, not a Qt Quick animation: an animation tied to this window's frames did not advance at
            // all - the flight jumped from start to end.
            Timer {
                id: flight
                property var from: [0, 0, 1, 1] // x, y, scale, opacity
                property var to: [0, 0, 1, 1]
                readonly property Item item: card
                property real started: 0
                property bool flying: false
                readonly property var curve: root.expressive ? Appearance.animationCurves.expressiveDefaultSpatial : [0, 0, 1, 1]
                interval: 16
                repeat: true
                function begin() {
                    flight.started = 0; // the clock starts at the first tick, once the window is up
                    flight.flying = true;
                    flight.apply(0);
                    flight.start();
                }
                function finish() {
                    flight.stop();
                    flight.flying = false;
                }
                // y of the cubic Bezier (0,0) (x1,y1) (x2,y2) (1,1) at x = p (Newton's method on x).
                function ease(p) {
                    const c = flight.curve;
                    const bez = (t, a, b) => 3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t;
                    let t = p;
                    for (let i = 0; i < 6; i++) {
                        const x = bez(t, c[0], c[2]) - p;
                        const dx = 3 * c[0] * (1 - t) * (1 - t) + 6 * (c[2] - c[0]) * t * (1 - t) + 3 * (1 - c[2]) * t * t;
                        if (Math.abs(dx) < 1e-6)
                            break;
                        t = Math.max(0, Math.min(1, t - x / dx));
                    }
                    return bez(t, c[1], c[3]);
                }
                function apply(p) {
                    const e = flight.ease(p);
                    const lerp = (i, k) => flight.from[i] + (flight.to[i] - flight.from[i]) * k;
                    flight.item.x = lerp(0, e);
                    flight.item.y = lerp(1, e);
                    flight.item.s = Math.max(0.01, lerp(2, e));
                    flight.item.opacity = lerp(3, p); // the fade without the spring
                }
                onTriggered: {
                    if (flight.started === 0)
                        flight.started = Date.now();
                    const p = Math.min(1, (Date.now() - flight.started) / root.duration);
                    flight.apply(p);
                    if (p >= 1)
                        flight.finish();
                }
            }
        }
    }
}
