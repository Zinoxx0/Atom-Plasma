import QtQuick
import QtQuick.Effects

// A picture with rounded corners and a soft shadow (the Theme page's option pictures): whatever its children draw is
// cut to the rounded rect (one mask layer).
Item {
    id: rp
    required property Item studio
    property real radius: studio.d(14)
    default property alias content: inner.data
    RectangularShadow { anchors.fill: parent; radius: rp.radius; blur: rp.studio.d(20); offset.y: rp.studio.d(6); spread: -rp.studio.d(6); color: Qt.rgba(0, 0, 0, 0.3) }
    Item {
        id: inner
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: mask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
    }
    Rectangle { id: mask; anchors.fill: parent; radius: rp.radius; visible: false; layer.enabled: true }
}
