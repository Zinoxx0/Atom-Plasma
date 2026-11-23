import QtQuick

// A value that follows its `to` on a critically damped spring: no overshoot, and a new `to` mid-way keeps the speed it
// has (a Behavior's NumberAnimation restarts its curve on every change: retargeted every frame or on a key's repeat, it
// crept and stuttered; the Atom launcher's lens and rings, 2026-11-23). Stepped by a FrameAnimation only while it
// moves, with the exact step (any frame rate draws the same curve; a long frame counts as 20 ms, so a hitch pauses the
// motion instead of skipping it). The same spring as the Sheet's.
//   Spring { id: s; to: target; stiffness: 20 }    ...  x: s.value
// stiffness (rad/s): about 2.4 / stiffness seconds to get 90% of the way (20: ~0.12 s; 12: ~0.2 s). It follows the
// system animation speed (0 = no animations: it jumps). angle: degrees, and a new `to` is reached the short way round
// (`value` is unbounded). jump(v) puts it there at rest.
QtObject {
    id: s
    property real to: 0
    property real value: 0
    property real velocity: 0               // per second
    property real stiffness: 18
    property bool angle: false
    property real epsilon: 0.01             // close enough (in the value's units)
    property bool enabled: true             // false: value = to at once
    readonly property bool moving: frames.running
    property real goal: 0                   // where it's heading (= to, or the short way round for an angle)

    function wrap(d) { return ((d % 360) + 540) % 360 - 180 }
    function head() {
        goal = angle ? value + wrap(to - value) : to
        if (!enabled || Tokens.speed <= 0) { jump(to); return }
        if (Math.abs(value - goal) > epsilon || Math.abs(velocity) > epsilon * stiffness) frames.running = true
    }
    function jump(v) {
        frames.running = false
        velocity = 0
        goal = v === undefined ? to : v
        value = goal
    }
    onToChanged: head()
    onAngleChanged: head()
    onEnabledChanged: head()
    Component.onCompleted: { goal = to; value = to }

    readonly property FrameAnimation frames: FrameAnimation {
        running: false
        onTriggered: {
            const dt = frameTime > 0 ? Math.min(frameTime, 0.02) : 1 / 120
            const w = s.stiffness / Math.max(Tokens.speed, 0.01), e = Math.exp(-w * dt)
            const d = s.value - s.goal, c = s.velocity + w * d
            const x = s.goal + (d + c * dt) * e, v = (s.velocity - w * c * dt) * e
            if (Math.abs(x - s.goal) < s.epsilon && Math.abs(v) < s.epsilon * w) { s.jump(s.goal) }
            else { s.velocity = v; s.value = x }
        }
    }
}
