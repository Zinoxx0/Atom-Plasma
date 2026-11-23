import QtQuick
import Atom
import Rice

// The atom: rings round a core, a lens on the focus, each ring's name above its slot.
// Focus: the keys and a pad turn the ring you're on (the focus stays at the slot, 9 o'clock) and step between rings.
// The pointer picks an item where it is (mode "pointer": the lens travels to it along the ring, nothing turns) AT ONCE
// (the user, 2026-11-23: "it should be snappy"), unless it's flung across the atom (faster than 1.6 px/ms over the
// last 80 ms: then the item it slows down on), and only on a real move (not items sliding under a still pointer, nor
// right after a turn); items take the pointer 16 px round themselves. The wheel turns the
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
    readonly property int ringCount: rep.count
    readonly property var focusItem: ring ? ring.focusItem : null
    signal launched(var item)
    signal options(var item, Item delegate)

    // the lens: an angle (deg, clockwise from 3 o'clock) and a radius, so it glides along the rings; on springs, heading
    // where its item WILL be (a docked ring's rest angle), so a moving dock never drags it behind
    readonly property real lensTarget: {
        if (!ring) return 180
        if (ring.placed) return ring.angleOf(ring.focusIndex)        // a placed ring: the lens goes to the item
        if (mode !== "pointer" || ring.picked < 0) return 180
        if (ring.docked) return ring.restAngle(ring.picked)
        const p = ring.centreOf(ring.picked)
        return Math.atan2(p.y - cy, p.x - cx) * 180 / Math.PI
    }
    Spring { id: lensA; to: av.lensTarget; angle: true; stiffness: 15 }
    readonly property real lensAngle: lensA.value
    Spring { id: lensRS; to: av.ring ? av.ring.restR : 0; stiffness: 15; epsilon: 0.1 }
    readonly property real lensRA: lensRS.value
    // where the lens is, for the rings' haze (its gap)
    readonly property real lensX: cx + lensRA * Math.cos(lensAngle * Math.PI / 180)
    readonly property real lensY: cy + lensRA * Math.sin(lensAngle * Math.PI / 180)
    readonly property real lensHole: lens.opacity > 0.01 ? lens.dia / 2 + d(7) * k : 0
    // the haze's mask: each Node draws its gap there (its shown edge + holeGap)
    readonly property Item holes: haze.gaps
    readonly property real holesX: haze.x
    readonly property real holesY: haze.y
    readonly property real holeGap: haze.gap

    // the pointer: only real moves count, never right after a turn; a fling waits until it slows
    property double lastMove: 0
    property double quietUntil: 0
    readonly property real flingSpeed: 1.6          // px/ms
    property var trail: [null, null, null, null, null, null, null, null]   // its recent places, a ring: { x, y, t }
    property int trailAt: 0
    property var aim: null                  // { ri, i }: the item under a flung pointer, picked once it slows
    HoverHandler {
        onPointChanged: {
            const now = Date.now(), p = point.position, was = av.trail[av.trailAt]
            if (!was || Math.abs(p.x - was.x) + Math.abs(p.y - was.y) <= 1) {      // (its first place: the page appeared under it)
                av.trail[av.trailAt] = { x: p.x, y: p.y, t: was ? was.t : 0 }
                return
            }
            av.lastMove = now
            av.trailAt = (av.trailAt + 1) % av.trail.length
            av.trail[av.trailAt] = { x: p.x, y: p.y, t: now }
            if (av.aim) av.aimCheck()
        }
    }
    Timer { id: aimTimer; interval: 40; onTriggered: av.aimCheck() }
    function speed() {          // over the last 80 ms (the newest place to the oldest one that recent)
        const now = Date.now(), n = trail.length, last = trail[trailAt]
        if (!last) return 0
        let old = last
        for (let j = 1; j < n; j++) { const q = trail[(trailAt - j + n) % n]; if (!q || now - q.t > 80) break; old = q }
        return old === last ? 0 : Math.hypot(last.x - old.x, last.y - old.y) / Math.max(16, now - old.t)
    }
    function pointed(ri, i) {
        if (Date.now() - lastMove > 120) return         // items sliding under a still pointer: not a pick
        aim = { ri: ri, i: i }
        aimCheck()
    }
    function unpointed(ri, i) { if (aim && aim.ri === ri && aim.i === i) { aim = null; aimTimer.stop() } }
    function aimCheck() {
        if (!aim) return
        const now = Date.now()
        if (now >= quietUntil && (now - lastMove > 40 || speed() < flingSpeed)) { const a = aim; aim = null; aimTimer.stop(); pick(a.ri, a.i) }
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
        quietUntil = Date.now() + 250
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
        quietUntil = Date.now() + 300
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
        quietUntil = Date.now() + 250
    }
    function ringAt(i) { rep.count; return rep.itemAt(i) }
    // the focus, to carry to another screen's launcher: the ring you're on and each ring's item
    function save() {
        const idx = []
        for (let i = 0; i < rep.count; i++) { const r = rep.itemAt(i); idx.push(r ? r.focusIndex : 0) }
        return { at: at, idx: idx }
    }
    function restore(f) {
        if (!f || !f.idx) return
        for (let i = 0; i < rep.count && i < f.idx.length; i++) {
            const r = rep.itemAt(i)
            if (r && r.count && !r.placed) { r.picked = -1; r.current = Math.min(f.idx[i], r.count - 1) }
        }
        at = Math.max(0, Math.min(rep.count - 1, f.at))
        mode = "slot"
    }
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

    Haze { id: haze; view: av }

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
        Spring { id: diaS; to: (lens.target ? lens.target.lensSize : av.d(66) * av.k * 1.16) + av.d(26) * av.k; stiffness: 15; epsilon: 0.1 }
        readonly property real dia: diaS.value
        width: dia; height: dia
        x: av.lensX - width / 2
        y: av.lensY - height / 2
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
            // a docked ring: clear of whatever is under it now (the slot's item, or a neighbour the dock moved there
            // round a pointer's pick; the lens round the focus), not only the slot's item (it sat on an icon)
            readonly property real clear: {
                if (!r) return 0
                if (!r.docked) return big * 0.58 * av.d(1) * av.k + av.d(30) * av.k
                const lx = av.cx - r.r, half = width / 2 + av.d(6) * av.k
                let reach = 0
                const take = (x, y, h) => { if (Math.abs(x - lx) < half + h && y - h < av.cy) reach = Math.max(reach, av.cy - (y - h)) }
                for (let i = 0; i < r.count; i++) {
                    const a = r.angleAt(i) * Math.PI / 180, it = r.items[i] || {}
                    take(av.cx + r.r * Math.cos(a), av.cy + r.r * Math.sin(a), r.d(it.big || r.size) * r.scaleAt(i) / 2)
                }
                if (av.at === index && lens.opacity > 0.01) take(av.lensX, av.lensY, lens.dia / 2)
                return reach + av.d(10) * av.k
            }
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
