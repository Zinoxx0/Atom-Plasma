import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

// The bar's silhouette and material: a band hanging from the top edge of the screen, corner to
// corner, with concave fillets where it meets the sides (so the screen looks rounded below it, as
// if the bezel grew) and a tab that drips from its lower edge under the hovered icon (the label).
// solid: just the bezel colour and a faint rim (the resting strip). Otherwise a smoked-glass drawer
// slides out from under the resting strip's solid bezel (`bezelH`, which shrinks away as it opens):
// the screen's pre-blurred wallpaper band (rice.py) under a dark veil, a colour wash, a faint dot
// grid, a sheen along its top edge, and a lit rim that runs along the lip and around the tab, so the
// tab reads as part of the same edge. `glint` (0 -> 1, once per opening) runs a light along the
// rim from `glintX` outward.
Item {
    id: n

    property real bandH: 6
    property real bezelH: 6                // the resting strip's height: stays solid bezel when open
    property real fillet: 14
    property real glint: 1                 // 1 = done (no light on the rim)
    property real glintX: width / 2
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
            GradientStop { position: 0; color: Qt.rgba(n.glow.r, n.glow.g, n.glow.b, 0.22) }
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
        Rectangle {     // smoked glass: darkest just under the bezel, clearing a little toward the lip
            id: veil
            anchors.fill: parent
            readonly property real under: n.bezelH / Math.max(1, height)
            readonly property real lip: n.bandH / Math.max(1, height)
            gradient: Gradient {
                GradientStop { position: 0; color: n.bezel }
                GradientStop { position: veil.under; color: Qt.rgba(n.bezel.r, n.bezel.g, n.bezel.b, 1 - 0.24 * n.glass) }
                GradientStop { position: veil.lip; color: Qt.rgba(n.bezel.r, n.bezel.g, n.bezel.b, 1 - 0.46 * n.glass) }
                GradientStop { position: 1; color: Qt.rgba(n.bezel.r, n.bezel.g, n.bezel.b, 1 - 0.4 * n.glass) }
            }
        }
        Image {         // the dot grid: texture so the glass reads as a material, not a flat fill
            y: n.bezelH
            width: n.width
            height: Math.max(0, n.height - n.bezelH)
            source: Qt.resolvedUrl("../images/dots.png")
            fillMode: Image.Tile
            opacity: 0.55 * n.glass
            visible: n.glass > 0
        }
        Rectangle {     // a breath of light at the top of the glass, like the bar's islands
            y: n.bezelH
            width: n.width
            height: Math.max(0, (n.bandH - n.bezelH) * 0.6)
            visible: n.glass > 0
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.05 * n.glass) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
        Rectangle {     // the solid bezel the drawer slides out from (the resting strip, unchanged)
            width: n.width
            height: n.bezelH
            color: n.bezel
        }
    }

    // the drawer's top edge catching the light where it comes out from under the bezel (gone with it)
    Rectangle {
        visible: !n.solid && n.glass > 0 && opacity > 0
        x: n.fillet
        y: n.bezelH
        width: n.width - 2 * n.fillet
        height: 1
        opacity: n.glass * Math.min(1, n.bezelH / 3)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.08; color: Qt.rgba(1, 1, 1, 0.09) }
            GradientStop { position: 0.92; color: Qt.rgba(1, 1, 1, 0.09) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // the resting rim: one crisp hairline along the lip
    Rectangle {
        visible: n.solid
        y: n.bandH - height
        width: n.width
        height: 1
        opacity: n.rimRest
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.12; color: n.rimA }
            GradientStop { position: 0.88; color: n.rimB }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // the opened rim: follows the lip and goes round the tab instead of cutting across its neck
    Shape {
        id: rim
        visible: !n.solid && n.height > 0
        anchors.fill: parent
        opacity: n.rimRest + (1 - n.rimRest) * n.glass
        preferredRendererType: Shape.CurveRenderer
        readonly property real w: 1 + 0.5 * n.glass
        readonly property real h: w / 2                       // the stroke sits just inside the edge
        readonly property bool tab: n.tabH > 2 * w
        // without a tab every point of it collapses onto the lip line
        readonly property real lipY: n.bandH - h
        readonly property real cf: tab ? n.tf : 0
        readonly property real cr: tab ? n.tr : 0
        readonly property real jy: tab ? n.bandH + cf : lipY  // where the joints meet the sides
        readonly property real by: tab ? n.bandH + n.tabH - h : lipY
        readonly property real lx: tab ? n.tL + h : n.tL
        readonly property real rx: tab ? n.tR - h : n.tR
        ShapePath {
            fillColor: "transparent"
            strokeWidth: rim.w
            strokeColor: "white"
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.RoundJoin
            strokeGradient: LinearGradient {
                x1: 0; y1: 0; x2: n.width; y2: 0
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.12; color: n.rimA }
                GradientStop { position: 0.88; color: n.rimB }
                GradientStop { position: 1.0; color: "transparent" }
            }
            startX: n.fillet; startY: rim.lipY
            PathLine { x: n.tL - rim.cf; y: rim.lipY }
            PathQuad { x: rim.lx; y: rim.jy; controlX: rim.lx; controlY: rim.lipY }
            PathLine { x: rim.lx; y: rim.by - rim.cr }
            PathQuad { x: n.tL + rim.cr; y: rim.by; controlX: rim.lx; controlY: rim.by }
            PathLine { x: n.tR - rim.cr; y: rim.by }
            PathQuad { x: rim.rx; y: rim.by - rim.cr; controlX: rim.rx; controlY: rim.by }
            PathLine { x: rim.rx; y: rim.jy }
            PathQuad { x: n.tR + rim.cf; y: rim.lipY; controlX: rim.rx; controlY: rim.lipY }
            PathLine { x: n.width - n.fillet; y: rim.lipY }
        }
    }

    // the opening light: two sparks that leave the point the pointer came in at and run out along the
    // rim, fading as they go
    Repeater {
        model: !n.solid && n.glint < 1 ? 2 : 0
        delegate: Rectangle {
            required property int index
            readonly property real run: Math.max(n.glintX - n.fillet, n.width - n.fillet - n.glintX)
            width: 160
            height: 2
            y: n.bandH - 1.5
            x: n.glintX + (index ? 1 : -1) * n.glint * run - width / 2
            opacity: (1 - n.glint) * Math.min(1, n.glint * 8)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.95) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }
}
