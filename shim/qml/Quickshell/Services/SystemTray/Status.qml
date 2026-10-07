// Placeholder until the Windows backend exists. Same API as Quickshell's module.
pragma Singleton
import QtQuick

QtObject {
    enum Enum { Passive, Active, NeedsAttention }
    function toString(value) { return ['Passive', 'Active', 'NeedsAttention'][value] ?? "Unknown" }

}
