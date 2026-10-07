pragma Singleton
pragma ComponentBehavior: Bound

// ii-windows: same API as ii's nmcli-based Network service, backed by Quickshell.Windows
// (Native Wifi + Network List Manager).

import Quickshell
import Quickshell.Windows as Win
import QtQuick
import qs.services.network

Singleton {
    id: root

    property bool wifi: Win.Network.wifiStatus === "connected"
    property bool ethernet: Win.Network.ethernet

    property bool wifiEnabled: Win.Network.wifiEnabled
    property bool wifiScanning: Win.Network.wifiScanning
    property bool wifiConnecting: wifiConnectTarget !== null
    property WifiAccessPoint wifiConnectTarget: null
    readonly property list<WifiAccessPoint> wifiNetworks: []
    readonly property WifiAccessPoint active: wifiNetworks.find(n => n.active) ?? null
    readonly property list<var> friendlyWifiNetworks: [...wifiNetworks].sort((a, b) => {
        if (a.active && !b.active)
            return -1;
        if (!a.active && b.active)
            return 1;
        return b.strength - a.strength;
    })
    property string wifiStatus: Win.Network.wifiStatus

    property string networkName: Win.Network.networkName
    property int networkStrength: active?.strength ?? 0
    property string materialSymbol: root.ethernet
        ? "lan"
        : (root.wifiEnabled && root.wifiStatus === "connected")
            ? (
                (root.active?.strength ?? 0) > 83 ? "signal_wifi_4_bar" :
                (root.active?.strength ?? 0) > 67 ? "network_wifi" :
                (root.active?.strength ?? 0) > 50 ? "network_wifi_3_bar" :
                (root.active?.strength ?? 0) > 33 ? "network_wifi_2_bar" :
                (root.active?.strength ?? 0) > 17 ? "network_wifi_1_bar" :
                "signal_wifi_0_bar"
            )
            : (root.wifiStatus === "connecting")
                ? "signal_wifi_statusbar_not_connected"
                : (root.wifiStatus === "disconnected")
                    ? "wifi_find"
                    : (root.wifiStatus === "disabled")
                        ? "signal_wifi_off"
                        : "signal_wifi_bad"

    // Control
    function enableWifi(enabled = true): void {
        Win.Network.setWifiEnabled(enabled);
    }

    function toggleWifi(): void {
        enableWifi(!wifiEnabled);
    }

    function rescanWifi(): void {
        Win.Network.scan();
    }

    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        accessPoint.askingPassword = false;
        root.wifiConnectTarget = accessPoint;
        Win.Network.connectTo(accessPoint.ssid);
    }

    function disconnectWifiNetwork(): void {
        if (active) Win.Network.disconnectWifi();
    }

    function openPublicWifiPortal() {
        // Windows' own captive portal check page.
        Quickshell.execDetached(["xdg-open", "http://www.msftconnecttest.com/redirect"]);
    }

    function changePassword(network: WifiAccessPoint, password: string, username = ""): void {
        // TODO: enterprise wifi with username
        network.askingPassword = false;
        root.wifiConnectTarget = network;
        Win.Network.connectWithPassword(network.ssid, password);
    }

    function update() {
        Win.Network.refresh();
    }

    Connections {
        target: Win.Network

        function onConnectFinished(ssid, success, needsPassword) {
            const target = root.wifiConnectTarget;
            if (target && target.ssid === ssid) {
                target.askingPassword = !success && needsPassword;
                root.wifiConnectTarget = null;
            }
        }

        function onNetworksChanged() {
            root.syncNetworks();
        }
    }

    Component.onCompleted: syncNetworks()

    function syncNetworks() {
        const networks = Win.Network.networks;
        const rNetworks = root.wifiNetworks;

        const destroyed = rNetworks.filter(rn => !networks.find(n => n.ssid === rn.ssid));
        for (const network of destroyed)
            rNetworks.splice(rNetworks.indexOf(network), 1).forEach(n => n.destroy());

        for (const network of networks) {
            const match = rNetworks.find(n => n.ssid === network.ssid);
            if (match) {
                match.lastIpcObject = network;
            } else {
                rNetworks.push(apComp.createObject(root, {
                    lastIpcObject: network
                }));
            }
        }
    }

    Component {
        id: apComp

        WifiAccessPoint {}
    }
}
