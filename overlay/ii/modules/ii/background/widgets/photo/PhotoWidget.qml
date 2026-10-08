pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import QtCore
import Quickshell

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

// ii-windows: a photo of your choice anywhere on the desktop (a local image or an https URL;
// gifs play), like the overlay's floating image but under the windows. Drag to move, wheel to
// resize; right click adds its options to the desktop menu (menuEntries).
AbstractBackgroundWidget {
    id: root

    configEntryName: "photo"
    acceptedButtons: Qt.LeftButton
    implicitWidth: imageReady ? imageWidth * displayFactor : Math.min(280, maximumWidth)
    implicitHeight: imageReady ? imageHeight * displayFactor : Math.min(emptyColumn.implicitHeight + 24, maximumHeight)

    readonly property string imageSource: configEntry.source
    readonly property string imageSourceUrl: imageUrl(imageSource)
    readonly property real scaleFactor: Math.max(0.3, Math.min(3, configEntry.scale))
    readonly property int imageWidth: animatedImage.sourceSize.width
    readonly property int imageHeight: animatedImage.sourceSize.height
    readonly property bool imageReady: animatedImage.status === Image.Ready && imageWidth > 0 && imageHeight > 0
    readonly property bool imageFailed: imageSource.length > 0 && (imageSourceUrl.length === 0 || animatedImage.status === Image.Error)
    // Account for the base widget's slight enlargement while dragging as well.
    readonly property real maximumWidth: screenWidth * 0.9 / Math.max(1, scale)
    readonly property real maximumHeight: screenHeight * 0.9 / Math.max(1, scale)
    readonly property real displayFactor: imageFactor(imageWidth, imageHeight, scaleFactor,
        screenWidth / Math.max(1, scale), screenHeight / Math.max(1, scale))

    // Shown at the top of the desktop menu when it is opened over this widget.
    readonly property var menuEntries: [
        { icon: "image", text: Translation.tr("Change photo…"), action: () => root.choosePhoto() },
        { icon: "restart_alt", text: Translation.tr("Reset size"), action: () => root.configEntry.scale = 1 },
        { icon: "open_in_new", text: Translation.tr("Open image"), action: () => root.openImage() },
        { icon: "close", text: Translation.tr("Remove from desktop"), action: () => root.configEntry.enable = false },
    ]

    function nativePath(path) {
        let value = path.toString().replace(/\\/g, "/");
        if (/^file:\/\//i.test(value)) {
            value = value.replace(/^file:\/\//i, "");
            // A file URL's authority is a UNC server; three slashes mean a drive path.
            if (!value.startsWith("/")) value = "//" + value;
            try {
                value = decodeURIComponent(value);
            } catch (error) {
                return "";
            }
            value = value.replace(/^\/(?=[A-Za-z]:\/)/, "");
        }
        return value.replace(/\//g, "\\");
    }

    function imageUrl(path) {
        const value = path.toString();
        if (/^https:\/\//i.test(value)) return value;
        const localPath = nativePath(value).replace(/\\/g, "/");
        // Reject other schemes (including http) and relative paths.
        if (!/^[A-Za-z]:\//.test(localPath) && !/^\/\/[^/]+\//.test(localPath)) return "";
        // Keep literal '#', '%' and Unicode in Windows filenames out of URL syntax.
        const encoded = localPath.split("/").map(segment => encodeURIComponent(segment)).join("/");
        return localPath.startsWith("//") ? "file:" + encoded
            : "file:///" + encoded.replace(/^([A-Za-z])%3A/i, "$1:");
    }

    function nextScale(value, delta) {
        return Math.max(0.3, Math.min(3, Math.round((value + delta) * 10) / 10));
    }

    function imageFactor(width, height, sizeScale, availableWidth, availableHeight) {
        if (width <= 0 || height <= 0) return 0;
        const fitted = Math.min(1, 360 / width, 360 / height);
        return Math.min(fitted * sizeScale, availableWidth * 0.9 / width, availableHeight * 0.9 / height);
    }

    function choosePhoto() {
        photoDialog.currentFolder = StandardPaths.writableLocation(StandardPaths.PicturesLocation);
        photoDialog.open();
    }

    function openImage() {
        if (imageSourceUrl.length === 0) return;
        Quickshell.execDetached(["xdg-open", /^https:\/\//i.test(imageSource) ? imageSource : nativePath(imageSource)]);
    }

    onWheel: event => {
        if (!root.imageReady || event.angleDelta.y === 0) {
            event.accepted = false;
            return;
        }
        root.configEntry.scale = root.nextScale(root.scaleFactor, event.angleDelta.y > 0 ? 0.1 : -0.1);
        event.accepted = true;
    }
    onVisibleChanged: {
        if (!visible) photoDialog.close();
    }

    StyledDropShadow {
        visible: root.imageReady
        target: photoMask
    }

    // Rounded corners as ii does them (MaskMultiEffect): the image and a rounded rectangle are
    // drawn offscreen and the effect shows the image through the rectangle.
    Item {
        id: photoSource
        anchors.fill: parent
        visible: false
        layer.enabled: true

        AnimatedImage {
            id: animatedImage
            anchors.fill: parent
            // Leave sourceSize unset: it supplies the natural size, without a resize loop.
            source: root.imageSourceUrl
            asynchronous: true
            smooth: true
            fillMode: Image.PreserveAspectFit
            // Its own `visible` is false here (offscreen source): follow the widget instead.
            playing: root.imageReady && root.visible && root.configEntry.enable && ((QsWindow.window as QsWindow)?.visible ?? false)
        }
    }

    Rectangle {
        id: photoMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        radius: Appearance.rounding.large
        color: "black"
    }

    MaskMultiEffect {
        anchors.fill: parent
        visible: root.imageReady
        source: photoSource
        maskSource: photoMask
    }

    StyledDropShadow {
        visible: emptyCard.visible
        target: emptyCard
    }

    Rectangle {
        id: emptyCard
        anchors.fill: parent
        visible: !root.imageReady
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer0

        Column {
            id: emptyColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 12

            MaterialSymbol {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "add_photo_alternate"
                iconSize: 40
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer0
                text: root.imageFailed ? Translation.tr("Couldn't load the photo") : Translation.tr("Choose a photo")
            }
            RippleButton {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: 140
                implicitHeight: 36
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                onClicked: root.choosePhoto()
                contentItem: StyledText {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: Appearance.colors.colOnPrimaryContainer
                    text: Translation.tr("Choose…")
                }
            }
        }
    }

    FileDialog {
        id: photoDialog
        title: Translation.tr("Choose a photo")
        fileMode: FileDialog.OpenFile
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        nameFilters: [Translation.tr("Images (*.jpg *.jpeg *.png *.gif *.webp *.bmp)")]
        onAccepted: root.configEntry.source = root.nativePath(selectedFile.toString())
    }
}
