// Placeholder until the Windows backend exists. Same API as Quickshell's module.
pragma Singleton
import QtQuick

QtObject {
    enum Enum { None, Track, Playlist }
    function toString(value) { return ['None', 'Track', 'Playlist'][value] ?? "Unknown" }

}
