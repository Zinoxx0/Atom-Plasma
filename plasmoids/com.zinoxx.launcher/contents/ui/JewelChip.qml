import QtQuick
import QtQuick.Effects
import "Rice"
import "Rice/Color.js" as C

// The jewel as a chip: the launcher's own accent object (accent fill, no sheen: the rice's rule) carrying
// Atom Plasma's mark (Emblem: its satellites swing once under the pointer). It leads the launcher's top bar
// as its home button, and it's what flies between the bar and there as the launcher opens and closes.
// Under the pointer it speaks the launcher's focus language: the white ring.
Rectangle {
    id: jc
    required property RicePalette rice
    property bool glowing: false            // in flight: it lights its way
    signal clicked()
    radius: Math.round(height * 0.34)
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: jc.rice.primary }
        GradientStop { position: 1; color: jc.rice.tertiary }
    }
    RectangularShadow {
        z: -1
        anchors.fill: parent
        radius: jc.radius
        blur: jc.height * 0.9
        offset.y: jc.height * 0.18
        color: C.alpha(jc.rice.primary, jc.glowing ? 0.55 : 0.0)
    }
    Emblem {
        anchors.centerIn: parent
        scale: Math.min(jc.width, jc.height) * 0.8 / 34
        hovered: ma.containsMouse
        pressed: ma.pressed
        c1: "#ffffff"
        c2: C.mix(jc.rice.tertiary, "#ffffff", 0.55)
        c3: C.mix(jc.rice.red, "#ffffff", 0.15)
        c4: C.mix(jc.rice.teal, "#ffffff", 0.15)
        glow: "#ffffff"
    }
    Rectangle {
        readonly property real gap: Math.max(2, jc.height * 0.07)
        anchors.fill: parent
        anchors.margins: -gap
        radius: jc.radius + gap
        color: "transparent"
        border.width: Math.max(2, jc.height * 0.055)
        border.color: jc.rice.light ? jc.rice.fg : "#ffffff"
        opacity: ma.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
    }
    scale: ma.pressed ? 0.94 : 1
    Behavior on scale { NumberAnimation { duration: Tokens.fast } }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: jc.clicked() }
}
