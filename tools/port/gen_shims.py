"""Writes shim/qml: QML-only stand-ins for Quickshell service modules that do not have a
Windows backend yet. Each mirrors the real module's QML API (names, enums, signals) and
reports "nothing available", so shells load and simply show empty sections. They are
replaced one by one by C++ modules with real Windows backends.
"""
import os
import textwrap

ROOT = os.path.join(os.path.dirname(__file__), '..', '..', 'shim', 'qml')

HEADER = '// Placeholder until the Windows backend exists. Same API as Quickshell\'s module.\n'

def model():
    # ObjectModel stand-in: usable as a view model and exposes `.values`.
    return 'ListModel { property var values: [] }'

FILES = {}

def module(uri, entries, files):
    path = os.path.join(ROOT, *uri.split('.'))
    lines = [f'module {uri}'] + entries
    FILES[os.path.join(path, 'qmldir')] = '\n'.join(lines) + '\n'
    for name, body in files.items():
        FILES[os.path.join(path, name)] = HEADER + textwrap.dedent(body).lstrip()

def enum_singleton(values, extra=''):
    names = ', '.join(values)
    return f'''
    pragma Singleton
    import QtQuick

    QtObject {{
        enum Enum {{ {names} }}
        function toString(value) {{ return [{', '.join(repr(v) for v in values)}][value] ?? "Unknown" }}
        {extra}
    }}
    '''

# --- UPower --------------------------------------------------------------------------------
module('Quickshell.Services.UPower', [
    'singleton UPower 0.1 UPower.qml',
    'singleton PowerProfiles 0.1 PowerProfiles.qml',
    'singleton PowerProfile 0.1 PowerProfile.qml',
    'singleton PerformanceDegradationReason 0.1 PerformanceDegradationReason.qml',
    'singleton UPowerDeviceState 0.1 UPowerDeviceState.qml',
    'singleton UPowerDeviceType 0.1 UPowerDeviceType.qml',
    'UPowerDevice 0.1 UPowerDevice.qml',
], {
    'UPower.qml': f'''
    pragma Singleton
    import QtQuick

    QtObject {{
        readonly property UPowerDevice displayDevice: UPowerDevice {{}}
        readonly property var devices: {model()}
        readonly property bool onBattery: false
    }}
    ''',
    'UPowerDevice.qml': '''
    import QtQuick

    QtObject {
        property int type: 0
        property bool powerSupply: false
        property real energy: 0
        property real energyCapacity: 0
        property real changeRate: 0
        property real timeToEmpty: 0
        property real timeToFull: 0
        property real percentage: 0
        property bool isPresent: false
        property int state: 0
        property real healthPercentage: 0
        property bool healthSupported: false
        property string iconName: ""
        property bool isLaptopBattery: false
        property string nativePath: ""
        property string model: ""
        property bool ready: true
    }
    ''',
    'PowerProfiles.qml': '''
    pragma Singleton
    import QtQuick

    QtObject {
        property int profile: 1
        readonly property bool hasPerformanceProfile: false
        readonly property int degradationReason: 0
        readonly property var holds: []
    }
    ''',
    'PowerProfile.qml': enum_singleton(['PowerSaver', 'Balanced', 'Performance']),
    'PerformanceDegradationReason.qml': enum_singleton(['None', 'LapDetected', 'HighTemperature']),
    'UPowerDeviceState.qml': enum_singleton(['Unknown', 'Charging', 'Discharging', 'Empty', 'FullyCharged', 'PendingCharge', 'PendingDischarge']),
    'UPowerDeviceType.qml': enum_singleton(['Unknown', 'LinePower', 'Battery', 'Ups', 'Monitor', 'Mouse', 'Keyboard']),
})

# --- Mpris ---------------------------------------------------------------------------------
module('Quickshell.Services.Mpris', [
    'singleton Mpris 0.1 Mpris.qml',
    'singleton MprisPlaybackState 0.1 MprisPlaybackState.qml',
    'singleton MprisLoopState 0.1 MprisLoopState.qml',
    'MprisPlayer 0.1 MprisPlayer.qml',
], {
    'Mpris.qml': f'''
    pragma Singleton
    import QtQuick

    QtObject {{
        readonly property var players: {model()}
    }}
    ''',
    'MprisPlaybackState.qml': enum_singleton(['Stopped', 'Playing', 'Paused']),
    'MprisLoopState.qml': enum_singleton(['None', 'Track', 'Playlist']),
    'MprisPlayer.qml': '''
    import QtQuick

    QtObject {
        property bool canControl: false
        property bool canPlay: false
        property bool canPause: false
        property bool canTogglePlaying: false
        property bool canSeek: false
        property bool canGoNext: false
        property bool canGoPrevious: false
        property bool canQuit: false
        property bool canRaise: false
        property string identity: ""
        property string desktopEntry: ""
        property string dbusName: ""
        property real position: 0
        property bool positionSupported: false
        property real length: 0
        property bool lengthSupported: false
        property real volume: 1
        property bool volumeSupported: false
        property var metadata: ({})
        property int uniqueId: 0
        property string trackTitle: ""
        property string trackArtist: ""
        property string trackArtists: ""
        property string trackAlbum: ""
        property string trackAlbumArtist: ""
        property string trackArtUrl: ""
        property int playbackState: 0
        property bool isPlaying: false
        property int loopState: 0
        property bool loopSupported: false
        property real rate: 1
        property bool shuffle: false
        property bool shuffleSupported: false
        signal postTrackChanged()
        function raise() {}
        function quit() {}
        function next() {}
        function previous() {}
        function seek(offset) {}
        function play() {}
        function pause() {}
        function stop() {}
        function togglePlaying() {}
    }
    ''',
})

