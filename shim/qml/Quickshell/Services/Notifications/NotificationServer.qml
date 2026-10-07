// Placeholder until the Windows backend exists. Same API as Quickshell's module.
import QtQuick

QtObject {
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
    readonly property var trackedNotifications: ListModel { property var values: [] }
    signal notification(var notification)
}
