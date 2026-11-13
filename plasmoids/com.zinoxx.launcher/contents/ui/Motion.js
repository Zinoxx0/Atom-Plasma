.pragma library
// Atom Home's choreography helpers. A move is one clock (0 -> its duration, linear) and tracks on it:
// each track has a start, a duration and a curve, and gives its eased progress at any time (the launcher
// lab's Timeline, so the timings tried there carry over as they are). Curves are CSS cubic-beziers.

function bezier(x1, y1, x2, y2) {
    const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx
    const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by
    const sx = t => ((ax * t + bx) * t + cx) * t
    const sy = t => ((ay * t + by) * t + cy) * t
    const dx = t => (3 * ax * t + 2 * bx) * t + cx
    return function (x) {
        if (x <= 0) return 0
        if (x >= 1) return 1
        let t = x
        for (let i = 0; i < 8; i++) {
            const e = sx(t) - x, d = dx(t)
            if (Math.abs(e) < 1e-6) return sy(t)
            if (Math.abs(d) < 1e-6) break
            t -= e / d
        }
        let lo = 0, hi = 1
        t = x
        for (let i = 0; i < 30; i++) {
            const v = sx(t)
            if (Math.abs(v - x) < 1e-6) break
            if (v < x) lo = t; else hi = t
            t = (lo + hi) / 2
        }
        return sy(t)
    }
}

// the calm family (the lab's defaults; Tokens.calmIn/Out/Move carry the same points for QML animations)
const enter = bezier(0.16, 1, 0.3, 1)       // things arriving: a long soft landing
const exit = bezier(0.55, 0, 0.75, 0.2)     // things leaving
const move = bezier(0.65, 0, 0.35, 1)       // things going from one place to another

function clamp(v, lo, hi) { return Math.min(hi === undefined ? 1 : hi, Math.max(lo === undefined ? 0 : lo, v)) }
function lerp(a, b, t) { return a + (b - a) * t }
// a track's eased progress at time `now` (ms): 0 before `start`, 1 after `start + dur`
function track(now, start, dur, curve) { return curve(clamp((now - start) / Math.max(1, dur))) }
