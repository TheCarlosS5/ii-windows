// Placeholder until the Windows backend exists. Same API as Quickshell's module.
pragma Singleton
import QtQuick

QtObject {
    enum Enum { Unknown, Charging, Discharging, Empty, FullyCharged, PendingCharge, PendingDischarge }
    function toString(value) { return ['Unknown', 'Charging', 'Discharging', 'Empty', 'FullyCharged', 'PendingCharge', 'PendingDischarge'][value] ?? "Unknown" }

}
