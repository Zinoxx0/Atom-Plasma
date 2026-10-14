import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

// The bar's silhouette and material: a band hanging from the top edge of the screen, corner to
// corner, with concave fillets where it meets the sides (so the screen looks rounded below it, as
// if the bezel grew) and a tab that drips from its lower edge under the hovered icon (the label).
// solid: just the bezel colour and a faint rim (the resting strip). Otherwise the lower lip turns to glass as
// `glass` goes to 1: the screen's pre-blurred wallpaper band (rice.py), a colour wash, a lit rim.
Item {
    id: n

    property real bandH: 6
    property real fillet: 14
    property real tabX: width / 2          // centre of the tab
    property real tabW: 0
    property real tabH: 0                  // 0 = no tab
    property real tabRadius: 10
    property bool solid: false
    property real glass: 0
    property url backdrop
    property size backdropSize
    property color bezel: "#060609"
    property color tintA: "transparent"    // colour wash, left / middle / right (alpha included)
    property color tintB: "transparent"
    property color tintC: "transparent"
    property color rimA: "white"
    property color rimB: "white"
    property color glow: "transparent"
    property real rimRest: 0.55            // the lit rim's strength while the band is closed

    // the tab's corners shrink with it, so it can grow out of a flat edge; it stays clear of the fillets
    readonly property real tf: Math.min(tabRadius, tabH / 2)
    readonly property real tr: Math.min(tabRadius, tabH / 2, tabW / 2)
    readonly property real tL: Math.max(fillet + tf, Math.min(width - fillet - tf - tabW, tabX - tabW / 2))
    readonly property real tR: tL + tabW

    // accent haze under the lip
    Rectangle {
        visible: !n.solid && n.glass > 0
        y: n.bandH
        width: n.width
        height: 18
        opacity: n.glass
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(n.glow.r, n.glow.g, n.glow.b, 0.30) }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    // the silhouette: drawn directly when solid, otherwise the mask of the glass body
    Item {
        id: mask
        anchors.fill: parent
        visible: n.solid
        layer.enabled: !n.solid
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: n.solid ? n.bezel : "white"
                strokeWidth: -1
                strokeColor: "transparent"
                startX: 0; startY: 0
                PathLine { x: n.width; y: 0 }
                PathLine { x: n.width; y: n.bandH + n.fillet }
                PathQuad { x: n.width - n.fillet; y: n.bandH; controlX: n.width; controlY: n.bandH }      // right screen fillet
                PathLine { x: n.tR + n.tf; y: n.bandH }
                PathQuad { x: n.tR; y: n.bandH + n.tf; controlX: n.tR; controlY: n.bandH }                // tab: joins the lip
                PathLine { x: n.tR; y: n.bandH + n.tabH - n.tr }
                PathQuad { x: n.tR - n.tr; y: n.bandH + n.tabH; controlX: n.tR; controlY: n.bandH + n.tabH }
                PathLine { x: n.tL + n.tr; y: n.bandH + n.tabH }
                PathQuad { x: n.tL; y: n.bandH + n.tabH - n.tr; controlX: n.tL; controlY: n.bandH + n.tabH }
                PathLine { x: n.tL; y: n.bandH + n.tf }
                PathQuad { x: n.tL - n.tf; y: n.bandH; controlX: n.tL; controlY: n.bandH }
                PathLine { x: n.fillet; y: n.bandH }
                PathQuad { x: 0; y: n.bandH + n.fillet; controlX: 0; controlY: n.bandH }                  // left screen fillet
                PathLine { x: 0; y: 0 }
            }
        }
    }

    Item {
        id: body
        anchors.fill: parent
        visible: !n.solid
        layer.enabled: !n.solid
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        Rectangle { anchors.fill: parent; color: n.bezel }
        Image {
            width: n.backdropSize.width
            height: n.backdropSize.height
            source: n.backdrop
            visible: status === Image.Ready && n.glass > 0
            smooth: true
            cache: true
        }
        Rectangle {     // colour wash
            anchors.fill: parent
            visible: n.glass > 0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: n.tintA }
                GradientStop { position: 0.55; color: n.tintB }
                GradientStop { position: 1.0; color: n.tintC }
            }
        }
        Rectangle {     // the bezel: solid at the top edge, clearing into glass toward the lip
            id: veil
            anchors.fill: parent
            readonly property real lip: n.bandH / Math.max(1, height)
            gradient: Gradient {
                GradientStop { position: 0; color: n.bezel }
                GradientStop { position: veil.lip * 0.3; color: n.bezel }
                GradientStop { position: veil.lip; color: Qt.rgba(n.bezel.r, n.bezel.g, n.bezel.b, 1 - 0.6 * n.glass) }
                GradientStop { position: 1; color: Qt.rgba(n.bezel.r, n.bezel.g, n.bezel.b, 1 - 0.42 * n.glass) }
            }
        }
        Rectangle {     // and along the tab's edge
            x: n.tL
            y: n.bandH + n.tabH - 1.5
            width: n.tabW
            height: 1.5
            visible: n.tabH > 4
            opacity: n.glass
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: n.rimA }
                GradientStop { position: 1.0; color: n.rimB }
            }
        }
    }

    // lit rim along the lip: a faint edge light at rest, full once the lip turns to glass
    Rectangle {
        y: n.bandH - height
        width: n.width
        height: 1 + 0.5 * n.glass
        opacity: n.rimRest + (1 - n.rimRest) * n.glass
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.12; color: n.rimA }
            GradientStop { position: 0.88; color: n.rimB }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
}
