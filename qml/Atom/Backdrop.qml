import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Atom.Native
import "../Rice"
import "../Rice/Color.js" as C

// A full-screen surface's backdrop in the blur style chosen on the Theme page (Atom Prefs.blurStyle), so the
// launcher and the power page always wear the same one:
//   "matte"  noisy matte: the screen's wallpaper pre-blurred by the theme engine (palette _glassFull) under a
//            fine grain (it dithers the bands a blurred picture makes in 8 bits): a still, opaque, matte
//            finish; the windows behind it are hidden
//   "clear"  clear blur: KWin's live blur of whatever is behind, windows included, like glass
//   "none"   no blur: the screen's wallpaper itself, sharp and unfiltered, laid exactly where the desktop shows
//            it (`offsetY`: how far below the screen's top this window starts); the windows behind are hidden
// All under a veil of the palette's darkest surface (`veil`, 0: none), and matte's grain over it all. It fills a circle (a ripple: `origin`,
// `radius`) or, with radius < 0 (or a circle past every corner), the whole window. Fill the window with it
// (its blur region and its picture are in window coordinates).
Item {
    id: bd
    required property var window            // the Window, for KWin's blur
    required property var pal               // RicePalette: the frost (_glassFull), the wallpaper, surfaceLowest
    property string style: Prefs.blurStyle
    property point origin: Qt.point(width / 2, height / 2)
    property real radius: -1
    property real veil: 0.5
    property var also: []                   // more blur for the same window (its own glass): one blur region per window
    property real offsetY: 0                // the window starts this far below its screen's top (the wallpaper lines up)
    readonly property bool matte: style === "matte"
    readonly property bool glass: style === "clear"
    readonly property bool sharp: style === "none"
    readonly property bool pictured: matte || sharp     // a picture of the wallpaper (frosted or sharp) hides what's behind
    // style "veil": only the veil (over another surface that already wears the style: the power page over the
    // launcher); grainy: the matte grain on top all the same (under a veil it would fade)
    property bool grainy: matte
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

    // the picture: the frost (matte) or the wallpaper itself (no blur), as one full-window texture, laid on
    // the screen's own frame (so it lines up with the desktop)
    readonly property string wallSource: pal && pal.wallpaper ? "file://" + pal.wallpaper : ""
    Item {
        id: frost
        width: bd.width
        height: bd.height
        visible: false
        Image {         // no blur: the wallpaper as the desktop shows it (scaled and cropped to the screen)
            readonly property real dpr: bd.window && bd.window.devicePixelRatio ? bd.window.devicePixelRatio : 1
            y: -bd.offsetY
            width: parent.width
            height: parent.height + bd.offsetY
            visible: bd.sharp
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: bd.sharp ? bd.wallSource : ""
            sourceSize: Qt.size(Math.ceil(width * dpr), Math.ceil(height * dpr))
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
    // the grain, tiled over the whole window (a texture of its own: it goes over the veil)
    Item {
        id: grainArt
        width: bd.width
        height: bd.height
        visible: false
        Image { anchors.fill: parent; source: bd.grainy && bd.grained ? bd.grain : ""; fillMode: Image.Tile; smooth: false }
    }
    // (live: it redraws only when the grain changes, i.e. once)
    ShaderEffectSource { id: grainTex; width: bd.width; height: bd.height; visible: false; sourceItem: grainArt; hideSource: true; live: bd.grainy && bd.grained
                         smooth: false }     // (sampled sharp: filtered, the grain softened and read weaker)
    ShaderEffectSource { id: frostTex; width: bd.width; height: bd.height; visible: false; sourceItem: frost; hideSource: true; live: bd.pictured && bd.shows }

    Shape {
        anchors.fill: parent
        visible: bd.shows
        preferredRendererType: Shape.CurveRenderer
        ShapePath {         // the picture (matte, no blur), cut to the ripple
            strokeWidth: -1
            strokeColor: "transparent"
            fillColor: "transparent"
            fillItem: bd.pictured ? frostTex : null
            PathRectangle { x: bd.whole ? 0 : bd.origin.x - bd.r; y: bd.whole ? 0 : bd.origin.y - bd.r
                            width: bd.whole ? bd.width : 2 * bd.r; height: bd.whole ? bd.height : 2 * bd.r; radius: bd.whole ? 0 : bd.r }
        }
        ShapePath {         // the veil, on the same ripple
            strokeWidth: -1
            strokeColor: "transparent"
            fillColor: C.alpha(bd.pal ? bd.pal.surfaceLowest : "#000000", bd.veil)
            PathRectangle { x: bd.whole ? 0 : bd.origin.x - bd.r; y: bd.whole ? 0 : bd.origin.y - bd.r
                            width: bd.whole ? bd.width : 2 * bd.r; height: bd.whole ? bd.height : 2 * bd.r; radius: bd.whole ? 0 : bd.r }
        }
    }
    Shape {             // the grain, on top of everything (its strength: a layer's opacity)
        anchors.fill: parent
        visible: bd.shows && bd.grainy && bd.grained
        opacity: bd.grainAlpha
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillColor: "transparent"
            fillItem: bd.grainy && bd.grained ? grainTex : null
            PathRectangle { x: bd.whole ? 0 : bd.origin.x - bd.r; y: bd.whole ? 0 : bd.origin.y - bd.r
                            width: bd.whole ? bd.width : 2 * bd.r; height: bd.whole ? bd.height : 2 * bd.r; radius: bd.whole ? 0 : bd.r }
        }
    }
}
