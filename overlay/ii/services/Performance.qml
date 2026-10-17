pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common
import qs.services

// ii-windows: the light mode, one switch for modest PCs. It is a preset of options that exist on their own:
// no decorative animation, no transparency (and so no frosted glass behind panels), no translucency for other
// programs' windows (ii-host stops touching them) and a dock that does not magnify. Every one of them can still be
// changed afterwards in Settings; "full effects" puts the usual values back.
Singleton {
    id: root

    readonly property bool light: Config.ready && Config.options.appearance.reduceMotion
        && !Config.options.appearance.transparency.enable && !Config.options.appearance.windowEffects.transparency

    // A PC where the light mode is worth offering: few processor threads or little memory (an old laptop, a
    // Celeron/Pentium, 4 GB). 0 = not known yet (SystemInfo asks ii-shim once at start).
    readonly property bool modestHardware: (SystemInfo.threads > 0 && SystemInfo.threads <= 4)
        || (SystemInfo.memoryMB > 0 && SystemInfo.memoryMB < 7000)
    readonly property bool suggested: modestHardware && !light

    function setLight(on) {
        Config.options.appearance.reduceMotion = on;
        Config.options.appearance.transparency.enable = !on;
        Config.options.appearance.windowEffects.transparency = !on;
        Config.options.dock.magnification = on ? 1 : 1.7;
    }

    // "4 threads, 4 GB": for the texts that offer the light mode.
    readonly property string hardwareText: {
        const parts = [];
        if (SystemInfo.threads > 0)
            parts.push(Translation.tr("%1 processor threads").arg(SystemInfo.threads));
        if (SystemInfo.memoryMB > 0)
            parts.push(Translation.tr("%1 GB of memory").arg(Math.round(SystemInfo.memoryMB / 1024)));
        return parts.join(", ");
    }
}
