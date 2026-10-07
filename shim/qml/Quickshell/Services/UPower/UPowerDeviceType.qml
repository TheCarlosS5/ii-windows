// Placeholder until the Windows backend exists. Same API as Quickshell's module.
pragma Singleton
import QtQuick

QtObject {
    enum Enum { Unknown, LinePower, Battery, Ups, Monitor, Mouse, Keyboard }
    function toString(value) { return ['Unknown', 'LinePower', 'Battery', 'Ups', 'Monitor', 'Mouse', 'Keyboard'][value] ?? "Unknown" }

}
