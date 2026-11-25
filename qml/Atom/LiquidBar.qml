import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Rice

// Live Apple Liquid Glass layer for one taskbar panel (mounted onto panelLayout.parent at z: -1 by
// com.zinoxx.shell ONLY when Prefs.barStyle === "liquid"). Tracks every visible island dynamically as
// widgets resize or toggle (Glimpse pins, Clawd, Gemini/Claude Misc Modules) and renders single-pass
// Snell's-law refraction + RGB chromatic dispersion + curved Fresnel rim aligned pixel-for-pixel with
// the screen's wallpaper, fading smoothly out when a window docks to the bar.
Item {
    id: bar
    required property var panelLayout
    required property var screenObj
    required property RicePalette pal
    property string style: Prefs.barStyle       // "liquid" | "aurora"
    property bool docked: false
    property real islandRadius: Tokens.radius.md
    readonly property real shaderMode: style === "aurora" ? 1 : 0

    anchors.fill: parent
    z: -1
    opacity: docked ? 0 : 1
    visible: opacity > 0.002 && width > 2 && height > 2
    Behavior on opacity {
        NumberAnimation { duration: Tokens.ms(260); easing.type: Easing.OutCubic }
    }

    readonly property real dpr: Window.window && Window.window.devicePixelRatio ? Window.window.devicePixelRatio : 1
    readonly property real screenW: screenObj ? Math.max(1, screenObj.width) : Math.max(1, width)
    readonly property real screenH: screenObj ? Math.max(1, screenObj.height) : Math.max(1, height)

    readonly property string wallSource: pal && pal.wallpaper ? "file://" + pal.wallpaper : ""
    readonly property string sharpSource: pal && pal.values && pal.values._wallFit ? "file://" + pal.values._wallFit : wallSource
    readonly property bool hasWallFit: !!(pal && pal.values && pal.values._wallFit)
    readonly property string frostSource: {
        const v = pal ? pal.values || ({}) : ({})
        return v._glassFull ? "file://" + v._glassFull : wallSource
    }
    readonly property bool hasFrost: !!(pal && pal.values && pal.values._glassFull)

    // Shared static screen textures (live: false -> zero per-frame FBO cost; updated only on wallpaper/screen change)
    function refreshTextures() {
        sharpSrc.scheduleUpdate()
        blurSrc.scheduleUpdate()
    }
    Item {
        id: sharpHolder
        width: bar.screenW; height: bar.screenH
        visible: true
        Image {
            id: sharpImg
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            source: bar.sharpSource
            sourceSize: bar.hasWallFit ? Qt.size(0, 0) : Qt.size(Math.min(1600, Math.ceil(bar.screenW)), Math.min(900, Math.ceil(bar.screenH)))
            onStatusChanged: if (status === Image.Ready) Qt.callLater(() => sharpSrc.scheduleUpdate())
        }
    }
    Item {
        id: blurHolder
        width: Math.max(1, Math.round(bar.screenW / 4))
        height: Math.max(1, Math.round(bar.screenH / 4))
        visible: true
        Image {
            id: blurImg
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            source: bar.frostSource
            sourceSize.width: bar.hasFrost ? 0 : 480
            layer.enabled: !bar.hasFrost
            layer.effect: MultiEffect { autoPaddingEnabled: false; blurEnabled: true; blur: 1; blurMax: 64; saturation: 0.3 }
            onStatusChanged: if (status === Image.Ready) Qt.callLater(() => blurSrc.scheduleUpdate())
        }
    }
    ShaderEffectSource {
        id: sharpSrc
        sourceItem: sharpHolder
        hideSource: true
        live: false
        smooth: true
        textureSize: Qt.size(Math.min(1600, Math.max(1, Math.round(bar.screenW))),
                             Math.min(900, Math.max(1, Math.round(bar.screenH))))
    }
    ShaderEffectSource {
        id: blurSrc
        sourceItem: blurHolder
        hideSource: true
        live: false
        smooth: true
    }
    onScreenWChanged: Qt.callLater(refreshTextures)
    onScreenHChanged: Qt.callLater(refreshTextures)
    onSharpSourceChanged: Qt.callLater(() => sharpSrc.scheduleUpdate())
    onFrostSourceChanged: Qt.callLater(() => blurSrc.scheduleUpdate())

    // Dynamic island geometry tracking (zero idle polling: updates only on child add/remove/move/resize)
    property var trackedChildren: []
    property var islands: []
    property real panelWinX: 0
    property real panelWinY: Math.max(0, screenH - height)
    property real barOffX: 0
    property real barOffY: 0

    Timer {
        id: measureTimer
        interval: 16
        onTriggered: bar.measure()
    }
    function scheduleMeasure() { measureTimer.restart() }

    function refreshChildren() {
        const lay = panelLayout
        if (!lay) { trackedChildren = []; islands = []; return }
        const list = []
        const kids = lay.children
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i]
            if (c && c.applet && c.applet.plasmoid) list.push(c)
        }
        trackedChildren = list
        scheduleMeasure()
    }

    function measure() {
        const lay = panelLayout
        if (!lay || bar.width < 2 || bar.height < 2) { islands = []; return }
        const win = bar.Window.window
        const sx = screenObj ? screenObj.virtualX : 0
        const sy = screenObj ? screenObj.virtualY : 0
        const barOrigin = bar.mapToItem(null, 0, 0)
        barOffX = barOrigin.x
        barOffY = barOrigin.y
        panelWinX = win && win.x >= sx && win.x < sx + screenW ? (win.x - sx) : 0
        panelWinY = win && win.y > sy && win.y < sy + screenH ? (win.y - sy) : Math.max(0, screenH - (win ? win.height : bar.height))

        // Collect applet containers in exact visual left-to-right order
        const items = []
        const kids = lay.children
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i]
            const plugin = c && c.applet && c.applet.plasmoid ? String(c.applet.plasmoid.pluginName || "") : ""
            if (!plugin) continue
            const pt = c.mapToItem(bar, 0, 0)
            items.push({ item: c, plugin: plugin, x: pt.x, y: pt.y, w: c.width, h: c.height })
        }
        items.sort((a, b) => a.x - b.x)

        // Split into islands on panelspacer widgets, ignoring zero-size/hidden helpers
        const groups = []
        let cur = []
        for (let i = 0; i < items.length; i++) {
            const it = items[i]
            if (it.plugin === "org.kde.plasma.panelspacer") {
                if (cur.length) { groups.push(cur); cur = [] }
                continue
            }
            if (it.plugin === "com.zinoxx.shell" || it.plugin === "luisbocanegra.panel.colorizer") continue
            if (!it.item.visible || it.item.opacity < 0.01 || it.w < 2 || it.h < 2) continue
            cur.push(it)
        }
        if (cur.length) groups.push(cur)

        const out = []
        const n = groups.length
        for (let g = 0; g < n; g++) {
            const grp = groups[g]
            let x0 = Infinity, y0 = Infinity, x1 = -Infinity
            let jewel = false
            for (let j = 0; j < grp.length; j++) {
                const m = grp[j]
                if (m.x < x0) x0 = m.x
                if (m.y < y0) y0 = m.y
                if (m.x + m.w > x1) x1 = m.x + m.w
                if (m.plugin === "com.zinoxx.launcher") jewel = true
            }
            const leftCorner = g === 0 && x0 <= 10
            const rightCorner = g === n - 1 && x1 >= bar.width - 10
            if (leftCorner) x0 = 0
            if (rightCorner) x1 = bar.width
            // Clamp top cleanly within panel window and extend flush to the screen's bottom edge
            y0 = Math.max(0, Math.min(bar.height - 8, y0))
            const iw = Math.max(0, x1 - x0)
            const ih = Math.max(0, bar.height - y0)
            if (iw < 4 || ih < 4) continue
            const r = Math.min(bar.islandRadius, Math.floor(Math.min(iw, ih) / 2))
            const t = n > 1 ? g / (n - 1) : 0
            out.push({
                x: x0, y: y0, w: iw, h: ih,
                rTL: leftCorner ? 0 : r,
                rTR: rightCorner ? 0 : r,
                jewel: jewel,
                t: t,
            })
        }
        islands = out
    }

    Connections {
        target: bar.panelLayout
        function onChildrenChanged() { bar.refreshChildren() }
        function onWidthChanged() { bar.scheduleMeasure() }
        function onHeightChanged() { bar.scheduleMeasure() }
        function onXChanged() { bar.scheduleMeasure() }
        function onYChanged() { bar.scheduleMeasure() }
    }
    onWidthChanged: scheduleMeasure()
    onHeightChanged: scheduleMeasure()
    Component.onCompleted: {
        Qt.callLater(refreshTextures)
        Qt.callLater(refreshChildren)
    }

    // Per-child watchers (no polling timers)
    Repeater {
        model: bar.trackedChildren
        delegate: Item {
            required property var modelData
            visible: false
            Connections {
                target: modelData
                function onXChanged() { bar.scheduleMeasure() }
                function onYChanged() { bar.scheduleMeasure() }
                function onWidthChanged() { bar.scheduleMeasure() }
                function onHeightChanged() { bar.scheduleMeasure() }
                function onVisibleChanged() { bar.scheduleMeasure() }
                function onOpacityChanged() { bar.scheduleMeasure() }
            }
        }
    }

    // Refracted Liquid Glass islands
    Repeater {
        model: bar.islands
        delegate: ShaderEffect {
            required property var modelData
            x: modelData.x
            y: modelData.y
            width: modelData.w
            height: modelData.h
            fragmentShader: Qt.resolvedUrl("liquid_glass.frag.qsb")

            readonly property size boxSize: Qt.size(width, height)
            readonly property point rectPos: Qt.point(bar.panelWinX + bar.barOffX + x, bar.panelWinY + bar.barOffY + y)
            readonly property size screenSize: Qt.size(bar.screenW, bar.screenH)
            readonly property real bevel: Math.min(12, Math.max(7, height * 0.22))
            readonly property real dpr: bar.dpr
            readonly property vector4d radii: Qt.vector4d(modelData.rTL, modelData.rTR, 0, 0)
            readonly property color baseTint: bar.pal && bar.pal.light ? Tokens.neutral.light : (bar.pal ? bar.pal.surfaceLowest : "#0d0f18")
            readonly property color tintColor: Qt.rgba(baseTint.r, baseTint.g, baseTint.b,
                bar.shaderMode > 0.5 ? 1.0 : (bar.pal && bar.pal.light ? 0.34 : 0.26))
            readonly property color gradCol: bar.pal ? C.mix(bar.pal.primary, bar.pal.tertiary, modelData.t) : "#ffffff"
            readonly property color rimA: (modelData.jewel || bar.shaderMode > 0.5) && bar.pal ? bar.pal.primary : gradCol
            readonly property color rimB: (modelData.jewel || bar.shaderMode > 0.5) && bar.pal ? bar.pal.tertiary : gradCol
            readonly property color rimC: bar.pal ? bar.pal.secondary : gradCol
            readonly property real glassAlpha: modelData.jewel ? 0.90
                : bar.shaderMode > 0.5 ? (bar.pal && bar.pal.light ? 0.90 : 0.88)
                : (bar.pal && bar.pal.light ? 0.84 : 0.80)
            readonly property real frostMix: modelData.jewel ? 0.32
                : (bar.pal && bar.pal.light ? 0.40 : 0.34)
            readonly property real isLight: bar.pal && bar.pal.light ? 1 : 0
            readonly property real isJewel: modelData.jewel ? 1 : 0
            readonly property real flatBottom: 1
            readonly property real mode: bar.shaderMode
            readonly property var sharpTex: sharpSrc
            readonly property var blurTex: blurSrc
        }
    }
}
