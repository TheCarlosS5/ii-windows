"""Audit 2026-10-09, P0 fixes on upstream ii files (exact-match edits of the staged tree, run
after the other patch_ii*.py scripts):
  - battery: no automatic suspend by default; never on AC or on a single reading
  - booru: Gelbooru API key, an honest User-Agent for Danbooru/Konachan, Zerochan's broken JSON,
    Alcy's default tag, error messages per status
  - bar popups and tray tooltips keep their window for a while instead of one per hover
  - desktop widgets know when an app covers their screen; the widget layer sits on whole pixels
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.join(ROOT, *parts)


# --- Battery ------------------------------------------------------------------------------------
# Laptops went to sleep (or hibernated, on Modern Standby) right after installing: ii suspends at
# 3 % on any reading where Windows does not say "Charging", and a 0 % blip at boot is enough.
# Windows has its own critical-battery action, so ii's is off by default; when enabled it needs a
# full minute on battery power below the threshold, with a warning first.
edit(path('modules', 'common', 'Config.qml'), [
    ('                property bool automaticSuspend: true\n',
     '                property bool automaticSuspend: false // ii-windows: Windows has its own critical-battery action\n'),
    ('''                    property JsonObject zerochan: JsonObject {
                        property string username: "[unset]"
                    }
''',
     '''                    property JsonObject zerochan: JsonObject {
                        property string username: "[unset]"
                    }
                    // ii-windows: Gelbooru's API answers 401 without an account's key
                    // (gelbooru.com > My Account > Options > API Access Credentials).
                    property JsonObject gelbooru: JsonObject {
                        property string apiKey: ""
                        property string userId: ""
                    }
'''),
])

edit(path('services', 'Battery.qml'), [
    ('''    onIsSuspendingAndNotChargingChanged: {
        if (root.available && isSuspendingAndNotCharging) {
            Quickshell.execDetached(["ii-shim", "suspend"]); // ii-windows
        }
    }
''',
     '''    // ii-windows: never on one reading and never on AC power (plugged in but full, or held at a
    // charge limit, is not "Charging"): one minute below the threshold on battery, warned first.
    readonly property bool shouldSuspend: root.available && root.isSuspendingAndNotCharging && UPower.onBattery
    onShouldSuspendChanged: {
        if (root.shouldSuspend) {
            suspendTimer.restart();
            Quickshell.execDetached([
                "notify-send",
                Translation.tr("Critically low battery"),
                Translation.tr("The computer will sleep in one minute unless you plug in the charger"),
                "-u", "critical",
                "-a", "Shell",
            ]);
        } else {
            suspendTimer.stop();
        }
    }
    Timer {
        id: suspendTimer
        interval: 60000
        onTriggered: {
            if (root.shouldSuspend)
                Quickshell.execDetached(["ii-shim", "suspend", `battery ${Math.round(root.percentage * 100)}%`]);
        }
    }
'''),
])

# --- Booru (left sidebar) -------------------------------------------------------------------------
edit(path('services', 'Booru.qml'), [
    # Danbooru's Cloudflare answers 403 to a browser User-Agent without cookies; API clients
    # identify themselves.
    ('    property var defaultUserAgent: ',
     '    property string apiUserAgent: "ii-windows (+https://github.com/TheCarlosS5/ii-windows)" // ii-windows\n'
     '    property var defaultUserAgent: '),
    ('''            if (["danbooru", "konachan"].includes(currentProvider)) {
                xhr.setRequestHeader("User-Agent", defaultUserAgent)
            }''',
     '''            if (["danbooru", "konachan"].includes(currentProvider)) {
                xhr.setRequestHeader("User-Agent", root.apiUserAgent)
            }''', 2),
    # Gelbooru: the account's key; Alcy: a tag is required (the bare URL is its home page).
    ('''        if (baseUrl.indexOf("?") === -1) {
            url += "?" + params.join("&")''',
     '''        if (currentProvider === "gelbooru") {
            const key = Config.options?.sidebar?.booru?.gelbooru?.apiKey ?? "";
            const user = Config.options?.sidebar?.booru?.gelbooru?.userId ?? "";
            if (key.length > 0 && user.length > 0)
                params.push("api_key=" + encodeURIComponent(key), "user_id=" + encodeURIComponent(user));
        }
        if (baseUrl.indexOf("?") === -1) {
            url += "?" + params.join("&")'''),
    ('''        else if (currentProvider === "t.alcy.cc") {
            url += tagString''',
     '''        else if (currentProvider === "t.alcy.cc") {
            url += tagString.trim().length > 0 ? tagString.trim() : "ycy"'''),
    # Zerochan's thumbnails are AVIF, which Qt cannot read on Windows (Linux has KDE's image
    # plugins); the same path with .jpg is served too.
    ('''            "description": Translation.tr("Clean stuff | Excellent quality, no NSFW"),
            "mapFunc": (response) => {
                response = response.items''',
     '''            "description": Translation.tr("Clean stuff | Excellent quality, no NSFW"),
            "mapFunc": (response) => {
                response = response.items.map(item => Object.assign(item, { "thumbnail": item.thumbnail?.replace(/\\.avif$/, ".jpg") })) // ii-windows'''),
    ('                        "file_ext": "avif",\n', '                        "file_ext": "jpg",\n'),
    # Zerochan answers 500 with its JSON wrapped in a stray "{" and HTML: read the object anyway.
    ('''            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    // console.log("[Booru] Raw response: " + xhr.responseText)
                    const provider = providers[currentProvider]
                    let response;
                    if (provider.manualParseFunc) {
                        response = provider.manualParseFunc(xhr.responseText)
                    } else {
                        response = JSON.parse(xhr.responseText)''',
     '''            const zerochanBody = currentProvider === "zerochan" && xhr.readyState === XMLHttpRequest.DONE && xhr.responseText.length > 0;
            if (xhr.readyState === XMLHttpRequest.DONE && (xhr.status === 200 || zerochanBody)) {
                try {
                    // console.log("[Booru] Raw response: " + xhr.responseText)
                    const provider = providers[currentProvider]
                    let response;
                    if (provider.manualParseFunc) {
                        response = provider.manualParseFunc(xhr.responseText)
                    } else {
                        response = root.parseJsonLoose(xhr.responseText)'''),
    ('''                console.log("[Booru] Request failed with status: " + xhr.status)
                newResponse.message = root.failMessage
                root.runningRequests--;''',
     '''                console.log("[Booru] Request failed with status: " + xhr.status)
                newResponse.message = root.statusMessage(xhr.status)
                root.runningRequests--;'''),
    ('''    function constructRequestUrl(''',
     '''    // ii-windows: JSON, or the first complete JSON object inside a damaged reply.
    function parseJsonLoose(text) {
        try {
            return JSON.parse(text);
        } catch (e) {
            for (let start = text.indexOf("{"); start >= 0; start = text.indexOf("{", start + 1)) {
                let depth = 0, inString = false, escaped = false;
                for (let i = start; i < text.length; i++) {
                    const c = text[i];
                    if (inString) {
                        if (escaped) escaped = false;
                        else if (c === "\\\\") escaped = true;
                        else if (c === '"') inString = false;
                    } else if (c === '"') inString = true;
                    else if (c === "{") depth++;
                    else if (c === "}" && --depth === 0) {
                        try { return JSON.parse(text.substring(start, i + 1)); } catch (e2) { break; }
                    }
                }
            }
            throw e;
        }
    }

    // ii-windows: say why instead of the generic tips.
    function statusMessage(status) {
        if (status === 401 && currentProvider === "gelbooru")
            return Translation.tr("Gelbooru needs an API key. Create one at gelbooru.com > My Account > Options, then set sidebar.booru.gelbooru.apiKey and userId in ii's config.json");
        if (status === 401 || status === 403)
            return Translation.tr("The site refused the request (%1). It may be blocking this connection, try another provider").arg(status);
        if (status === 0)
            return Translation.tr("No connection to the site. Check your internet");
        if (status === 429)
            return Translation.tr("Too many requests. Wait a moment and try again");
        return root.failMessage;
    }

    function constructRequestUrl('''),
])

# --- Bar popups and tray tooltips -------------------------------------------------------------------
# On Windows a new window costs a device, a swap chain and a first frame: hovering the bar's
# resources/clock/weather/battery or a tray icon created and destroyed one every time, a visible
# pause on laptops. The window now stays (hidden) for a while after the pointer leaves.
edit(path('modules', 'ii', 'bar', 'StyledPopup.qml'), [
    ('    active: hoverTarget && hoverTarget.containsMouse\n',
     '''    // ii-windows: kept for a while, hidden, after the pointer leaves (no window per hover).
    property bool shown: !!hoverTarget && hoverTarget.containsMouse
    property Timer keepAlive: Timer {
        interval: 20000
    }
    onShownChanged: if (!shown) keepAlive.restart()
    active: shown || keepAlive.running
'''),
    ('''    component: PanelWindow {
        id: popupWindow
''',
     '''    component: PanelWindow {
        id: popupWindow
        visible: root.shown
'''),
])

edit(path('modules', 'common', 'widgets', 'PopupToolTip.qml'), [
    ('''        active: root.internalVisibleCondition
        sourceComponent: PopupWindow {
            visible: true''',
     '''        // ii-windows: kept for a while, hidden, after the pointer leaves (no window per hover).
        active: root.internalVisibleCondition || keepAlive.running
        sourceComponent: PopupWindow {
            visible: root.internalVisibleCondition'''),
    ('''    Loader {
        id: tooltipLoader''',
     '''    Timer {
        id: keepAlive
        interval: 15000
    }
    onInternalVisibleConditionChanged: if (!internalVisibleCondition) keepAlive.restart()

    Loader {
        id: tooltipLoader'''),
])

# --- Desktop widgets ------------------------------------------------------------------------------
edit(path('modules', 'ii', 'background', 'widgets', 'AbstractBackgroundWidget.qml'), [
    ('    property bool scalesContent: false\n',
     '    property bool scalesContent: false\n'
     '    // An app covers this screen: no animations or per-second updates (services/DesktopCover).\n'
     '    readonly property bool desktopCovered: DesktopCover.covered(root.QsWindow.window?.screen?.name ?? "")\n'),
])

# The widget layer follows the wallpaper's parallax: keep it on whole pixels so text stays sharp.
edit(path('modules', 'ii', 'background', 'Background.qml'), [
    ('                x: wallpaperTotalOffsetX * parallaxFactor * !locked\n'
     '                y: wallpaperTotalOffsetY * parallaxFactor * !locked\n',
     '                x: Math.round(wallpaperTotalOffsetX * parallaxFactor * !locked)\n'
     '                y: Math.round(wallpaperTotalOffsetY * parallaxFactor * !locked)\n'),
])
