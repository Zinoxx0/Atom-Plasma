import QtQuick
import QtQuick.Effects
import Atom
import Rice

// Atom's scene, under everything: the backdrop chosen on the Theme page (Atom Backdrop, the power page's too), pulled a
// little out of focus as the launcher opens (a slow zoom, picture styles only: KWin's live blur can't be scaled), a
// game's art (softened) while a game has the focus, a gradient from the top edge under the top bar and a shade on the
// left under the caption; matte's grain over it all. (No light round the whole atom in the focus's colour since the
// lab's round 5: the user found it too much while choosing; that colour lives in the core.)
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
        opacity: !glass ? (scene.stage.priming && scene.stage.phase === "closed" ? 0.0015 : scene.stage.bgO)
                        : (scene.stage.priming && scene.stage.phase === "closed" ? 0 : 1)
        veil: glass ? Prefs.glassVeil : 0.34
        offsetY: scene.stage.topGap
        grained: false
        transform: Scale {
            origin.x: scene.stage.atomAt.x; origin.y: scene.stage.atomAt.y
            xScale: bd.glass ? 1 : 1 + 0.04 * scene.stage.pullT; yScale: xScale
        }
    }

    // a game's art while a game has the focus, the Steam way (the user, 2026-11-23: Yakuza 0's was zoomed until its
    // characters were cut): the whole picture at its own proportions across the width, from the top, fading into the
    // scene at its bottom; in and out with a calm fade. Sharp on the Games page; elsewhere softened when the backdrop
    // is (matte, clear: the same softness everywhere), sharp with a sharp one (noise, none). A wallpaper previewed on
    // the Theme page fills the screen instead (`sharp`). Two slots: a new picture loads into the hidden one and fades
    // in once it's ready; a slot still fading out is never given a new picture (it'd pop): the newest waits for it.
    // Each slot's look (mask, blur) is a layer made once per picture, not every frame.
    Item {
        id: art
        anchors.fill: parent
        opacity: scene.stage.bgO
        readonly property string want: scene.stage.focusItem && scene.stage.focusItem.hero ? scene.stage.focusItem.hero : ""
        readonly property bool wall: !!(scene.stage.focusItem && scene.stage.focusItem.sharp)       // a wallpaper previewed: fills
        readonly property bool soft: !wall && scene.stage.page !== "games" && (bd.matte || bd.glass)
        property int shown: -1              // the slot in view (-1: none)
        property string waiting: ""         // a picture for a slot still fading out
        readonly property real dpr: scene.stage.devicePixelRatio || 1
        function slotItem(i) { return i === 0 ? s0 : s1 }
        function retarget() {
            const w = want
            if (!w) { shown = -1; waiting = ""; return }
            if (shown >= 0 && String(slotItem(shown).source) === w) { waiting = ""; return }
            const k = shown === 0 ? 1 : 0, other = slotItem(k)
            if (String(other.source) === w) { shown = k; waiting = ""; return }       // (back to the one fading out)
            if (other.level > 0.004 && shown >= 0) { waiting = w; return }      // it must go first (the shown one stays meanwhile)
            other.source = w; shown = k; waiting = ""
        }
        onWantChanged: retarget()
        function settled(i) {               // slot i has faded out: a waiting picture can go in it
            if (!waiting || slotItem(i).level > 0.004) return
            const w = waiting; waiting = ""
            if (w !== want) return
            slotItem(i).source = w; shown = i
        }
        component Slot: Image {
            id: im
            required property int slot
            property bool everReady: false
            onSourceChanged: everReady = false
            onStatusChanged: if (status === Image.Ready) everReady = true
            readonly property bool on: art.shown === slot && (status === Image.Ready || everReady)
            property real level: on ? 1 : 0
            Behavior on level { NumberAnimation { duration: Tokens.ms(460); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
            onLevelChanged: if (level <= 0.004) art.settled(slot)
            opacity: level
            visible: level > 0.004
            x: 0; y: 0
            width: parent.width
            // its own proportions across the width (a wallpaper: the whole screen, cropped as a wallpaper is)
            height: art.wall ? parent.height : implicitWidth > 0 ? Math.round(width * implicitHeight / implicitWidth) : 0
            fillMode: art.wall ? Image.PreserveAspectCrop : Image.Stretch
            asynchronous: true
            cache: true
            retainWhileLoading: true
            smooth: true
            sourceSize.width: art.soft ? Math.min(960, Math.round(parent.width * art.dpr)) : Math.round(parent.width * art.dpr)
            layer.enabled: source != "" && !art.wall
            layer.effect: art.soft ? softEffect : fadeEffect
        }
        Component {
            id: fadeEffect
            ShaderEffect { fragmentShader: "artfade.frag.qsb" }
        }
        Component {
            id: softEffect
            MultiEffect {
                maskEnabled: true
                maskSource: fadeMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
                blurEnabled: true
                blur: 0.7; blurMax: 48
                saturation: 0.1
            }
        }
        Slot { id: s0; slot: 0 }
        Slot { id: s1; slot: 1 }
        // where softened art fades into the scene: solid down to 55% of its height, gone at its bottom
        Rectangle {
            id: fadeMask
            width: 8; height: 256          // (stretched over each picture: only its rows matter)
            visible: false; layer.enabled: art.soft && (s0.visible || s1.visible)
            gradient: Gradient {
                GradientStop { position: 0; color: "white" }
                GradientStop { position: 0.55; color: "white" }
                GradientStop { position: 1; color: "transparent" }
            }
        }
        readonly property real level: Math.max(s0.level, s1.level)
        // the veil that keeps text readable over it (lighter over a sharp game's art: it's meant to be seen;
        // on a light theme a white veil washes the art and hides white logos, so sharp art stays unwashed and
        // softened art gets only a gentle lift)
        Rectangle {
            anchors.fill: parent
            readonly property real alpha: art.wall ? 0.12
                : scene.stage.look.light ? (art.soft ? 0.14 : 0)
                : (art.soft ? 0.4 : 0.24)
            color: C.alpha(scene.stage.look.surfaceLowest, alpha)
            opacity: art.level
            visible: opacity > 0.004 && alpha > 0
        }
    }

    // a gradient from the top edge (the top bar's ground) and a shade on the left (the caption's)
    // (on a light theme with game art, the flat veil above is off so the hero stays vivid; keep the top band strong
    // enough for the top bar and date, and ease the left shade slightly so the art breathes)
    readonly property real lightGame: scene.stage.look.light && !art.wall ? art.level : 0
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        height: scene.stage.d(250)
        opacity: scene.stage.topO * (scene.stage.finder ? 0 : 1)
        gradient: Gradient {
            GradientStop { position: 0; color: C.alpha(scene.stage.look.surfaceLowest, M.lerp(0.78, 0.84, scene.lightGame)) }
            GradientStop { position: 0.45; color: C.alpha(scene.stage.look.surfaceLowest, M.lerp(0.38, 0.48, scene.lightGame)) }
            GradientStop { position: 1; color: C.alpha(scene.stage.look.surfaceLowest, 0) }
        }
    }
    Rectangle {
        anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
        width: parent.width * 0.5
        opacity: scene.stage.bgO
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: C.alpha(scene.stage.look.surfaceLowest, M.lerp(0.55, 0.46, scene.lightGame)) }
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
        opacity: bd.grainAlpha * (scene.stage.priming && scene.stage.phase === "closed" ? 0.0015 : scene.stage.bgO)
    }
}
