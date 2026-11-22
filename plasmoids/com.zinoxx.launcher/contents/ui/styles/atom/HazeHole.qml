import QtQuick
import QtQuick.Shapes

// A gap in an orbit's haze (an Orbit's mask, inverted): a soft disc centred on cx, cy, solid out to `rad - soft` and
// gone at `rad + soft`. Every Node puts one round itself, and every ring one round the lens.
Shape {
    id: hole
    property real cx: 0
    property real cy: 0
    property real rad: 0
    property real soft: 4
    readonly property real outer: Math.max(1, rad + soft)
    x: cx - outer; y: cy - outer
    width: 2 * outer; height: 2 * outer
    visible: rad > 0
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        strokeWidth: -1
        fillGradient: RadialGradient {
            centerX: hole.outer; centerY: hole.outer; centerRadius: hole.outer; focalX: hole.outer; focalY: hole.outer
            GradientStop { position: 0; color: "black" }
            GradientStop { position: Math.max(0, (hole.rad - hole.soft) / hole.outer); color: "black" }
            GradientStop { position: 1; color: "transparent" }
        }
        PathAngleArc { centerX: hole.outer; centerY: hole.outer; radiusX: hole.outer; radiusY: hole.outer; startAngle: 0; sweepAngle: 360 }
    }
}
