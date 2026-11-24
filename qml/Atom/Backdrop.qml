import QtQuick
import QtQuick.Effects
import Atom.Native
import Rice

// A full-screen surface's backdrop in the style chosen on the Theme page (Atom Prefs.backdropStyle), so the
// launcher and the power page always wear the same one:
//   "matte"  noisy matte: the screen's wallpaper pre-blurred by the theme engine (palette _glassFull) under a
//            fine grain (it dithers the bands a blurred picture makes in 8 bits): a still, opaque, matte
//            finish; the windows behind it are hidden
//   "clear"  clear blur: KWin's live blur of whatever is behind, windows included, like glass
//   "noise"  noisy only: the screen's wallpaper itself, sharp, under matte's grain (texture without the blur)
//   "none"   no blur: the screen's wallpaper itself, sharp and unfiltered, laid exactly where the desktop shows
//            it (`offsetY`: how far below the screen's top this window starts); the windows behind are hidden
// All under a veil of the palette's darkest surface (`veil`, 0: none), and matte's grain over it all. It fills a circle (a ripple: `origin`,
// `radius`) or, with radius < 0 (or a circle past every corner), the whole window. Fill the window with it
// (its blur region and its picture are in window coordinates).
Item {
    id: bd
    required property var window            // the Window, for KWin's blur
    required property var pal               // RicePalette: the frost (_glassFull), the wallpaper, surfaceLowest
    property string style: Prefs.backdropStyle
    property point origin: Qt.point(width / 2, height / 2)
    property real radius: -1
    property real veil: 0.5
    property var also: []                   // more blur for the same window (its own glass): one blur region per window
    property real offsetY: 0                // the window starts this far below its screen's top (the wallpaper lines up)
    readonly property bool matte: style === "matte"
    readonly property bool glass: style === "clear"
    readonly property bool sharp: style === "none" || style === "noise"     // the wallpaper itself, unblurred
    readonly property bool pictured: matte || sharp     // a picture of the wallpaper (frosted or sharp) hides what's behind
    // style "veil": only the veil (over another surface that already wears the style: the power page over the
    // launcher); grainy: the matte grain on top all the same (under a veil it would fade)
    property bool grainy: matte || style === "noise"
    readonly property url grain: Prefs.grain
    property real grainAlpha: Prefs.grainAlpha
    // its own grain on top (false: the surface draws it itself, over what it lays on the backdrop: the
    // launcher's scrims; it must stay the top layer, or the veil and the scrims fade it)
    property bool grained: true
    readonly property string frostSource: {
        const v = pal ? pal.values || ({}) : ({})
        return v._glassFull ? "file://" + v._glassFull : pal && pal.wallpaper ? "file://" + pal.wallpaper : ""
    }
    readonly property real reach: Math.max(Math.hypot(origin.x, origin.y), Math.hypot(width - origin.x, origin.y),
                                           Math.hypot(origin.x, height - origin.y), Math.hypot(width - origin.x, height - origin.y))
    readonly property bool whole: radius < 0 || radius >= reach
    readonly property real r: whole ? reach : Math.max(0, radius)
    readonly property bool shows: visible && opacity > 0.001 && (whole || r >= 1)

    BlurBehind {
        window: bd.window
        shapes: (!bd.glass || !bd.shows ? []
              : bd.whole ? [{ x: 0, y: 0, width: bd.width, height: bd.height, radius: 0 }]
              : [{ x: bd.origin.x - bd.r, y: bd.origin.y - bd.r, width: 2 * bd.r, height: 2 * bd.r, radius: bd.r }]).concat(bd.also || [])
    }

    // the picture: the frost (matte) or the wallpaper itself (no blur, noisy only), laid on the screen's own
    // frame so it lines up with the desktop. Whole-window backdrops (100% of matte/noise/none launcher opens and
    // resting power pages) draw directly in the scene graph with ZERO offscreen FBOs and ZERO CurveRenderer
    // shapes; only an active circular ripple (!bd.whole) loads the single-pass ripple shader.
    readonly property string wallSource: pal && pal.wallpaper ? "file://" + pal.wallpaper : ""
    readonly property string sharpSource: pal && pal.values && pal.values._wallFit ? "file://" + pal.values._wallFit : wallSource
    readonly property bool hasWallFit: !!(pal && pal.values && pal.values._wallFit)
    readonly property color veilColor: C.alpha(bd.pal ? bd.pal.surfaceLowest : "#000000", bd.veil)

    Item {
        id: picBox
        anchors.fill: parent
        clip: bd.offsetY > 0
        visible: bd.shows && bd.pictured
        Image {         // no blur, noisy only: screen-fitted JPEG (_wallFit) when cached, else full wallpaper
            readonly property real dpr: bd.window && bd.window.devicePixelRatio ? bd.window.devicePixelRatio : 1
            y: -bd.offsetY
            width: parent.width
            height: parent.height + bd.offsetY
            visible: bd.sharp
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: bd.sharp ? bd.sharpSource : ""
            sourceSize: bd.hasWallFit ? Qt.size(0, 0) : Qt.size(Math.ceil(width * dpr), Math.ceil(height * dpr))
        }
        Image {
            readonly property bool frosted: !!(bd.pal && bd.pal.values && bd.pal.values._glassFull)
            y: -bd.offsetY
            width: parent.width
            height: parent.height + bd.offsetY
            visible: bd.matte
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: bd.matte ? bd.frostSource : ""
            // no frost made yet (a fresh palette): the wallpaper itself, small and blurred here
            sourceSize.width: frosted ? 0 : 480
            layer.enabled: !frosted && bd.matte
            layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 64; saturation: 0.3 }
        }
    }
    // whole-window fast path: direct veil and grain, zero FBOs
    Rectangle {
        anchors.fill: parent
        visible: bd.shows && bd.whole && bd.veil > 0.001
        color: bd.veilColor
    }
    Image {
        anchors.fill: parent
        visible: bd.shows && bd.whole && bd.grainy && bd.grained
        source: visible ? bd.grain : ""
        fillMode: Image.Tile
        smooth: false
        opacity: bd.grainAlpha
    }

    // clear-blur / plain-veil ripple: simple clipped circle, zero FBOs and zero shaders
    Item {
        anchors.fill: parent
        clip: true
        visible: bd.shows && !bd.whole && !bd.pictured && !(bd.grainy && bd.grained) && bd.veil > 0.001
        Rectangle {
            x: bd.origin.x - bd.r; y: bd.origin.y - bd.r
            width: 2 * bd.r; height: 2 * bd.r; radius: bd.r
            color: bd.veilColor
        }
    }

    // pictured or grainy ripple (PowerWindow expanding/collapsing): instantiated ONLY during the ~500 ms ripple
    Loader {
        anchors.fill: parent
        active: bd.shows && !bd.whole && (bd.pictured || (bd.grainy && bd.grained))
        sourceComponent: Item {
            anchors.fill: parent
            ShaderEffectSource {
                id: rPicTex
                anchors.fill: parent
                visible: false
                sourceItem: bd.pictured ? picBox : null
                hideSource: bd.pictured
                live: bd.pictured
            }
            Image {
                id: rGrain
                visible: false
                smooth: false
                source: bd.grainy && bd.grained ? bd.grain : ""
            }
            ShaderEffectSource {
                id: rGrainTex
                width: Math.max(1, rGrain.implicitWidth)
                height: Math.max(1, rGrain.implicitHeight)
                visible: false
                sourceItem: rGrain
                hideSource: true
                live: bd.grainy && bd.grained
                smooth: false
            }
            ShaderEffect {
                anchors.fill: parent
                fragmentShader: Qt.resolvedUrl("ripple.frag.qsb")
                readonly property size boxSize: Qt.size(width, height)
                readonly property point origin: bd.origin
                readonly property real radius: bd.r
                readonly property real dpr: bd.window && bd.window.devicePixelRatio ? bd.window.devicePixelRatio : 1
                readonly property real hasPic: bd.pictured ? 1 : 0
                readonly property real hasGrain: bd.grainy && bd.grained ? 1 : 0
                readonly property real grainAlpha: bd.grainAlpha
                readonly property size grainSize: Qt.size(Math.max(1, rGrain.implicitWidth), Math.max(1, rGrain.implicitHeight))
                readonly property color veilColor: bd.veilColor
                readonly property var picTex: bd.pictured ? rPicTex : rGrainTex
                readonly property var grainTex: rGrainTex
            }
        }
    }
}
