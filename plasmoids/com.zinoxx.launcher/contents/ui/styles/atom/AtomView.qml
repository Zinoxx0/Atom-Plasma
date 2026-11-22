import QtQuick
import Atom
import Rice

// The atom: rings round a core, a lens on the focus, each ring's name above its slot.
// Focus: the keys and a pad turn the ring you're on (the focus stays at the slot, 9 o'clock) and step between rings.
// The pointer picks an item where it is (mode "pointer": the lens travels to it along the ring, nothing turns) by
// INTENT, like the simplified launcher (the Atom lab's round 5): only once it rests or slows under 0.35 px/ms over the
// last 150 ms, and only after a real move (not items sliding under a still pointer, nor the moment after a turn), so a
// sweep across the atom changes nothing on the way; items take the pointer 16 px round themselves. The wheel turns the
// ring UNDER the pointer, and the item that lands under it takes the focus. The first key after the pointer turns its
// pick to the slot. The lens's angle lights every ring from its side; a dot orbits the lens slowly, breathing.
// `dock` (Home; the lab's round 6): the rings lay their items out as a dock (Orbit), the active ring lifts out, and a
// fine beam runs from the core to the focus.
Item {
    id: av      // (not `view`: the rings have a `view` property, and `view: view` in a delegate binds it to itself)
    required property var stage
    property var shells: []                 // [{ name, items, radius, size, window }]
    property color tint: rice.primary       // the focus's colour (the page reads it off its icon)
    property bool dock: false
    // the dock (design px): the focus x1.6 (never past 116 px), a gaussian over its neighbours (sigma in items), the
    // other rings at rest x0.86, the active one 22 px further out
    readonly property real dockFocus: 1.6
    readonly property real dockSigma: 1.3
    readonly property real dockMax: 116
    readonly property real dockRest: 0.86
    readonly property real dockLift: 22
    readonly property var rice: stage.look
    readonly property real k: stage.atomK
    function d(px) { return stage.d(px) }
    readonly property real cx: stage.atomAt.x
    readonly property real cy: stage.atomAt.y
    anchors.fill: parent

    property int at: 0
    property string mode: "slot"
    readonly property Item ring: (rep.count, rep.itemAt(at))
    readonly property var focusItem: ring ? ring.focusItem : null
    signal launched(var item)
    signal options(var item, Item delegate)

    // the lens: an angle (deg, clockwise from 3 o'clock) and a radius, so it glides along the rings
    readonly property real lensTarget: {
        if (!ring) return 180
        if (ring.placed) return ring.angleOf(ring.focusIndex)        // a placed ring: the lens goes to the item
        if (mode !== "pointer" || ring.picked < 0) return 180
        const p = ring.centreOf(ring.picked)
        return Math.atan2(p.y - cy, p.x - cx) * 180 / Math.PI
    }
    property real lensAngle: 180
    onLensTargetChanged: lensAngle = lensTarget + 360 * Math.round((lensAngle - lensTarget) / 360)    // the short way round
    Behavior on lensAngle { NumberAnimation { duration: Tokens.ms(520); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
    readonly property real lensR: ring ? ring.r : 0
    property real lensRA: lensR
    Behavior on lensRA { NumberAnimation { duration: Tokens.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
    onLensRChanged: lensRA = lensR
    // where the lens is, for the rings' haze (its gap)
    readonly property real lensX: cx + lensRA * Math.cos(lensAngle * Math.PI / 180)
    readonly property real lensY: cy + lensRA * Math.sin(lensAngle * Math.PI / 180)
    readonly property real lensHole: lens.opacity > 0.01 ? lens.dia / 2 + d(7) * k : 0

    // the pointer: only real moves count, never while a ring turns; a pick waits for the pointer's intent
    property double lastMove: 0
    property double quietUntil: 0
    property var trail: []                  // its recent places: [{ x, y, t }]
    property var aim: null                  // { ri, i }: the item under it, waiting to be meant
    HoverHandler {
        onPointChanged: {
            const now = Date.now(), p = point.position
            av.lastMove = now
            av.trail = av.trail.filter(q => now - q.t < 150).concat([{ x: p.x, y: p.y, t: now }])
            if (av.aim) av.aimCheck()
        }
    }
    Timer { id: aimTimer; interval: 60; onTriggered: av.aimCheck() }
    function pointed(ri, i) {
        if (Date.now() - lastMove > 120) return         // items sliding under a still pointer: not a pick
        aim = { ri: ri, i: i }
        aimCheck()
    }
    function unpointed(ri, i) { if (aim && aim.ri === ri && aim.i === i) { aim = null; aimTimer.stop() } }
    function aimCheck() {
        if (!aim) return
        const now = Date.now(), tr = trail.filter(q => now - q.t < 150)
        // its speed from the oldest place kept to now (a pointer that stops slows to nothing); one place alone, just
        // seen, says nothing yet
        let v = 0
        if (tr.length >= 2) v = Math.hypot(tr[tr.length - 1].x - tr[0].x, tr[tr.length - 1].y - tr[0].y) / Math.max(16, now - tr[0].t)
        else if (tr.length === 1 && now - tr[0].t < 60) v = Infinity
        if (v < 0.35 && now >= quietUntil) { const a = aim; aim = null; pick(a.ri, a.i) }
        else aimTimer.restart()
    }
    function pick(ri, i) {
        const r = rep.itemAt(ri)
        if (!r || (ri === at && r.picked === i && mode === "pointer")) return
        if (ri !== at && ring) ring.picked = -1
        at = ri; r.picked = i; mode = "pointer"
    }
    function turn(dd) {
        if (!ring) return
        quietUntil = Date.now() + 650
        aim = null
        if (mode === "pointer" && ring.picked >= 0) { ring.bring(); mode = "slot"; return }
        mode = "slot"
        ring.turn(dd)
    }
    // the wheel: turns the ring under the pointer (p, in the view), and what lands under it takes the focus; away from
    // the rings (or on a placed one) it turns the ring you're on
    function wheelAt(dd, p) {
        if (!p) return turn(dd)
        const dist = Math.hypot(p.x - cx, p.y - cy)
        let hit = -1, best = 1e9
        for (let i = 0; i < rep.count; i++) {
            const r = rep.itemAt(i)
            if (!r) continue
            const g = Math.abs(dist - r.r)
            if (g < r.d(r.size) / 2 + d(34) * k && g < best) { best = g; hit = i }
        }
        const r = hit >= 0 ? rep.itemAt(hit) : null
        if (!r || r.placed) return turn(dd)
        if (hit !== at && ring) ring.picked = -1
        at = hit
        r.picked = -1
        r.turn(dd)
        const j = r.landingAt(Math.atan2(p.y - cy, p.x - cx) * 180 / Math.PI)
        if (Shell.debug) console.warn("ATOM atom wheel ring", hit, "by", dd, "at", Math.round(p.x), Math.round(p.y), "lands", j)
        if (j >= 0) { r.picked = j; mode = "pointer" } else mode = "slot"
        aim = null; aimTimer.stop()
        quietUntil = Date.now() + 420
    }
    function hop(dd) {
        const t = Math.max(0, Math.min(rep.count - 1, at + dd))
        if (t === at) return
        if (ring) ring.picked = -1
        const to = rep.itemAt(t)
        const nowAt = to && to.gauge ? to.items.findIndex(x => x.now) : -1
        if (nowAt >= 0) { to.placedCur = nowAt; to.current = nowAt }   // onto a gauge: its value now
        else if (to && to.placed && to.items.length) {        // onto a placed ring: the item nearest the lens's angle
            let best = 0, bd = 1e9
            for (let i = 0; i < to.items.length; i++) {
                const dd = Math.abs(((to.angleOf(i) - av.lensAngle) % 360 + 540) % 360 - 180)
                if (dd < bd) { bd = dd; best = i }
            }
            to.placedCur = best; to.current = best
        }
        at = t; mode = "slot"
        aim = null
        quietUntil = Date.now() + 400
    }
    function ringAt(i) { rep.count; return rep.itemAt(i) }
    function launch() { if (focusItem) launched(focusItem) }
    function openOptions() { if (ring && focusItem) options(focusItem, ring.focusDelegate) }

    Core { id: core; view: av; item: av.focusItem; tint: av.tint }

    // the beam (dock): a fine line of light from the core's arcs to the focus, along the lens's angle, under the rings
    Item {
        id: beam
        visible: av.dock && !!av.focusItem && len > 1
        x: av.cx; y: av.cy
        rotation: av.lensAngle
        opacity: M.clamp((av.stage.atomT - 0.75) * 4)
        readonly property real from: core.dia / 2 + av.d(34) * av.k
        readonly property real len: av.lensRA - from - lens.dia / 2 - av.d(8) * av.k
        readonly property color hot: av.rice.light ? av.rice.primary : C.mix(av.rice.primary, "#ffffff", 0.4)
        Rectangle {         // its glow
            x: beam.from; y: -height / 2; width: Math.max(0, beam.len); height: av.d(6) * av.k; radius: height / 2
            opacity: av.rice.light ? 0.12 : 0.22
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: C.alpha(av.rice.primary, 0) }
                GradientStop { position: 1; color: av.rice.primary }
            }
        }
        Rectangle {
            x: beam.from; y: -height / 2; width: Math.max(0, beam.len); height: Math.max(1, av.d(1.5) * av.k); radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: C.alpha(av.rice.primary, 0) }
                GradientStop { position: 0.55; color: C.alpha(av.rice.primary, 0.7) }
                GradientStop { position: 1; color: beam.hot }
            }
        }
    }

    Repeater {
        id: rep
        model: av.shells.length
        delegate: Orbit {           // (its own required `index` is the Repeater's)
            readonly property var sh: av.shells[index] || ({})
            view: av
            items: sh.items || []
            radius: sh.radius || 300
            size: sh.size || 66
            window: sh.window || 16
            placed: !!sh.placed
            gauge: !!sh.gauge
            name: sh.name || ""
            reveal: M.enter(M.clamp((av.stage.atomT - index * 0.09) / 0.82))
            onHovered: i => av.pointed(index, i)
            onUnhovered: i => av.unpointed(index, i)
            onClicked: i => { if (Shell.debug) console.warn("ATOM atom click ring", index, "item", i, "focus ring", av.at); av.aim = null; av.pick(index, i); if (av.at === index) av.launched(items[i]) }
            onRightClicked: (i, dl) => { av.aim = null; av.at = index; picked = i; av.mode = "pointer"; av.options(items[i], dl) }
        }
    }

    // the lens: a ring of light round the focus; a dot orbits its rim slowly, breathing, and runs round it when a new
    // focus lands. The orbit and the breath step from a timer (~30 a second, only while it shows): a looping animation
    // would redraw the whole launcher at the screen's refresh (the rice's rule)
    Item {
        id: lens
        readonly property Item target: av.ring ? av.ring.focusDelegate : null
        property real dia: (target ? target.lensSize : av.d(66) * av.k * 1.16) + av.d(26) * av.k
        width: dia; height: dia
        x: av.lensX - width / 2
        y: av.lensY - height / 2
        Behavior on dia { NumberAnimation { duration: Tokens.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        opacity: M.clamp((av.stage.atomT - 0.75) * 4) * (av.focusItem ? 1 : 0)
        z: 5
        Rectangle {
            anchors.fill: parent; radius: width / 2; color: "transparent"
            border.width: Math.max(1.6, av.d(1.6)); border.color: C.alpha(av.rice.fg, 0.88)
        }
        Rectangle {         // its glow (quiet: the focus's colour stays in the core)
            anchors.centerIn: parent; width: parent.width + av.d(12); height: width; radius: width / 2; z: -1
            color: "transparent"; border.width: av.d(6); border.color: C.alpha(av.rice.primary, 0.14)
        }
        Item {
            id: orbitDot
            anchors.fill: parent
            property real breath: 1
            Timer {
                interval: 33; repeat: true
                running: lens.opacity > 0.01 && av.visible && av.stage.visible
                onTriggered: {
                    const t = Date.now()
                    orbitDot.rotation = (t % 16000) / 16000 * 360                               // a turn every 16 s
                    orbitDot.breath = 0.775 - 0.225 * Math.cos(2 * Math.PI * (t % 6400) / 6400)  // .55 .. 1 and back, 6.4 s
                }
            }
            Item {
                id: electron
                anchors.fill: parent
                Rectangle { x: parent.width / 2 - width / 2; y: -height / 2; width: av.d(8); height: width; radius: width / 2; color: av.rice.fg
                            opacity: orbitDot.breath
                            Rectangle { anchors.centerIn: parent; width: parent.width * 2.6; height: width; radius: width / 2; color: C.alpha(av.rice.primary, 0.35); z: -1 } }
                RotationAnimation on rotation { id: run; running: false; from: -200; to: 0; duration: Tokens.ms(900); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn }
            }
        }
        Connections { target: av; function onFocusItemChanged() { if (av.focusItem) run.restart() } }
    }

    // each ring's name, over its slot (a docked ring: over its slot item as the dock shows it, the active one's over
    // its lens)
    Repeater {
        model: av.shells.length
        delegate: Text {
            required property int index
            readonly property Item r: (rep.count, rep.itemAt(index))
            readonly property real big: r ? Math.max(r.size, ...(r.items || []).map(it => it.big || 0)) : 66
            // rings close together (the colour wheel's) take turns above and below their slot; rings whose items carry their
            // own names keep theirs above
            readonly property var sh: av.shells[index] || ({})
            readonly property bool tight: av.shells.some((o, j) => j !== index && Math.abs((o.radius || 300) - (sh.radius || 300)) < 110)
            readonly property bool below: tight && index % 2 === 1 && !((sh.items || [])[0] && sh.items[0].label)
            readonly property real clear: !r ? 0 : r.docked ? (av.at === index ? r.slotShown * 0.58 + av.d(25) * av.k : r.slotShown / 2 + av.d(12) * av.k) + av.d(4) * av.k
                                                            : big * 0.58 * av.d(1) * av.k + av.d(30) * av.k
            x: av.cx - (r ? r.r : 0) - width / 2
            y: below ? av.cy + big * 0.58 * av.d(1) * av.k + av.d(14) * av.k
                     : av.cy - clear - height
            text: r ? r.name : ""
            color: av.at === index ? av.rice.fg : av.rice.fgDim
            font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: av.d(14.5); font.letterSpacing: av.d(0.6)
            opacity: M.clamp((av.stage.atomT - 0.75) * 4)
            Behavior on color { ColorAnimation { duration: Tokens.ms(300) } }
        }
    }
}
