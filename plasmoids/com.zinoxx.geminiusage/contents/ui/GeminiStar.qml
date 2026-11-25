import QtQuick

// 4-point Gemini astroid star rendered cleanly at device pixel ratio.
// Supports "iridescent" (classic Gemini cyan -> blue -> violet -> coral) and "google4"
// (Google 4-colour star), shifting to warn/hot colours near limit.
Item {
    id: root
    property string starStyle: "iridescent"     // "iridescent" | "google4"
    property bool hot: false
    property bool floating: false
    property bool animate: true
    property color warnColor: "#ff9e64"
    property color hotColor: "#f7768e"

    property real bobY: 0
    property real bobScale: 1

    SequentialAnimation {
        running: root.floating && root.animate && root.visible
        loops: Animation.Infinite
        onRunningChanged: if (!running) { root.bobY = 0; root.bobScale = 1 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "bobY"; to: -1.4; duration: 1450; easing.type: Easing.InOutSine }
            NumberAnimation { target: root; property: "bobScale"; to: 1.06; duration: 1450; easing.type: Easing.InOutSine }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "bobY"; to: 0.5; duration: 1450; easing.type: Easing.InOutSine }
            NumberAnimation { target: root; property: "bobScale"; to: 1.0; duration: 1450; easing.type: Easing.InOutSine }
        }
    }

    Canvas {
        id: cv
        anchors.fill: parent
        antialiasing: true
        renderStrategy: Canvas.Cooperative
        transform: [
            Translate { y: root.bobY },
            Scale { origin.x: cv.width / 2; origin.y: cv.height / 2; xScale: root.bobScale; yScale: root.bobScale }
        ]

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: root
            function onStarStyleChanged() { cv.requestPaint() }
            function onHotChanged() { cv.requestPaint() }
            function onWarnColorChanged() { cv.requestPaint() }
            function onHotColorChanged() { cv.requestPaint() }
        }

        function traceStar(ctx, s) {
            const u = s / 24
            ctx.beginPath()
            ctx.moveTo(12 * u, 1.2 * u)
            ctx.bezierCurveTo(12.8 * u, 8.2 * u, 15.8 * u, 11.2 * u, 22.8 * u, 12 * u)
            ctx.bezierCurveTo(15.8 * u, 12.8 * u, 12.8 * u, 15.8 * u, 12 * u, 22.8 * u)
            ctx.bezierCurveTo(11.2 * u, 15.8 * u, 8.2 * u, 12.8 * u, 1.2 * u, 12 * u)
            ctx.bezierCurveTo(8.2 * u, 11.2 * u, 11.2 * u, 8.2 * u, 12 * u, 1.2 * u)
            ctx.closePath()
        }

        onPaint: {
            const ctx = getContext("2d")
            const w = width, h = height
            ctx.clearRect(0, 0, w, h)
            const s = Math.min(w, h)
            if (s <= 1) return

            ctx.save()
            ctx.translate((w - s) / 2, (h - s) / 2)
            traceStar(ctx, s)

            if (root.hot) {
                const g = ctx.createLinearGradient(0, 0, s, s)
                g.addColorStop(0, String(root.warnColor))
                g.addColorStop(1, String(root.hotColor))
                ctx.fillStyle = g
                ctx.fill()
            } else if (root.starStyle === "google4") {
                ctx.clip()
                ctx.fillStyle = "#4285f4"
                ctx.fillRect(0, 0, s, s)
                const blobs = [
                    [5 / 24, 5 / 24, "#ea4335"],
                    [5 / 24, 19 / 24, "#fbbc04"],
                    [19 / 24, 19 / 24, "#34a853"],
                    [19 / 24, 5 / 24, "#4285f4"],
                ]
                for (let i = 0; i < blobs.length; i++) {
                    const bx = blobs[i][0] * s, by = blobs[i][1] * s, br = s * 0.52
                    const rg = ctx.createRadialGradient(bx, by, 0, bx, by, br)
                    rg.addColorStop(0, blobs[i][2])
                    rg.addColorStop(0.65, blobs[i][2])
                    rg.addColorStop(1, "rgba(66,133,244,0)")
                    ctx.fillStyle = rg
                    ctx.beginPath()
                    ctx.arc(bx, by, br, 0, Math.PI * 2)
                    ctx.fill()
                }
                const core = ctx.createRadialGradient(s * 0.5, s * 0.5, 0, s * 0.5, s * 0.5, s * 0.24)
                core.addColorStop(0, "rgba(255,255,255,0.28)")
                core.addColorStop(1, "rgba(255,255,255,0)")
                ctx.fillStyle = core
                ctx.fillRect(0, 0, s, s)
            } else {
                const g = ctx.createLinearGradient(s * 0.08, s * 0.06, s * 0.92, s * 0.94)
                g.addColorStop(0.0, "#4ecdc4")
                g.addColorStop(0.30, "#4285f4")
                g.addColorStop(0.66, "#9b72cb")
                g.addColorStop(1.0, "#d96570")
                ctx.fillStyle = g
                ctx.fill()
            }
            ctx.restore()
        }
    }
}
