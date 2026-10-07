// Placeholder until the Windows backend exists. Same API as Quickshell's module.
pragma Singleton
import QtQuick

QtObject {
    enum Enum { Unknown, Expired, Dismissed, CloseRequested }
    function toString(value) { return ["Unknown", "Expired", "Dismissed", "CloseRequested"][value] ?? "Unknown" }
}
