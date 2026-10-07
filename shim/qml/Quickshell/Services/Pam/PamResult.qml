// Placeholder until the Windows backend exists. Same API as Quickshell's module.
pragma Singleton
import QtQuick

QtObject {
    enum Enum { Success, Failed, Error, MaxTries }
    function toString(value) { return ['Success', 'Failed', 'Error', 'MaxTries'][value] ?? "Unknown" }

}
