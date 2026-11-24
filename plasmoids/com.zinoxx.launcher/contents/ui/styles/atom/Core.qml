import QtQuick
import org.kde.kirigami as Kirigami
import Rice

// The atom's core: a glass orb that shows what has the focus (its icon, or a game's art), tinted by its colour and lit
// from below, with a crisp light along its upper rim and a sheen; round it a soft glow and a fine rim in the focus's
// colour, and three short arcs in it that turn a step whenever the focus changes. Drawn by two lightweight shaders
// (core_back.frag.qsb behind the icon/art, core_front.frag.qsb in front) — zero Shape CurveRenderers.
Item {
    id: core
    required property var view
    property var item: null                 // { icon, art }
    property color tint: view.rice.primary
    readonly property real dia: view.d(300) * view.k
    readonly property real dpr: view.stage && view.stage.devicePixelRatio ? view.stage.devicePixelRatio : 1
    readonly property var rice: view.rice
    x: view.cx - dia / 2; y: view.cy - dia / 2
    width: dia; height: dia
    property int turns: 0
    onItemChanged: { turns++; pop.restart() }
    property real popT: 1
    NumberAnimation { id: pop; target: core; property: "popT"; from: 0; to: 1; duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn }

    Behavior on tint { ColorAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }

    property real arcAngle: 40 * turns
    Behavior on arcAngle { NumberAnimation { duration: Tokens.ms(650); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }

    // outer focus glow, three rotating rounded-cap arcs, tinted glass orb, inner border, accent rim & underlight
    ShaderEffect {
        id: back
        readonly property real reach: core.dia / 2 + core.view.d(40) * core.view.k
        anchors.centerIn: parent
        width: 2 * reach; height: width
        fragmentShader: "core_back.frag.qsb"
        readonly property size boxSize: Qt.size(width, height)
        readonly property real orbR: core.dia / 2
        readonly property real arcR: core.dia / 2 + core.view.d(9) * core.view.k
        readonly property real arcRot: core.arcAngle * Math.PI / 180
        readonly property real dpr: core.dpr
        readonly property color tint: core.tint
        readonly property color arcMid: C.mix(core.tint, core.rice.fg, 0.5)
        readonly property color glassColor: C.alpha(C.mix(core.rice.surfaceLowest, core.tint, 0.12), 0.84)
        readonly property color innerBorder: C.alpha(core.rice.light ? "#000000" : "#ffffff", 0.13)
        readonly property color rimColor: C.alpha(core.tint, 0.45)
    }

    // the orb's focus content & foreground highlights
    Item {
        id: orb
        anchors.fill: parent
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
        // upper-left glass sheen + conical rim light in one pass
        ShaderEffect {
            anchors.fill: parent
            fragmentShader: "core_front.frag.qsb"
            readonly property real dia: core.dia
            readonly property real dpr: core.dpr
        }
    }
}
