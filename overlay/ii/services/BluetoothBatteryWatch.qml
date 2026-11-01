pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth

/**
 * ii-windows (plan 2026-10-31, E5): a notice when a connected Bluetooth device (headphones like the PRO60) runs low:
 * once below 20 %, again below 10 %, and again only after it was charged above 30 % or reconnected. The level is the
 * one Windows' Bluetooth settings show (the fork reads it from the device node); devices that publish none are silent.
 */
Singleton {
    id: root
    property var warned: ({}) // address → the lowest threshold already announced (20 or 10)
    function load() {}

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.check()
    }
    function check() {
        const devices = Bluetooth.devices?.values ?? [];
        const next = {};
        for (const d of devices) {
            if (!d.connected || !d.batteryAvailable) continue;
            const level = Math.round(d.battery * 100);
            let shown = root.warned[d.address] ?? 100;
            if (level > 30) shown = 100; // charged: warn again next time
            const threshold = level <= 10 ? 10 : level < 20 ? 20 : 100;
            if (threshold < shown) {
                shown = threshold;
                Quickshell.execDetached(["notify-send", "-a", "Bluetooth", "-u", threshold === 10 ? "critical" : "normal",
                    Translation.tr("%1 is running low").arg(d.name), Translation.tr("%1 % battery left").arg(level)]);
            }
            next[d.address] = shown;
        }
        root.warned = next; // a device that disconnects is forgotten (warned again when it comes back low)
    }
}
