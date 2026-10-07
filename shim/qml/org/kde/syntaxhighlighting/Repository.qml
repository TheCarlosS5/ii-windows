// Placeholder until the Windows backend exists. Same API as Quickshell's module.
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
