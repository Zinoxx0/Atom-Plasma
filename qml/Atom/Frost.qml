import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// A piece of frosted glass over the bare wallpaper: the screen's pre-blurred wallpaper (`backdrop`, a
// full-window texture provider, e.g. a ShaderEffectSource) cut to this piece's rounded shape, under a tint,
// a breath of light at the top, a hairline rim (rimA -> rimB) and a soft shadow. Unlike KWin's blur it
// fades and moves with the piece, so it's for surfaces that show the wallpaper itself (the launcher, which
// clears the windows away first).
//
// Place it directly in a full-window container (its x/y are window coordinates: the texture is shifted
// by them so the frost lines up with the real wallpaper). Content goes inside, like a Rectangle.
Item {
    id: f
    property Item backdrop: null
    property real radius: 20
    property color tint: "#12131a"
    property real tintAlpha: 0.5
    property color rimA: "white"
    property color rimB: "white"
    property real rimAlpha: 0.32
    property real sheen: 0.07
    property real lift: 1                   // shadow strength
    // where this piece sits in the window, if its own x/y aren't that (it lives in a moved parent)
    property real originX: x
    property real originY: y

    RectangularShadow {
        anchors.fill: parent
        visible: f.lift > 0.01 && f.width > 2
        radius: f.radius
        blur: 30
        spread: -6
        offset.y: 8
        color: Qt.rgba(0, 0, 0, 0.36 * f.lift)
    }
    Shape {
        anchors.fill: parent
        visible: f.width > 2 && f.height > 2
        preferredRendererType: Shape.CurveRenderer
        ShapePath {         // the frost: the blurred wallpaper right under this piece
            strokeWidth: -1
            strokeColor: "transparent"
            fillItem: f.backdrop
            fillTransform: PlanarTransform.fromTranslate(-f.originX, -f.originY)
            PathRectangle { x: 0; y: 0; width: f.width; height: f.height; radius: f.radius }
        }
        ShapePath {         // the tint (obsidian), with the light at the top
            strokeWidth: -1
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: Math.min(f.height, 120)
                GradientStop { position: 0; color: Qt.rgba(Math.min(1, f.tint.r + f.sheen), Math.min(1, f.tint.g + f.sheen), Math.min(1, f.tint.b + f.sheen), f.tintAlpha) }
                GradientStop { position: 1; color: Qt.rgba(f.tint.r, f.tint.g, f.tint.b, f.tintAlpha) }
            }
            PathRectangle { x: 0; y: 0; width: f.width; height: f.height; radius: f.radius }
        }
        ShapePath {         // the rim
            fillColor: "transparent"
            strokeWidth: 1
            strokeColor: "white"
            strokeGradient: LinearGradient {
                x1: 0; y1: 0; x2: f.width; y2: f.height * 0.4
                GradientStop { position: 0; color: Qt.rgba(f.rimA.r, f.rimA.g, f.rimA.b, f.rimAlpha) }
                GradientStop { position: 1; color: Qt.rgba(f.rimB.r, f.rimB.g, f.rimB.b, f.rimAlpha) }
            }
            PathRectangle { x: 0.5; y: 0.5; width: Math.max(0, f.width - 1); height: Math.max(0, f.height - 1); radius: Math.max(0, f.radius - 0.5) }
        }
    }
}
