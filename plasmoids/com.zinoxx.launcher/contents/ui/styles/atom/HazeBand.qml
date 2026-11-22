import QtQuick
import QtQuick.Shapes

// One band of an orbit's haze (Orbit): an annulus round the atom's centre, `w` wide, coloured by the angle from the lens
// and mirrored round it (c0 at the lens, c1 at a1 deg from it, c2 at a2, c3 on the far side). An Orbit draws it through
// a MultiEffect (blurred, the gaps masked out), so it stays hidden itself.
Shape {
    id: band
    property real cx: width / 2
    property real cy: height / 2
    property real r: 0
    property real w: 7
    property real lens: 180                 // the lens's angle (deg, clockwise from 3 o'clock)
    property color c0: "transparent"
    property color c1: "transparent"
    property color c2: "transparent"
    property color c3: "transparent"
    property real a1: 90
    property real a2: 135
    visible: false
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        strokeWidth: -1
        fillRule: ShapePath.OddEvenFill
        fillGradient: ConicalGradient {
            centerX: band.cx; centerY: band.cy
            angle: -band.lens               // (its angle runs counter-clockwise; the stops are mirrored round the lens)
            GradientStop { position: 0; color: band.c0 }
            GradientStop { position: band.a1 / 360; color: band.c1 }
            GradientStop { position: band.a2 / 360; color: band.c2 }
            GradientStop { position: 0.5; color: band.c3 }
            GradientStop { position: 1 - band.a2 / 360; color: band.c2 }
            GradientStop { position: 1 - band.a1 / 360; color: band.c1 }
            GradientStop { position: 1; color: band.c0 }
        }
        PathAngleArc { centerX: band.cx; centerY: band.cy; radiusX: band.r + band.w / 2; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
        PathAngleArc { centerX: band.cx; centerY: band.cy; radiusX: Math.max(0.5, band.r - band.w / 2); radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
    }
}
