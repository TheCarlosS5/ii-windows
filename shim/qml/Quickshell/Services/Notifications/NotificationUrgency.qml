// Placeholder until the Windows backend exists. Same API as Quickshell's module.
pragma Singleton
import QtQuick

QtObject {
    enum Enum { Low, Normal, Critical }
    function toString(value) { return ['Low', 'Normal', 'Critical'][value] ?? "Unknown" }

}
