pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.ii.background.widgets
import qs.modules.ii.mediaControls

// ii-windows: ii's player card (the one in the bar's media popup) on the desktop, for whatever
// is playing: cover, title, artist, progress and controls. It hides while nothing plays.
// Drag it by its edges like the clock.
AbstractBackgroundWidget {
    id: root

    configEntryName: "media"
    readonly property MprisPlayer player: MprisController.activePlayer
    implicitWidth: Appearance.sizes.mediaControlsWidth
    implicitHeight: Appearance.sizes.mediaControlsHeight
    opacity: (root.player === null || (GlobalStates.screenLocked && !visibleWhenLocked)) ? 0 : 1

    Loader {
        anchors.fill: parent
        active: root.player !== null
        sourceComponent: PlayerControl {
            player: root.player
            radius: Appearance.rounding.windowRounding
        }
    }
}
