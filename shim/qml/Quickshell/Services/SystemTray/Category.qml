// Placeholder until the Windows backend exists. Same API as Quickshell's module.
pragma Singleton
import QtQuick

QtObject {
    enum Enum { ApplicationStatus, Communications, SystemServices, Hardware }
    function toString(value) { return ['ApplicationStatus', 'Communications', 'SystemServices', 'Hardware'][value] ?? "Unknown" }

}
