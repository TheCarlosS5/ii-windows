import QtQuick

QtObject {
    id: root
    property bool active: false
    onActiveChanged: AudioSpectrum.setDemand(root, active)
    Component.onCompleted: AudioSpectrum.setDemand(root, active)
    Component.onDestruction: AudioSpectrum.setDemand(root, false)
}
