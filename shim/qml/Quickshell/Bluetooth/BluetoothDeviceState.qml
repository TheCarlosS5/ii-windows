// Placeholder until the Windows backend exists. Same API as Quickshell's module.
pragma Singleton
import QtQuick

QtObject {
    enum Enum { Disconnected, Connected, Disconnecting, Connecting }
    function toString(value) { return ['Disconnected', 'Connected', 'Disconnecting', 'Connecting'][value] ?? "Unknown" }

}