# --- SystemTray ----------------------------------------------------------------------------
module('Quickshell.Services.SystemTray', [
    'singleton SystemTray 0.1 SystemTray.qml',
    'singleton Status 0.1 Status.qml',
    'singleton Category 0.1 Category.qml',
    'SystemTrayItem 0.1 SystemTrayItem.qml',
], {
    'SystemTray.qml': f'''
    pragma Singleton
    import QtQuick

    QtObject {{
        readonly property var items: {model()}
    }}
    ''',
    'Status.qml': enum_singleton(['Passive', 'Active', 'NeedsAttention']),
    'Category.qml': enum_singleton(['ApplicationStatus', 'Communications', 'SystemServices', 'Hardware']),
    'SystemTrayItem.qml': '''
    import QtQuick

    QtObject {
        property string id: ""
        property string title: ""
        property int status: 0
        property int category: 0
        property string icon: ""
        property string tooltipTitle: ""
        property string tooltipDescription: ""
        property var menu: null
        property bool hasMenu: false
        property bool onlyMenu: false
        function activate() {}
        function secondaryActivate() {}
        function scroll(delta, horizontal) {}
        function display(parentWindow, relativeX, relativeY) {}
    }
    ''',
})

# --- Notifications ---------------------------------------------------------------------------
module('Quickshell.Services.Notifications', [
    'NotificationServer 0.1 NotificationServer.qml',
    'Notification 0.1 Notification.qml',
    'NotificationAction 0.1 NotificationAction.qml',
    'singleton NotificationUrgency 0.1 NotificationUrgency.qml',
    'singleton NotificationCloseReason 0.1 NotificationCloseReason.qml',
], {
    'NotificationServer.qml': f'''
    import QtQuick

    QtObject {{
        property bool keepOnReload: true
        property bool persistenceSupported: false
        property bool bodySupported: true
        property bool bodyMarkupSupported: false
        property bool bodyHyperlinksSupported: false
        property bool bodyImagesSupported: false
        property bool actionsSupported: false
        property bool actionIconsSupported: false
        property bool imageSupported: false
        property bool inlineReplySupported: false
        property var extraHints: []
        readonly property var trackedNotifications: {model()}
        signal notification(var notification)
    }}
    ''',
    'Notification.qml': '''
    import QtQuick

    QtObject {
        property int id: 0
        property bool tracked: false
        property bool lastGeneration: false
        property real expireTimeout: -1
        property string appName: ""
        property string appIcon: ""
        property string summary: ""
        property string body: ""
        property int urgency: 1
        property var actions: []
        property bool hasActionIcons: false
        property bool resident: false
        property bool transient: false
        property string desktopEntry: ""
        property string image: ""
        property bool hasInlineReply: false
        property string inlineReplyPlaceholder: ""
        property var hints: ({})
        signal closed(int reason)
        function expire() { closed(1) }
        function dismiss() { closed(2) }
        function sendInlineReply(text) {}
    }
    ''',
    'NotificationAction.qml': '''
    import QtQuick

    QtObject {
        property string identifier: ""
        property string text: ""
        function invoke() {}
    }
    ''',
    'NotificationUrgency.qml': enum_singleton(['Low', 'Normal', 'Critical']),
    'NotificationCloseReason.qml': '''
    pragma Singleton
    import QtQuick

    QtObject {
        enum Enum { Unknown, Expired, Dismissed, CloseRequested }
        function toString(value) { return ["Unknown", "Expired", "Dismissed", "CloseRequested"][value] ?? "Unknown" }
    }
    ''',
})

