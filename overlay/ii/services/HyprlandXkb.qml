pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Windows
import qs.modules.common

/**
 * ii-windows: the keyboard layout indicator's data from Windows' input languages
 * (Quickshell.Windows KeyboardLayouts) instead of Hyprland's xkb devices. Same API as ii's:
 * the bar shows it when more than one layout is installed; codes are locale names ("es-CO"),
 * the indicator shows their language part.
 */
Singleton {
    id: root
    property list<string> layoutCodes: KeyboardLayouts.codes
    property var cachedLayoutCodes: ({})
    property string currentLayoutName: KeyboardLayouts.currentName
    property string currentLayoutCode: KeyboardLayouts.current
}
