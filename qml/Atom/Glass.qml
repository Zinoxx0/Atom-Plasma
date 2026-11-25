import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Window

// The rice's one glass for every shell panel (the sheet, notification cards, the launcher's cards):
// obsidian over KWin's blur (BlurBehind on the window, set by whoever owns it), a breath of white light
// along the top, a hairline rim running rimA -> rimB like the bar's islands, and a soft neutral shadow.
// When `liquid` is true (with `pal` and `screenSize`), renders single-pass Apple Liquid Glass optics
// (Snell refraction, chromatic dispersion, curved Fresnel bevel) aligned to `screenPos` over KWin's blur.
// Size it like a Rectangle. Colours are plain values: Glass knows nothing of palettes unless `liquid` is set.
Item {
    id: g
    property real radius: 24
    property color fill: "#12131a"
    property real fillAlpha: 0.8
    property color rimA: "white"
    property color rimB: "white"
    property real rimAlpha: 0.5
    property real sheen: 0.06               // the white light at the top (0 = none)
    property real lift: 1                   // 0..1: how far it stands off what's below (shadow strength)
    property bool liquid: false
    property string glassStyle: ""          // "liquid" | "aurora" (empty: standard obsidian/frost glass)
    property var pal: null
    property size screenSize: Qt.size(0, 0)
    property point screenPos: Qt.point(0, 0)
    readonly property string activeStyle: glassStyle !== "" ? glassStyle : (liquid ? "liquid" : "")
    readonly property bool liquidActive: activeStyle !== "" && !!pal && screenSize.width > 1 && screenSize.height > 1
    readonly property real shaderMode: activeStyle === "aurora" ? 1 : 0

    RectangularShadow {
        anchors.fill: parent
        visible: g.lift > 0.01
        radius: g.radius
        blur: 34
        spread: -6
        offset.y: 10
        color: Qt.rgba(0, 0, 0, 0.42 * g.lift)
    }
    Rectangle {
        anchors.fill: parent
        visible: !g.liquidActive
        radius: g.radius
        color: Qt.rgba(g.fill.r, g.fill.g, g.fill.b, g.fillAlpha)
    }
    Rectangle {
        visible: !g.liquidActive && g.sheen > 0
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
        height: Math.min(parent.height * 0.4, 96)
        radius: Math.max(0, g.radius - 1)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, g.sheen) }
            GradientStop { position: 1; color: "transparent" }
        }
    }
    Shape {
        anchors.fill: parent
        visible: !g.liquidActive && g.width > 2 && g.height > 2
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeWidth: 1
            strokeColor: "white"
            strokeGradient: LinearGradient {
                x1: 0; y1: 0; x2: g.width; y2: g.height * 0.3
                GradientStop { position: 0; color: Qt.rgba(g.rimA.r, g.rimA.g, g.rimA.b, g.rimAlpha) }
                GradientStop { position: 1; color: Qt.rgba(g.rimB.r, g.rimB.g, g.rimB.b, g.rimAlpha) }
            }
            PathRectangle {
                x: 0.5; y: 0.5
                width: Math.max(0, g.width - 1); height: Math.max(0, g.height - 1)
                radius: Math.max(0, g.radius - 0.5)
            }
        }
    }

    // Apple Liquid Glass popup surface: instantiated ONLY when bar.style === "liquid"
    Loader {
        anchors.fill: parent
        active: g.liquidActive
        sourceComponent: Item {
            id: lg
            anchors.fill: parent
            readonly property real dpr: g.Window.window && g.Window.window.devicePixelRatio ? g.Window.window.devicePixelRatio : 1
            readonly property string wallSource: g.pal && g.pal.wallpaper ? "file://" + g.pal.wallpaper : ""
            readonly property string sharpSource: g.pal && g.pal.values && g.pal.values._wallFit ? "file://" + g.pal.values._wallFit : wallSource
            readonly property bool hasWallFit: !!(g.pal && g.pal.values && g.pal.values._wallFit)
            readonly property string frostSource: g.pal && g.pal.values && g.pal.values._glassFull ? "file://" + g.pal.values._glassFull : wallSource
            readonly property bool hasFrost: !!(g.pal && g.pal.values && g.pal.values._glassFull)

            function refreshTextures() {
                gSharpSrc.scheduleUpdate()
                gBlurSrc.scheduleUpdate()
            }
            Item {
                id: gSharpHolder
                width: Math.max(1, g.screenSize.width); height: Math.max(1, g.screenSize.height)
                visible: true
                Image {
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    source: lg.sharpSource
                    sourceSize: lg.hasWallFit ? Qt.size(0, 0) : Qt.size(Math.min(1600, Math.ceil(g.screenSize.width)), Math.min(900, Math.ceil(g.screenSize.height)))
                    onStatusChanged: if (status === Image.Ready) Qt.callLater(() => gSharpSrc.scheduleUpdate())
                }
            }
            Item {
                id: gBlurHolder
                width: Math.max(1, Math.round(g.screenSize.width / 4))
                height: Math.max(1, Math.round(g.screenSize.height / 4))
                visible: true
                Image {
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    source: lg.frostSource
                    sourceSize.width: lg.hasFrost ? 0 : 480
                    layer.enabled: !lg.hasFrost
                    layer.effect: MultiEffect { autoPaddingEnabled: false; blurEnabled: true; blur: 1; blurMax: 64; saturation: 0.3 }
                    onStatusChanged: if (status === Image.Ready) Qt.callLater(() => gBlurSrc.scheduleUpdate())
                }
            }
            ShaderEffectSource {
                id: gSharpSrc
                sourceItem: gSharpHolder
                hideSource: true
                live: false
                smooth: true
                textureSize: Qt.size(Math.min(1600, Math.max(1, Math.round(g.screenSize.width))),
                                     Math.min(900, Math.max(1, Math.round(g.screenSize.height))))
            }
            ShaderEffectSource {
                id: gBlurSrc
                sourceItem: gBlurHolder
                hideSource: true
                live: false
                smooth: true
            }
            onSharpSourceChanged: Qt.callLater(() => gSharpSrc.scheduleUpdate())
            onFrostSourceChanged: Qt.callLater(() => gBlurSrc.scheduleUpdate())
            Connections {
                target: g
                function onScreenSizeChanged() { Qt.callLater(lg.refreshTextures) }
            }
            Component.onCompleted: Qt.callLater(refreshTextures)

            ShaderEffect {
                anchors.fill: parent
                visible: g.width > 2 && g.height > 2
                fragmentShader: Qt.resolvedUrl("liquid_glass.frag.qsb")
                readonly property size boxSize: Qt.size(width, height)
                readonly property point rectPos: g.screenPos
                readonly property size screenSize: g.screenSize
                readonly property real bevel: Math.min(18, Math.max(10, Math.min(width, height) * 0.14))
                readonly property real dpr: lg.dpr
                readonly property vector4d radii: Qt.vector4d(g.radius, g.radius, g.radius, g.radius)
                readonly property color tintColor: Qt.rgba(g.fill.r, g.fill.g, g.fill.b,
                    g.shaderMode > 0.5 ? 1.0 : (g.pal && g.pal.light ? 0.44 : 0.38))
                readonly property color rimA: g.rimA
                readonly property color rimB: g.rimB
                readonly property color rimC: g.pal ? g.pal.secondary : g.rimB
                readonly property real glassAlpha: g.shaderMode > 0.5 ? 0.90 : (g.pal && g.pal.light ? 0.88 : 0.85)
                readonly property real frostMix: g.pal && g.pal.light ? 0.60 : 0.56
                readonly property real isLight: g.pal && g.pal.light ? 1 : 0
                readonly property real isJewel: 0
                readonly property real flatBottom: 0
                readonly property real mode: g.shaderMode
                readonly property var sharpTex: gSharpSrc
                readonly property var blurTex: gBlurSrc
            }
        }
    }
}
