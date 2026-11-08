import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// The rice's one glass for every shell panel (the sheet, notification cards, the launcher's cards):
// obsidian over KWin's blur (BlurBehind on the window, set by whoever owns it), a breath of white light
// along the top, a hairline rim running rimA -> rimB like the bar's islands, and a soft neutral shadow.
// Size it like a Rectangle. Colours are plain values: Glass knows nothing of palettes.
Item {
    id: g
    property real radius: 24
    property color fill: "#12131a"
    property real fillAlpha: 0.8
    property color rimA: "white"
    property color rimB: "white"
    property real rimAlpha: 0.5
    property real sheen: 0.06               // the white light at the top (0 = none)
    property real lift: 1                   // 0..1: how far it stands off what's below (shadow strength)

    RectangularShadow {
        anchors.fill: parent
        visible: g.lift > 0.01
        radius: g.radius
        blur: 34
        spread: -6
        offset.y: 10
        color: Qt.rgba(0, 0, 0, 0.42 * g.lift)
    }
    Rectangle {
        anchors.fill: parent
        radius: g.radius
        color: Qt.rgba(g.fill.r, g.fill.g, g.fill.b, g.fillAlpha)
    }
    Rectangle {
        visible: g.sheen > 0
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
        height: Math.min(parent.height * 0.4, 96)
        radius: Math.max(0, g.radius - 1)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, g.sheen) }
            GradientStop { position: 1; color: "transparent" }
        }
    }
    Shape {
        anchors.fill: parent
        visible: g.width > 2 && g.height > 2
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeWidth: 1
            strokeColor: "white"
            strokeGradient: LinearGradient {
                x1: 0; y1: 0; x2: g.width; y2: g.height * 0.3
                GradientStop { position: 0; color: Qt.rgba(g.rimA.r, g.rimA.g, g.rimA.b, g.rimAlpha) }
                GradientStop { position: 1; color: Qt.rgba(g.rimB.r, g.rimB.g, g.rimB.b, g.rimAlpha) }
            }
            PathRectangle {
                x: 0.5; y: 0.5
                width: Math.max(0, g.width - 1); height: Math.max(0, g.height - 1)
                radius: Math.max(0, g.radius - 0.5)
            }
        }
    }
}
