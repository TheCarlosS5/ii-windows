// Placeholder until the Windows backend exists. Same API as Quickshell's module.
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
