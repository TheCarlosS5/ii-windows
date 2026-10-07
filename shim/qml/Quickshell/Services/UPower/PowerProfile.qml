// Placeholder until the Windows backend exists. Same API as Quickshell's module.
pragma Singleton
import QtQuick

QtObject {
    enum Enum { PowerSaver, Balanced, Performance }
    function toString(value) { return ['PowerSaver', 'Balanced', 'Performance'][value] ?? "Unknown" }

}
