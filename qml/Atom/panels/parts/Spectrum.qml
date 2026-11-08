import QtQuick
import "../../../Rice"
import "../../../Rice/Color.js" as C

// A slider over a spectrum (a light's white, warm to cool): the track is the spectrum itself, the knob
// solid while it's what the light shows (`engaged`), faint otherwise. Dragging reports `moved(v)` in
// from..to, stepped.
Item {
    id: sp
    required property RicePalette pal
    property real ui: 1
    property string label: ""
    property string valueText: ""
    property real from: 0
    property real to: 1
    property real step: 1
    property real value: 0
    property bool engaged: true
    // the spectrum, left to right (five stops)
    property color c0: "#ff8a2a"
    property color c1: "#ffb46b"
    property color c2: "#ffe4ce"
    property color c3: "#f5f3ff"
    property color c4: "#cfdcff"
    signal moved(real v)
    function u(n) { return Math.round(n * ui) }
    implicitHeight: u(40)
    readonly property real frac: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0

    Text {
        anchors { left: parent.left; top: parent.top }
        text: sp.label
        color: sp.pal.fgDim
        font.family: Tokens.font.ui
        font.weight: Font.Medium
        font.pixelSize: sp.u(11)
    }
    Text {
        anchors { right: parent.right; top: parent.top }
        text: sp.valueText
        color: sp.pal.muted
        font.family: Tokens.font.ui
        font.pixelSize: sp.u(11)
    }
    Rectangle {
        id: track
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: sp.u(4) }
        height: sp.u(10)
        radius: height / 2
        border.width: 1
        border.color: C.alpha(sp.pal.edge, Tokens.alpha.outline)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: sp.c0 }
            GradientStop { position: 0.22; color: sp.c1 }
            GradientStop { position: 0.5; color: sp.c2 }
            GradientStop { position: 0.75; color: sp.c3 }
            GradientStop { position: 1; color: sp.c4 }
        }
        Rectangle {     // the knob
            x: Math.max(0, Math.min(parent.width - width, parent.width * sp.frac - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            width: sp.u(drag.pressed || drag.containsMouse ? 18 : 15); height: width; radius: width / 2
            color: "white"
            border.width: sp.u(2)
            border.color: C.alpha("#000000", 0.25)
            opacity: sp.engaged || drag.pressed ? 1 : 0.55
            Behavior on width { NumberAnimation { duration: Tokens.fast } }
            Behavior on opacity { NumberAnimation { duration: Tokens.base } }
        }
        MouseArea {
            id: drag
            anchors.fill: parent
            anchors.margins: -sp.u(8)
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            function pick(x) {
                const f = Math.max(0, Math.min(1, (x - sp.u(8)) / track.width))
                const v = sp.from + Math.round(f * (sp.to - sp.from) / sp.step) * sp.step
                sp.moved(v)
            }
            onPressed: mouse => pick(mouse.x)
            onPositionChanged: mouse => { if (pressed) pick(mouse.x) }
        }
    }
}
