// Placeholder until the Windows backend exists. Same API as Quickshell's module.
pragma Singleton
import QtQuick

QtObject {
    enum Enum { Stopped, Playing, Paused }
    function toString(value) { return ['Stopped', 'Playing', 'Paused'][value] ?? "Unknown" }

}
