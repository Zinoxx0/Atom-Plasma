import QtQuick
import QtQuick.Shapes

// The light an app casts on the band's glass: a soft, flattened pool of its colour around its icon,
// stronger for the focused app. Static: it only changes when the band opens, closes or the focus moves.
Shape {
    id: glow
    property color tint: "white"
    property real strength: 0.2
    property real flat: 0.62                // height / width of the pool
    width: 96
    height: width
    transform: Scale { origin.x: glow.width / 2; origin.y: glow.height / 2; yScale: glow.flat }
    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillGradient: RadialGradient {
            centerX: glow.width / 2; centerY: glow.height / 2; centerRadius: glow.width / 2
            focalX: glow.width / 2; focalY: glow.height / 2
            GradientStop { position: 0; color: Qt.rgba(glow.tint.r, glow.tint.g, glow.tint.b, glow.strength) }
            GradientStop { position: 0.45; color: Qt.rgba(glow.tint.r, glow.tint.g, glow.tint.b, glow.strength * 0.4) }
            GradientStop { position: 1; color: "transparent" }
        }
        PathRectangle { x: 0; y: 0; width: glow.width; height: glow.height }
    }
}
