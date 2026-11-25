import QtQuick
import QtQuick.Effects
import Atom.Native
import Rice

// A full-screen surface's backdrop in the material chosen on the Theme page (Atom Prefs.backdropStyle), so the
// launcher and the power page always wear the same one:
//   "solid"  Solid: clean architectural tonal gradient tuned to the screen's palette (hides windows behind)
//   "satin"  Satin: bead-blasted anodized solid gradient with fine tactile micro-grain
//   "aurora" Aurora: single-pass GPU velvet palette mesh (primary/secondary/tertiary), zero banding
//   "matte"  Sanded glass: pre-blurred wallpaper (_glassFull) under fine sandblasted grain
//   "clear"  Blur: KWin's live blur of whatever is behind, windows included
//   "liquid" Liquid glass: single-pass GPU Snell's-law refraction + chromatic dispersion + curved Fresnel bevel
//   "none"   Clear: the screen's wallpaper itself, sharp and unfiltered (`offsetY` lines it up with the desktop)
//   "noise"  (legacy) sharp wallpaper under matte's grain
// All under a veil of the palette's darkest surface (`veil`, 0: none), and grain over it all when grainy.
// It fills a circle (a ripple: `origin`, `radius`) or, with radius < 0 (or past every corner), the whole window.
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
    property point lensCenter: Qt.point(0, 0) // optional subtle optical focal lens center (e.g. Atom core)
    property real lensRadius: 0               // focal lens radius (<= 0: none)
    readonly property bool solid: style === "solid" || style === "satin"
    readonly property bool satin: style === "satin"
    readonly property bool aurora: style === "aurora"
    readonly property bool matte: style === "matte"
    readonly property bool glass: style === "clear"
    readonly property bool liquid: style === "liquid"
    readonly property bool shadered: liquid || aurora
    readonly property bool sharp: style === "none" || style === "noise"     // the wallpaper itself, unblurred
    readonly property bool pictured: matte || sharp || solid                // hides what's behind using picBox
    // style "veil": only the veil (over another surface that already wears the style: the power page over the
    // launcher); grainy: fine tactile grain on top (under a veil it would fade)
    property bool grainy: matte || satin || style === "noise"
    readonly property url grain: Prefs.grain
    property real grainAlpha: satin ? 0.075 : Prefs.grainAlpha
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
        // Solid & Satin: refined architectural palette gradient + subtle top-lit sheen (0 FBOs)
        Item {
            anchors.fill: parent
            visible: bd.solid
            readonly property color low: bd.pal ? bd.pal.surfaceLowest : "#0d0f18"
            readonly property color high: bd.pal ? bd.pal.surfaceHigh : "#1c1f2e"
            readonly property color pri: bd.pal ? bd.pal.primary : "#7aa2f7"
            readonly property color ter: bd.pal ? bd.pal.tertiary : pri
            readonly property bool light: !!(bd.pal && bd.pal.light)
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0; color: C.mix(parent.high, parent.pri, parent.light ? 0.08 : 0.10) }
                    GradientStop { position: 0.55; color: C.mix(parent.low, parent.high, parent.light ? 0.50 : 0.34) }
                    GradientStop { position: 1; color: C.mix(parent.low, parent.ter, parent.light ? 0.06 : 0.05) }
                }
            }
            Rectangle {     // subtle horizontal ambient tone shift
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: C.alpha(parent.pri, parent.light ? 0.06 : 0.08) }
                    GradientStop { position: 1; color: C.alpha(parent.ter, parent.light ? 0.05 : 0.06) }
                }
            }
            Rectangle {     // anodized top light catch (stronger on Satin for brushed tactile sheen)
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                height: parent.height * (bd.satin ? 0.48 : 0.36)
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, bd.satin ? (parent.light ? 0.24 : 0.08) : (parent.light ? 0.16 : 0.045)) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
        }
        Image {         // clear / legacy noise: screen-fitted JPEG (_wallFit) when cached, else full wallpaper
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
            layer.effect: MultiEffect { autoPaddingEnabled: false; blurEnabled: true; blur: 1; blurMax: 64; saturation: 0.3 }
        }
    }
    // whole-window fast path: direct veil and grain, zero FBOs (shadered styles handle veil inside shader)
    Rectangle {
        anchors.fill: parent
        visible: bd.shows && bd.whole && !bd.shadered && bd.veil > 0.001
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
        visible: bd.shows && !bd.whole && !bd.pictured && !bd.shadered && !(bd.grainy && bd.grained) && bd.veil > 0.001
        Rectangle {
            x: bd.origin.x - bd.r; y: bd.origin.y - bd.r
            width: 2 * bd.r; height: 2 * bd.r; radius: bd.r
            color: bd.veilColor
        }
    }

    // Aurora Ambient Silk Mesh backdrop: pure-math single-pass shader (0 FBOs, 0 VRAM textures, 0% idle GPU)
    Loader {
        id: auroraLoader
        anchors.fill: parent
        active: bd.shows && bd.aurora
        sourceComponent: ShaderEffect {
            anchors.fill: parent
            fragmentShader: Qt.resolvedUrl("aurora_backdrop.frag.qsb")
            readonly property size boxSize: Qt.size(width, height)
            readonly property real dpr: bd.window && bd.window.devicePixelRatio ? bd.window.devicePixelRatio : 1
            readonly property real isLight: bd.pal && bd.pal.light ? 1 : 0
            readonly property point origin: bd.origin
            readonly property real radius: bd.whole ? -1 : bd.r
            readonly property real veilAlpha: bd.veil
            readonly property color baseColor: bd.pal ? bd.pal.surfaceLowest : "#0d0f18"
            readonly property color colA: bd.pal ? bd.pal.primary : "#7aa2f7"
            readonly property color colB: bd.pal ? bd.pal.secondary : "#bb9af7"
            readonly property color colC: bd.pal ? bd.pal.tertiary : "#7dcfff"
        }
    }

    // Optical glass backdrop (Liquid glass): single-pass Snell refraction + chromatic dispersion
    // over shared static wallpaper textures (live: false -> 0% idle GPU). Instantiated ONLY when liquid.
    Loader {
        id: liquidLoader
        anchors.fill: parent
        active: bd.shows && bd.liquid
        sourceComponent: Item {
            id: lq
            anchors.fill: parent
            readonly property real dpr: bd.window && bd.window.devicePixelRatio ? bd.window.devicePixelRatio : 1
            readonly property real fullW: Math.max(1, bd.width)
            readonly property real fullH: Math.max(1, bd.height + bd.offsetY)

            function refreshTextures() {
                lqSharpSrc.scheduleUpdate()
                lqBlurSrc.scheduleUpdate()
            }

            Item {
                id: sharpHolder
                width: lq.fullW; height: lq.fullH
                visible: true
                Image {
                    id: lqSharp
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    source: bd.sharpSource
                    sourceSize: bd.hasWallFit ? Qt.size(0, 0) : Qt.size(Math.ceil(width * Math.min(lq.dpr, 1.25)), Math.ceil(height * Math.min(lq.dpr, 1.25)))
                    onStatusChanged: if (status === Image.Ready) Qt.callLater(() => lqSharpSrc.scheduleUpdate())
                }
            }
            Item {
                id: blurHolder
                width: Math.max(1, Math.round(lq.fullW / 4))
                height: Math.max(1, Math.round(lq.fullH / 4))
                visible: true
                Image {
                    id: lqBlur
                    readonly property bool frosted: !!(bd.pal && bd.pal.values && bd.pal.values._glassFull)
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    source: bd.frostSource
                    sourceSize.width: frosted ? 0 : 480
                    layer.enabled: !frosted
                    layer.effect: MultiEffect { autoPaddingEnabled: false; blurEnabled: true; blur: 1; blurMax: 64; saturation: 0.3 }
                    onStatusChanged: if (status === Image.Ready) Qt.callLater(() => lqBlurSrc.scheduleUpdate())
                }
            }
            ShaderEffectSource {
                id: lqSharpSrc
                sourceItem: sharpHolder
                hideSource: true
                live: false
                smooth: true
                textureSize: Qt.size(Math.max(1, Math.round(lq.fullW * Math.min(lq.dpr, 1.25))),
                                     Math.max(1, Math.round(lq.fullH * Math.min(lq.dpr, 1.25))))
            }
            ShaderEffectSource {
                id: lqBlurSrc
                sourceItem: blurHolder
                hideSource: true
                live: false
                smooth: true
            }
            onFullWChanged: Qt.callLater(refreshTextures)
            onFullHChanged: Qt.callLater(refreshTextures)
            Connections {
                target: bd
                function onSharpSourceChanged() { Qt.callLater(() => lqSharpSrc.scheduleUpdate()) }
                function onFrostSourceChanged() { Qt.callLater(() => lqBlurSrc.scheduleUpdate()) }
            }
            Component.onCompleted: Qt.callLater(refreshTextures)

            ShaderEffect {
                anchors.fill: parent
                fragmentShader: Qt.resolvedUrl("liquid_backdrop.frag.qsb")
                readonly property size boxSize: Qt.size(width, height)
                readonly property size screenSize: Qt.size(lq.fullW, lq.fullH)
                readonly property real offsetY: bd.offsetY
                readonly property real dpr: lq.dpr
                readonly property point origin: bd.origin
                readonly property real radius: bd.whole ? -1 : bd.r
                readonly property real isLight: bd.pal && bd.pal.light ? 1 : 0
                readonly property point lensCenter: bd.lensCenter
                readonly property real lensRadius: bd.lensRadius
                readonly property real veilAlpha: bd.veil
                readonly property color veilColor: bd.pal ? bd.pal.surfaceLowest : "#000000"
                readonly property color accentColor: bd.pal ? bd.pal.primary : "#ffffff"
                readonly property var sharpTex: lqSharpSrc
                readonly property var blurTex: lqBlurSrc
            }
        }
    }

    // pictured or grainy ripple (PowerWindow expanding/collapsing): instantiated ONLY during the ~500 ms ripple
    Loader {
        anchors.fill: parent
        active: bd.shows && !bd.whole && !bd.shadered && (bd.pictured || (bd.grainy && bd.grained))
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