# --- Bluetooth -----------------------------------------------------------------------------
module('Quickshell.Bluetooth', [
    'singleton Bluetooth 0.1 Bluetooth.qml',
    'singleton BluetoothAdapterState 0.1 BluetoothAdapterState.qml',
    'singleton BluetoothDeviceState 0.1 BluetoothDeviceState.qml',
    'BluetoothAdapter 0.1 BluetoothAdapter.qml',
    'BluetoothDevice 0.1 BluetoothDevice.qml',
], {
    'Bluetooth.qml': f'''
    pragma Singleton
    import QtQuick

    QtObject {{
        readonly property var defaultAdapter: null
        readonly property var adapters: {model()}
        readonly property var devices: {model()}
    }}
    ''',
    'BluetoothAdapterState.qml': enum_singleton(['Disabled', 'Enabled', 'Enabling', 'Disabling', 'Blocked']),
    'BluetoothDeviceState.qml': enum_singleton(['Disconnected', 'Connected', 'Disconnecting', 'Connecting']),
    'BluetoothAdapter.qml': f'''
    import QtQuick

    QtObject {{
        property string name: ""
        property string adapterId: ""
        property bool enabled: false
        property int state: 0
        property bool discoverable: false
        property bool discovering: false
        property bool pairable: false
        readonly property var devices: {model()}
    }}
    ''',
    'BluetoothDevice.qml': '''
    import QtQuick

    QtObject {
        property string address: ""
        property string deviceName: ""
        property string name: ""
        property string icon: ""
        property bool connected: false
        property bool paired: false
        property bool bonded: false
        property bool trusted: false
        property bool blocked: false
        property bool pairing: false
        property bool batteryAvailable: false
        property real battery: 0
        property int state: 0
        function connect() {}
        function disconnect() {}
        function pair() {}
        function cancelPair() {}
        function forget() {}
    }
    ''',
})

# --- Polkit / Pam: Windows uses UAC and its own lock screen --------------------------------
module('Quickshell.Services.Polkit', ['PolkitAgent 0.1 PolkitAgent.qml'], {
    'PolkitAgent.qml': '''
    import QtQuick

    // Windows elevation is UAC's job; this agent never receives requests.
    QtObject {
        readonly property bool isActive: false
        readonly property bool isRegistered: false
        readonly property var flow: null
        property string path: ""
        signal authenticationRequestStarted()
    }
    ''',
})

module('Quickshell.Services.Pam', [
    'PamContext 0.1 PamContext.qml',
    'singleton PamResult 0.1 PamResult.qml',
], {
    'PamContext.qml': '''
    import QtQuick

    // No PAM on Windows; locking uses the Windows lock screen instead.
    QtObject {
        property string config: "login"
        property string configDirectory: ""
        property string user: ""
        property bool active: false
        readonly property string message: ""
        readonly property bool messageIsError: false
        readonly property bool responseRequired: false
        readonly property bool responseVisible: false
        signal completed(int result)
        signal error(int error)
        signal pamMessage()
        function start() { completed(2) }
        function abort() {}
        function respond(response) {}
    }
    ''',
    'PamResult.qml': enum_singleton(['Success', 'Failed', 'Error', 'MaxTries']),
})

# --- KDE bits used for icons and code highlighting -----------------------------------------
module('org.kde.kirigami', ['Icon 2.0 Icon.qml'], {
    'Icon.qml': '''
    import QtQuick
    import QtQuick.Effects
    import Quickshell

    // Kirigami.Icon subset: theme icon names resolve through Quickshell's icon provider.
    Item {
        id: root
        property var source: ""
        property var fallback: "application-x-executable"
        property bool isMask: false
        property color color: "transparent"
        property bool roundToIconSize: true
        property bool animated: false
        property bool active: false
        property bool selected: false
        property string placeholder: ""
        readonly property bool valid: image.status === Image.Ready
        readonly property int status: image.status
        implicitWidth: 32
        implicitHeight: 32

        function resolve(src) {
            const s = String(src ?? "");
            if (s.length === 0) return "";
            if (s.indexOf("/") >= 0 || s.indexOf(":") >= 0) return s;
            return Quickshell.iconPath(s, String(root.fallback));
        }

        Image {
            id: image
            anchors.fill: parent
            source: root.resolve(root.source)
            sourceSize: Qt.size(root.width * 2, root.height * 2)
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            visible: !root.isMask
            asynchronous: true
        }
        MultiEffect {
            anchors.fill: image
            source: image
            visible: root.isMask
            colorization: 1
            colorizationColor: root.color
        }
    }
    ''',
})

module('org.kde.syntaxhighlighting', [
    'SyntaxHighlighter 1.0 SyntaxHighlighter.qml',
    'singleton Repository 1.0 Repository.qml',
], {
    'SyntaxHighlighter.qml': '''
    import QtQuick

    // No-op: code blocks render as plain text until a highlighter is ported.
    QtObject {
        property var textEdit: null
        property var repository: null
        property var definition: null
        property var theme: null
    }
    ''',
    'Repository.qml': '''
    pragma Singleton
    import QtQuick

    QtObject {
        function definitionForName(name) { return null }
        function definitionForFileName(name) { return null }
        function theme(name) { return null }
        function defaultTheme(type) { return null }
        readonly property var definitions: []
        readonly property var themes: []
    }
    ''',
})

for path, text in FILES.items():
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
print(f'wrote {len(FILES)} files under {os.path.normpath(ROOT)}')
