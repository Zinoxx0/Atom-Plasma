import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Atom
import Rice

// Atom's scene, under everything: the backdrop chosen on the Theme page (Atom Backdrop, the power page's too), pulled a
// little out of focus as the launcher opens (a slow zoom, picture styles only: KWin's live blur can't be scaled), a
// game's art (softened) while a game has the focus, the focused item's colour as a soft light round the atom, a
// gradient from the top edge under the top bar and a shade on the left under the caption; matte's grain over it all.
Item {
    id: scene
    required property var stage

    Backdrop {
        id: bd
        anchors.fill: parent
        window: scene.stage
        pal: scene.stage.rice      // (the real frost and wallpaper: the backdrop is the screen's)
        origin: scene.stage.rippleOrigin
        radius: !glass || scene.stage.bgO >= 0.999 ? -1 : reach * scene.stage.bgO
        opacity: !glass ? scene.stage.bgO : 1
        veil: glass ? Prefs.glassVeil : 0.34
        offsetY: scene.stage.topGap
        grained: false
        transform: Scale {
            origin.x: scene.stage.atomAt.x; origin.y: scene.stage.atomAt.y
            xScale: bd.glass ? 1 : 1 + 0.04 * scene.stage.pullT; yScale: xScale
        }
    }

    // a game's art while a game has the focus (cross-faded; softened like the scene)
    Item {
        id: art
        anchors.fill: parent
        readonly property string want: scene.stage.focusItem && scene.stage.focusItem.hero ? scene.stage.focusItem.hero : ""
        readonly property bool sharp: !!(scene.stage.focusItem && scene.stage.focusItem.sharp)     // a wallpaper previewed: as it is
        property int shownSlot: 0
        onWantChanged: { const next = 1 - shownSlot; (next ? b : a).source = want; shownSlot = next }
        opacity: scene.stage.bgO
        Image { id: a; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true; visible: opacity > 0.01
                opacity: art.shownSlot === 0 && source != "" && status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.ms(500); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
                layer.enabled: visible && !art.sharp; layer.effect: MultiEffect { blurEnabled: true; blur: 0.7; blurMax: 48; saturation: 0.1 } }
        Image { id: b; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true; visible: opacity > 0.01
                opacity: art.shownSlot === 1 && source != "" && status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.ms(500); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
                layer.enabled: visible && !art.sharp; layer.effect: MultiEffect { blurEnabled: true; blur: 0.7; blurMax: 48; saturation: 0.1 } }
        Rectangle { anchors.fill: parent; color: C.alpha(scene.stage.look.surfaceLowest, art.sharp ? 0.12 : 0.4); visible: a.visible || b.visible; opacity: Math.max(a.opacity, b.opacity) }
    }

    // the focus's colour, a soft light round the atom
    Shape {
        id: ambient
        readonly property real r: scene.stage.d(900)
        x: scene.stage.atomAt.x - r; y: scene.stage.atomAt.y - r
        width: 2 * r; height: 2 * r
        opacity: scene.stage.bgO * (scene.stage.look.light ? 0.45 : 1)
        property color c: scene.stage.focusTint
        Behavior on c { ColorAnimation { duration: Tokens.ms(600); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: ambient.r; centerY: ambient.r; centerRadius: ambient.r; focalX: ambient.r; focalY: ambient.r
                GradientStop { position: 0; color: C.alpha(ambient.c, 0.34) }
                GradientStop { position: 1; color: C.alpha(ambient.c, 0) }
            }
            PathRectangle { width: ambient.width; height: ambient.height }
        }
    }

    // a gradient from the top edge (the top bar's ground) and a shade on the left (the caption's)
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        height: scene.stage.d(250)
        opacity: scene.stage.topO * (scene.stage.finder ? 0 : 1)
        gradient: Gradient {
            GradientStop { position: 0; color: C.alpha(scene.stage.look.surfaceLowest, 0.78) }
            GradientStop { position: 0.45; color: C.alpha(scene.stage.look.surfaceLowest, 0.38) }
            GradientStop { position: 1; color: C.alpha(scene.stage.look.surfaceLowest, 0) }
        }
    }
    Rectangle {
        anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
        width: parent.width * 0.5
        opacity: scene.stage.bgO
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: C.alpha(scene.stage.look.surfaceLowest, 0.55) }
            GradientStop { position: 1; color: C.alpha(scene.stage.look.surfaceLowest, 0) }
        }
    }
    // matte's grain, last (it dithers the bands of a blurred picture; sampled sharp)
    Image {
        anchors.fill: parent
        visible: bd.grainy
        source: visible ? bd.grain : ""
        fillMode: Image.Tile
        smooth: false
        opacity: bd.grainAlpha * scene.stage.bgO
    }
}
