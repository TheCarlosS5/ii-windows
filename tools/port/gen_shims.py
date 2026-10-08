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

# UPower: native Windows battery + documented power schemes.

# Mpris: real module (GSMTC) in quickshell/src/win32/services/mpris.cpp

# SystemTray: real module (Shell_NotifyIcon) in quickshell/src/win32/services/tray.cpp

# Notifications: real module (toasts + notify-send) in quickshell/src/win32/services/notifications.cpp

# Bluetooth: native Windows radio/device watchers.

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
