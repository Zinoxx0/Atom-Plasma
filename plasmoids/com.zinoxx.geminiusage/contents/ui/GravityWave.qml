import QtQuick

// Soft quadrupole gravitational wave spacetime distortion behind the Gemini star.
// Diffused luminous warped crests (m=2 gravitational wave strain), zero hard sonar rings.
// Runs at ~30 fps only while ripples are active or fading out; 0% CPU/GPU when idle or covered.
Canvas {
    id: gw
    antialiasing: true
    renderStrategy: Canvas.Cooperative

    property bool active: false
    property bool ripplesEnabled: true
    property bool animate: true
    property bool hot: false
    property string starStyle: "iridescent"

    readonly property bool wantWave: active && ripplesEnabled && animate && visible
    property real energy: 0
    property real phase: 1.4

    Timer {
        id: stepper
        interval: 33
        repeat: true
        running: gw.wantWave || gw.energy > 0.008
        onTriggered: {
            const target = gw.wantWave ? 1.0 : 0.0
            gw.energy += (target - gw.energy) * 0.12
            if (!gw.wantWave && gw.energy <= 0.008) gw.energy = 0
            gw.phase += 0.033
            gw.requestPaint()
        }
    }

    onWantWaveChanged: requestPaint()
    onHotChanged: requestPaint()
    onStarStyleChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        const w = width, h = height
        ctx.clearRect(0, 0, w, h)
        const cx = w / 2, cy = h / 2
        const maxR = Math.min(w, h) * 0.45
        if (maxR <= 2) return

        // Serene ambient aura around the star even at rest
        const aura = ctx.createRadialGradient(cx, cy, 1, cx, cy, maxR * 0.86)
        if (hot) {
            aura.addColorStop(0, "rgba(247, 118, 142, 0.28)")
            aura.addColorStop(0.55, "rgba(224, 175, 104, 0.09)")
        } else if (starStyle === "google4") {
            aura.addColorStop(0, "rgba(66, 133, 244, 0.25)")
            aura.addColorStop(0.5, "rgba(52, 168, 83, 0.09)")
        } else {
            aura.addColorStop(0, "rgba(155, 114, 203, 0.26)")
            aura.addColorStop(0.5, "rgba(66, 133, 244, 0.10)")
        }
        aura.addColorStop(1, "rgba(0, 0, 0, 0)")
        ctx.fillStyle = aura
        ctx.fillRect(0, 0, w, h)

        if (energy <= 0.01) return

        const layers = 4
        const palette = hot
            ? ["rgba(247,118,142,", "rgba(255,158,100,"]
            : starStyle === "google4"
                ? ["rgba(66,133,244,", "rgba(52,168,83,", "rgba(251,188,4,", "rgba(234,67,53,"]
                : ["rgba(78,205,196,", "rgba(66,133,244,", "rgba(155,114,203,", "rgba(217,101,112,"]

        ctx.save()
        ctx.globalCompositeOperation = "lighter"
        for (let i = 0; i < layers; i++) {
            const p = (phase * 0.30 + i / layers) % 1.0
            const rBase = maxR * (0.24 + p * 0.72)
            const env = Math.sin(p * Math.PI)
            const alpha = env * env * 0.54 * energy
            if (alpha < 0.005) continue

            const swirl = phase * 1.15 - p * 2.2
            const strain = 0.18 + 0.09 * Math.sin(p * Math.PI)
            const colA = palette[i % palette.length]
            const colB = palette[(i + 1) % palette.length]

            const grad = ctx.createLinearGradient(cx - rBase, cy - rBase, cx + rBase, cy + rBase)
            grad.addColorStop(0, colA + Math.min(1, alpha * 0.95).toFixed(3) + ")")
            grad.addColorStop(0.5, colB + Math.min(1, alpha * 0.62).toFixed(3) + ")")
            grad.addColorStop(1, colA + Math.min(1, alpha * 0.95).toFixed(3) + ")")

            const passes = [
                { lw: Math.max(1.8, maxR * 0.24), mul: 0.52 },
                { lw: Math.max(1.0, maxR * 0.10), mul: 0.88 },
            ]
            for (let k = 0; k < passes.length; k++) {
                ctx.beginPath()
                const steps = 48
                for (let s = 0; s <= steps; s++) {
                    const th = (s / steps) * Math.PI * 2
                    const warp = 1 + strain * Math.cos(2 * th - swirl) + 0.04 * Math.sin(4 * th + swirl * 0.7)
                    const r = rBase * warp
                    const x = cx + Math.cos(th) * r
                    const y = cy + Math.sin(th) * r
                    if (s === 0) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                }
                ctx.closePath()
                ctx.strokeStyle = grad
                ctx.globalAlpha = passes[k].mul
                ctx.lineWidth = passes[k].lw
                ctx.stroke()
            }
        }
        ctx.restore()
    }
}
