import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import Rice

// The atom's core: a glass orb that shows what has the focus (its icon, or a game's art), tinted by its colour and lit
// from below, with a crisp light along its upper rim and a sheen; round it a soft glow and a fine rim in the focus's
// colour, and three short arcs in it that turn a step whenever the focus changes. (Its tick bezel went in the lab's
// round 6: small clutter.)
Item {
    id: core
    required property var view
    property var item: null                 // { icon, art }
    property color tint: view.rice.primary
    readonly property real dia: view.d(300) * view.k
    readonly property var rice: view.rice
    x: view.cx - dia / 2; y: view.cy - dia / 2
    width: dia; height: dia
    property int turns: 0
    onItemChanged: { turns++; pop.restart() }
    property real popT: 1
    NumberAnimation { id: pop; target: core; property: "popT"; from: 0; to: 1; duration: Tokens.ms(520); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn }

    Behavior on tint { ColorAnimation { duration: Tokens.ms(500); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }

    // the focus's colour as a soft glow just round the orb (the lab's round 5: the colour stays with the core, the atom
    // itself isn't lit), and a fine rim of it
    Shape {
        id: glow
        readonly property real reach: core.dia / 2 + core.view.d(40) * core.view.k
        anchors.centerIn: parent
        width: 2 * reach; height: width
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: glow.reach; centerY: glow.reach; centerRadius: glow.reach; focalX: glow.reach; focalY: glow.reach
                GradientStop { position: 0; color: C.alpha(core.tint, 0.26) }
                GradientStop { position: core.dia / 2 / glow.reach; color: C.alpha(core.tint, 0.26) }
                GradientStop { position: 1; color: C.alpha(core.tint, 0) }
            }
            PathAngleArc { centerX: glow.reach; centerY: glow.reach; radiusX: glow.reach; radiusY: glow.reach; startAngle: 0; sweepAngle: 360 }
        }
    }
    // three short arcs in the focus's colour, turning a step on every change
    Shape {
        id: arcs
        readonly property real r: core.dia / 2 + core.view.d(9) * core.view.k
        anchors.centerIn: parent
        width: 2 * r + 20; height: width
        rotation: 40 * core.turns
        Behavior on rotation { NumberAnimation { duration: Tokens.ms(1100); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"; strokeColor: core.tint; strokeWidth: 2.2; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: arcs.width / 2; centerY: arcs.height / 2; radiusX: arcs.r; radiusY: arcs.r; startAngle: -90; sweepAngle: 26 }
        }
        ShapePath {
            fillColor: "transparent"; strokeColor: C.mix(core.tint, core.rice.fg, 0.5); strokeWidth: 2.2; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: arcs.width / 2; centerY: arcs.height / 2; radiusX: arcs.r; radiusY: arcs.r; startAngle: 30; sweepAngle: 12 }
        }
        ShapePath {
            fillColor: "transparent"; strokeColor: core.tint; strokeWidth: 2.2; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: arcs.width / 2; centerY: arcs.height / 2; radiusX: arcs.r; radiusY: arcs.r; startAngle: 150; sweepAngle: 12 }
        }
    }

    // the orb
    Item {
        id: orb
        anchors.fill: parent
        Rectangle {         // the glass: the scene's deepest colour, tinted
            anchors.fill: parent; radius: width / 2
            color: C.mix(core.rice.surfaceLowest, core.tint, 0.12)
            opacity: 0.84
            border.width: 1; border.color: C.alpha(core.rice.light ? "#000000" : "#ffffff", 0.13)
        }
        Rectangle {         // the rim, in the focus's colour
            anchors.fill: parent; anchors.margins: -1; radius: width / 2
            color: "transparent"; border.width: 1; border.color: C.alpha(core.tint, 0.45)
        }
        Shape {             // light from below, in the focus's colour
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: orb.width / 2; centerY: orb.height * 1.1; centerRadius: orb.width * 0.62
                    focalX: centerX; focalY: centerY
                    GradientStop { position: 0; color: C.alpha(core.tint, 0.7) }
                    GradientStop { position: 1; color: C.alpha(core.tint, 0) }
                }
                PathAngleArc { centerX: orb.width / 2; centerY: orb.height / 2; radiusX: orb.width / 2 - 1; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
            }
        }
        // what has the focus: a game's art fills the orb, an app's icon sits in it
        Kirigami.ShadowedImage {
            anchors.fill: parent; anchors.margins: 1
            visible: !!(core.item && core.item.art)
            radius: width / 2
            source: visible ? core.item.art : ""
            fillMode: Image.PreserveAspectCrop
            color: "transparent"
            opacity: core.popT; scale: M.lerp(0.86, 1, core.popT)
        }
        Text {              // a gauge's value, big
            anchors.centerIn: parent
            visible: !!(core.item && core.item.mark)
            text: core.item && core.item.mark ? core.item.name : ""
            color: core.rice.fg
            font.family: core.view.stage.wideFamily; font.pixelSize: parent.width * 0.2; font.variableAxes: core.view.stage.wide(118, 640)
        }
        Rectangle {         // a colour
            anchors.centerIn: parent
            visible: !!(core.item && core.item.sw)
            width: parent.width * 0.42; height: width; radius: width / 2
            color: core.item && core.item.sw ? core.item.sw : "transparent"
            border.width: 1.5; border.color: Qt.rgba(1, 1, 1, 0.25)
            opacity: core.popT; scale: M.lerp(0.86, 1, core.popT)
        }
        Text {              // a node's glyph (a category, an action, a setting)
            anchors.centerIn: parent
            visible: !!(core.item && core.item.glyph)
            text: core.item ? core.item.glyph || "" : ""
            color: core.rice.fg
            font.family: Tokens.font.icons; font.pixelSize: parent.width * 0.34
            opacity: core.popT; scale: M.lerp(0.86, 1, core.popT)
        }
        Kirigami.Icon {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -parent.height * 0.03
            visible: !!(core.item && !core.item.art && !core.item.glyph && !core.item.mark && !core.item.sw && !core.item.swc && !core.item.dot)
            width: parent.width * 0.44; height: width
            source: core.item ? core.item.icon : ""
            opacity: core.popT; scale: M.lerp(0.86, 1, core.popT)
        }
        Shape {             // the sheen, high on the left
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: orb.width * 0.42; centerY: orb.height * 0.13; centerRadius: orb.width * 0.32
                    focalX: centerX; focalY: centerY
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.2) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                }
                PathAngleArc { centerX: orb.width / 2; centerY: orb.height / 2; radiusX: orb.width / 2 - 1; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
            }
        }
        Shape {             // the rim's light, along the upper left
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                fillRule: ShapePath.OddEvenFill
                fillGradient: ConicalGradient {
                    centerX: orb.width / 2; centerY: orb.height / 2; angle: 128
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0) }
                    GradientStop { position: 0.13; color: Qt.rgba(1, 1, 1, 0.75) }
                    GradientStop { position: 0.27; color: Qt.rgba(1, 1, 1, 0) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                }
                PathAngleArc { centerX: orb.width / 2; centerY: orb.height / 2; radiusX: orb.width / 2 - 0.5; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
                PathAngleArc { centerX: orb.width / 2; centerY: orb.height / 2; radiusX: orb.width / 2 - 3; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
            }
        }
    }
}
