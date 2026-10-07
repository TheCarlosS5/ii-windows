// Placeholder until the Windows backend exists. Same API as Quickshell's module.
pragma Singleton
import QtQuick

QtObject {
    enum Enum { Disabled, Enabled, Enabling, Disabling, Blocked }
    function toString(value) { return ['Disabled', 'Enabled', 'Enabling', 'Disabling', 'Blocked'][value] ?? "Unknown" }

}
