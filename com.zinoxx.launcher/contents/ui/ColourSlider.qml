import QtQuick
import "Rice"
import "Rice/Color.js" as C

// One channel of a colour (hue, saturation or lightness, HSL) as a painted track with a round knob
// in the colour it would make. Drag, click or scroll; `moved` reports the new value (0..1).
// channel "x": a plain amount, the track running from `from` to `to` (intensity).
Item {
    id: sl
    required override property RicePalette palette
    property string channel: "h"        // "h" | "s" | "l" | "x"
    property real h: 0
    property real s: 1
    property real l: 0.5
    property color from: "#808080"      // channel "x"
    property color to: "#ffffff"
    property real value: 0              // 0..1
    signal moved(real value)
    signal released()                   // the drag ended (or a scroll step): time to commit

    implicitHeight: 22
    // the colour at t along the track; the hue track keeps enough colour to read as a rainbow
    function at(t) {
        if (channel === "h") return Qt.hsla(t, Math.max(s, 0.55), Math.min(0.62, Math.max(l, 0.42)), 1)
        if (channel === "s") return Qt.hsla(h, t, l, 1)
        if (channel === "l") return Qt.hsla(h, s, t, 1)
        return C.mix(from, to, t)
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        radius: height / 2
        border.width: 1
        border.color: C.alpha(sl.palette.edge, 0.14)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: sl.at(0.0) }
            GradientStop { position: 1 / 6; color: sl.at(1 / 6) }
            GradientStop { position: 2 / 6; color: sl.at(2 / 6) }
            GradientStop { position: 3 / 6; color: sl.at(3 / 6) }
            GradientStop { position: 4 / 6; color: sl.at(4 / 6) }
            GradientStop { position: 5 / 6; color: sl.at(5 / 6) }
            GradientStop { position: 1.0; color: sl.at(1.0) }
        }
    }
    Rectangle {
        id: knob
        width: sl.height
        height: width
        radius: width / 2
        x: Math.max(0, Math.min(1, sl.value)) * (sl.width - width)
        color: sl.at(sl.value)
        border.width: 2.5
        border.color: "#ffffff"
        scale: drag.pressed ? 1.14 : drag.containsMouse ? 1.06 : 1
        Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }
        Rectangle {     // a dark hairline round the white ring, so the knob reads on light tracks too
            anchors.fill: parent
            anchors.margins: -1
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.32)
        }
    }
    MouseArea {
        id: drag
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        function at(x) { return Math.max(0, Math.min(1, (x - sl.height / 2) / Math.max(1, sl.width - sl.height))) }
        onPressed: mouse => sl.moved(at(mouse.x))
        onPositionChanged: mouse => { if (pressed) sl.moved(at(mouse.x)) }
        onReleased: sl.released()
    }
    WheelHandler {
        onWheel: event => {
            sl.moved(Math.max(0, Math.min(1, sl.value + (event.angleDelta.y > 0 ? 0.01 : -0.01))))
            sl.released()
        }
    }
}
