import QtQuick
import "../../../Rice"
import "../../../Rice/Color.js" as C

// A colour picker for a light: hue across, saturation down (pale at the bottom); brightness stays on its
// own slider. The knob is solid while the light shows a colour (`engaged`). Reports `picked(hue, sat)`
// (0..359, 0..100) while pressed and dragged.
Item {
    id: hf
    required property RicePalette pal
    property real ui: 1
    property int hue: 0
    property int sat: 100
    property bool engaged: false
    signal picked(int hue, int sat)
    function u(n) { return Math.round(n * ui) }
    implicitHeight: u(56)

    Rectangle {
        anchors.fill: parent
        radius: hf.u(14)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#ff0000" }
            GradientStop { position: 1 / 6; color: "#ffff00" }
            GradientStop { position: 2 / 6; color: "#00ff00" }
            GradientStop { position: 3 / 6; color: "#00ffff" }
            GradientStop { position: 4 / 6; color: "#0000ff" }
            GradientStop { position: 5 / 6; color: "#ff00ff" }
            GradientStop { position: 1; color: "#ff0000" }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: hf.u(14)
        border.width: 1
        border.color: C.alpha(hf.pal.edge, Tokens.alpha.outlineStrong)
        gradient: Gradient {
            GradientStop { position: 0; color: "#00ffffff" }
            GradientStop { position: 1; color: "#ffffff" }
        }
    }
    Rectangle {     // the knob
        readonly property real inset: hf.u(9)
        x: inset + (hf.hue / 359) * (hf.width - 2 * inset) - width / 2
        y: inset + (1 - hf.sat / 100) * (hf.height - 2 * inset) - height / 2
        width: hf.u(16); height: width; radius: width / 2
        color: Qt.hsva(hf.hue / 360, hf.sat / 100, 1, 1)
        border.width: hf.u(2)
        border.color: "white"
        opacity: hf.engaged || m.pressed ? 1 : 0.5
        scale: m.pressed ? 1.15 : 1
        Behavior on scale { NumberAnimation { duration: Tokens.fast } }
        Behavior on opacity { NumberAnimation { duration: Tokens.base } }
    }
    MouseArea {
        id: m
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.CrossCursor
        function pick(x, y) {
            const across = Math.max(0, Math.min(1, x / width)), down = Math.max(0, Math.min(1, y / height))
            hf.picked(Math.min(359, Math.round(across * 359)), Math.round((1 - down) * 100))
        }
        onPressed: mouse => pick(mouse.x, mouse.y)
        onPositionChanged: mouse => { if (pressed) pick(mouse.x, mouse.y) }
    }
}
