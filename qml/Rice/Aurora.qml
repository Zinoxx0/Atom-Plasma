import QtQuick
import QtQuick.Shapes

// A faint glow of the screen's colours across the top of a popup: a pool of the primary on the
// left, the tertiary on the right, so every popup carries a breath of its wallpaper. `drift` (0 -> 1)
// slides the pools in from the sides as the popup opens; nothing moves after that.
Item {
    id: au
    property RicePalette ricePalette
    property real strength: 0.13
    property real drift: 1
    clip: true

    component Pool: Shape {
        id: pool
        property color tint
        property real cx: 0.5                   // centre, as a share of the width
        width: au.width * 0.9
        height: width
        x: au.width * cx - width / 2
        y: -height / 2
        transform: Scale { origin.x: pool.width / 2; origin.y: pool.height / 2; yScale: 0.32 }
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: pool.width / 2; centerY: pool.height / 2; centerRadius: pool.width / 2
                focalX: pool.width / 2; focalY: pool.height / 2
                GradientStop { position: 0; color: Qt.rgba(pool.tint.r, pool.tint.g, pool.tint.b, au.strength) }
                GradientStop { position: 0.5; color: Qt.rgba(pool.tint.r, pool.tint.g, pool.tint.b, au.strength * 0.35) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathRectangle { x: 0; y: 0; width: pool.width; height: pool.height }
        }
    }
    Pool { tint: au.ricePalette ? au.ricePalette.primary : "white"; cx: 0.18 - 0.08 * (1 - au.drift) }
    Pool { tint: au.ricePalette ? au.ricePalette.tertiary : "white"; cx: 0.86 + 0.08 * (1 - au.drift) }
}
