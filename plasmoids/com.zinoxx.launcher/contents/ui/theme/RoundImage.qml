import QtQuick
import QtQuick.Effects

// A picture with rounded corners and a soft shadow: an Image cut by a mask (MultiEffect). A grid passes one shared
// mask (`mask`, the tiles' size) so its tiles don't each make their own.
// Not Kirigami's ShadowedTexture: its material keeps the source image's texture, and a Theme page section going away
// with its pictures crashed plasmashell's render thread (SEGV in libKirigamiPrimitives, nested, 2026-11-21).
Item {
    id: ri
    property url source
    property real radius: 8
    property int sourceWidth: 360
    property bool shadow: true
    property real shadowBlur: 14
    property color fill: "transparent"
    property bool asynchronous: true
    property Item mask: null
    property real border: 0
    property color borderColor: "transparent"
    RectangularShadow {
        visible: ri.shadow
        anchors.fill: parent
        radius: ri.radius; blur: ri.shadowBlur; offset.y: ri.shadowBlur * 0.4; spread: -ri.shadowBlur * 0.3
        color: Qt.rgba(0, 0, 0, 0.3)
    }
    Rectangle { anchors.fill: parent; radius: ri.radius; color: ri.fill }
    Image {
        anchors.fill: parent
        source: ri.source
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: ri.sourceWidth
        asynchronous: ri.asynchronous
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: ri.mask || ownMask.item; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
    }
    Rectangle { visible: ri.border > 0; anchors.fill: parent; radius: ri.radius; color: "transparent"; border.width: ri.border; border.color: ri.borderColor }
    Loader {
        id: ownMask
        active: !ri.mask
        sourceComponent: Rectangle { width: ri.width; height: ri.height; radius: ri.radius; visible: false; layer.enabled: true }
    }
}
