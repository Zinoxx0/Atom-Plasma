import QtQuick
import QtQuick.Shapes

// The launcher's mark: a glowing core with two tilted orbits crossing like an atom, a
// satellite on each. The far half of every orbit passes behind the core, so it has depth.
// Still at rest (nothing loops, so an idle desktop costs nothing). Hovering swings both
// satellites once round their orbits, behind the core and back out; while the launcher is
// open the orbits flatten into a single Saturn-like halo and the core flares, with one
// ripple; pressing squishes it.
Item {
    id: e

    property bool hovered: false
    property bool pressed: false
    property bool open: false
    property color c1: "#7aa2f7"        // core and first orbit
    property color c2: "#bb9af7"        // second orbit
    property color c3: "#f7768e"        // satellites
    property color c4: "#73daca"
    property color glow: c1

    implicitWidth: 34
    implicitHeight: 34

    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real ra: 12.5                         // orbit radii
    property real rb: open ? 3.6 : 4.6
    Behavior on rb { SpringAnimation { spring: 3; damping: 0.26; epsilon: 0.01 } }

    // tilts spring between the atom (crossed) and the halo (flat)
    property real tilt1: open ? -8 : 32
    property real tilt2: open ? -8 : -32
    Behavior on tilt1 { SpringAnimation { spring: 2.6; damping: 0.22; epsilon: 0.05 } }
    Behavior on tilt2 { SpringAnimation { spring: 2.6; damping: 0.22; epsilon: 0.05 } }

    // where the satellites are on their orbits, in degrees (90 = nearest to you)
    property real t1: 50
    property real t2: 230
    readonly property real restT1: 50
    readonly property real restT2: 230
    readonly property real openT1: 120
    readonly property real openT2: 300

    property real lit: open ? 1 : hovered ? 0.75 : 0.45   // glow strength
    Behavior on lit { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
    property real flare: open ? 1.22 : hovered ? 1.08 : 1
    Behavior on flare { SpringAnimation { spring: 3.4; damping: 0.2; epsilon: 0.002 } }

    // a satellite's position on its tilted ellipse, and whether it is on the near side
    function px(t, tilt) {
        const r = t * Math.PI / 180, q = tilt * Math.PI / 180
        return cx + ra * Math.cos(r) * Math.cos(q) - rb * Math.sin(r) * Math.sin(q)
    }
    function py(t, tilt) {
        const r = t * Math.PI / 180, q = tilt * Math.PI / 180
        return cy + ra * Math.cos(r) * Math.sin(q) + rb * Math.sin(r) * Math.cos(q)
    }
    function near(t) { return Math.sin(t * Math.PI / 180) >= 0 }

    // hover: one full swing round, satellites in opposite directions; open/close glide to place
    NumberAnimation { id: swing1; target: e; property: "t1"; duration: 1100; easing.type: Easing.OutCubic }
    NumberAnimation { id: swing2; target: e; property: "t2"; duration: 1100; easing.type: Easing.OutCubic }
    function glide(to1, to2, extra) {
        swing1.stop(); swing2.stop()
        t1 = ((t1 % 360) + 360) % 360
        t2 = ((t2 % 360) + 360) % 360
        let d1 = ((to1 - t1) % 360 + 360) % 360 + extra
        let d2 = ((to2 - t2) % 360 + 360) % 360 + extra
        swing1.to = t1 + d1
        swing2.to = t2 - (360 - d2 % 360) % 360 - extra
        swing1.duration = swing2.duration = extra ? 1150 : 700
        swing1.start(); swing2.start()
    }
    onHoveredChanged: if (hovered && !open) glide(restT1, restT2, 360)
    onOpenChanged: {
        if (open) { glide(openT1, openT2, 0); rippleAnim.restart() }
        else glide(restT1, restT2, 0)
    }

    // soft glow behind everything
    Shape {
        anchors.centerIn: parent
        width: 48
        height: 48
        opacity: e.lit
        z: -2
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: 24; centerY: 24; centerRadius: 24
                focalX: 24; focalY: 24
                GradientStop { position: 0; color: Qt.rgba(e.glow.r, e.glow.g, e.glow.b, 0.6) }
                GradientStop { position: 0.45; color: Qt.rgba(e.glow.r, e.glow.g, e.glow.b, 0.16) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathRectangle { x: 0; y: 0; width: 48; height: 48 }
        }
    }

    // one ripple when the launcher opens
    Rectangle {
        id: ripple
        anchors.centerIn: parent
        width: 22
        height: 22
        radius: width / 2
        color: "transparent"
        border.width: 1.5
        border.color: e.glow
        opacity: 0
        z: 5
    }
    ParallelAnimation {
        id: rippleAnim
        NumberAnimation { target: ripple; property: "scale"; from: 0.6; to: 2.0; duration: 560; easing.type: Easing.OutCubic }
        NumberAnimation { target: ripple; property: "opacity"; from: 0.85; to: 0; duration: 560; easing.type: Easing.OutQuad }
    }

    // the mark itself, squished as one when pressed
    Item {
        id: mark
        anchors.fill: parent
        scale: e.pressed ? 0.84 : 1
        Behavior on scale { SpringAnimation { spring: 5; damping: 0.25; epsilon: 0.002 } }

        // an orbit's far or near half: the far half sits behind the core, dimmer
        component Arc: Shape {
            id: arc
            property real tilt
            property color tint
            property bool far
            anchors.fill: parent
            rotation: tilt
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.rgba(arc.tint.r, arc.tint.g, arc.tint.b, arc.far ? 0.4 : 0.95)
                strokeWidth: arc.far ? 1.1 : 1.4
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: e.cx; centerY: e.cy
                    radiusX: e.ra; radiusY: e.rb
                    startAngle: arc.far ? 180 : 0
                    sweepAngle: 180
                }
            }
        }
        Arc { tilt: e.tilt1; tint: e.c1; far: true; z: 0 }
        Arc { tilt: e.tilt2; tint: e.c2; far: true; z: 0 }

        // the core: a little lit sphere
        Rectangle {
            anchors.centerIn: parent
            width: 9
            height: 9
            radius: 4.5
            z: 1
            scale: e.flare
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(e.c1, 1.45) }
                GradientStop { position: 0.55; color: e.c1 }
                GradientStop { position: 1; color: e.c2 }
            }
            Rectangle {      // specular dot
                x: 2; y: 1.6
                width: 2.6; height: 2.6; radius: 1.3
                color: Qt.rgba(1, 1, 1, 0.85)
            }
        }

        Arc { tilt: e.tilt1; tint: e.c1; far: false; z: 2 }
        Arc { tilt: e.tilt2; tint: e.c2; far: false; z: 2 }

        // satellites: in front of the core on the near side, behind it on the far side
        component Satellite: Rectangle {
            property real t
            property real tilt
            readonly property bool front: e.near(t)
            width: 4
            height: 4
            radius: 2
            x: e.px(t, tilt) - width / 2
            y: e.py(t, tilt) - height / 2
            z: front ? 3 : 0.5
            scale: front ? 1.15 : 0.8
            opacity: front ? 1 : 0.7
            border.width: 0.6
            border.color: Qt.rgba(1, 1, 1, 0.55)
        }
        Satellite { t: e.t1; tilt: e.tilt1; color: e.c3 }
        Satellite { t: e.t2; tilt: e.tilt2; color: e.c4 }
    }
}
