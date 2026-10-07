// Placeholder until the Windows backend exists. Same API as Quickshell's module.
pragma Singleton
import QtQuick

QtObject {
    enum Enum { None, LapDetected, HighTemperature }
    function toString(value) { return ['None', 'LapDetected', 'HighTemperature'][value] ?? "Unknown" }

}
