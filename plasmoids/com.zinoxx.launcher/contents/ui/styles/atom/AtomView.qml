import QtQuick
import Rice

// The atom: rings round a core, a lens on the focus, each ring's name above its slot.
// Focus: the keys and a pad turn the ring you're on (the focus stays at the slot, 9 o'clock) and step between rings;
// the pointer picks an item where it is (mode "pointer": the lens travels to it along the ring, nothing turns), but
// only a real move counts (not items sliding under a still pointer, nor the moment after a turn); the first key after
// the pointer turns its pick to the slot. The lens's angle lights every ring from its side.
Item {
    id: av      // (not `view`: the rings have a `view` property, and `view: view` in a delegate binds it to itself)
    required property var stage
    property var shells: []                 // [{ name, items, radius, size, window }]
    property color tint: rice.primary       // the focus's colour (the page reads it off its icon)
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

    // the pointer: only real moves count, never while a ring turns
    property double lastMove: 0
    property double quietUntil: 0
    HoverHandler { onPointChanged: av.lastMove = Date.now() }
    function pick(ri, i) {
        if (Date.now() - lastMove > 120 || Date.now() < quietUntil) return
        const r = rep.itemAt(ri)
        if (!r || (ri === at && r.picked === i && mode === "pointer")) return
        if (ri !== at && ring) ring.picked = -1
        at = ri; r.picked = i; mode = "pointer"
    }
    function turn(dd) {
        if (!ring) return
        quietUntil = Date.now() + 650
        if (mode === "pointer" && ring.picked >= 0) { ring.bring(); mode = "slot"; return }
        mode = "slot"
        ring.turn(dd)
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
        quietUntil = Date.now() + 400
    }
    function ringAt(i) { rep.count; return rep.itemAt(i) }
    function launch() { if (focusItem) launched(focusItem) }
    function openOptions() { if (ring && focusItem) options(focusItem, ring.focusDelegate) }

    Core { id: core; view: av; item: av.focusItem; tint: av.tint }

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
            onHovered: i => av.pick(index, i)
            onClicked: i => { av.pick(index, i); if (av.at === index) av.launched(items[i]) }
            onRightClicked: (i, dl) => { av.at = index; picked = i; av.mode = "pointer"; av.options(items[i], dl) }
        }
    }

    // the lens: a ring of light round the focus; an electron runs its rim when a new one lands
    Item {
        id: lens
        readonly property Item target: av.ring ? av.ring.focusDelegate : null
        property real dia: (target ? target.width : av.d(66) * av.k) * 1.16 + av.d(26) * av.k
        width: dia; height: dia
        x: av.cx + av.lensRA * Math.cos(av.lensAngle * Math.PI / 180) - width / 2
        y: av.cy + av.lensRA * Math.sin(av.lensAngle * Math.PI / 180) - height / 2
        Behavior on dia { NumberAnimation { duration: Tokens.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        opacity: M.clamp((av.stage.atomT - 0.75) * 4) * (av.focusItem ? 1 : 0)
        z: 5
        Rectangle {
            anchors.fill: parent; radius: width / 2; color: "transparent"
            border.width: Math.max(1.6, av.d(1.6)); border.color: C.alpha(av.rice.fg, 0.85)
        }
        Rectangle {         // its glow
            anchors.centerIn: parent; width: parent.width + av.d(26); height: width; radius: width / 2; z: -1
            color: "transparent"; border.width: av.d(10); border.color: C.alpha(av.rice.primary, 0.22)
        }
        Item {
            id: electron
            anchors.fill: parent
            property int landings: 0
            Rectangle { x: parent.width / 2 - width / 2; y: -height / 2; width: av.d(8); height: width; radius: width / 2; color: av.rice.fg
                        Rectangle { anchors.centerIn: parent; width: parent.width * 2.6; height: width; radius: width / 2; color: C.alpha(av.rice.primary, 0.35); z: -1 } }
            RotationAnimation on rotation { id: run; running: false; from: -200; to: 0; duration: Tokens.ms(900); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn }
        }
        Connections { target: av; function onFocusItemChanged() { if (av.focusItem) run.restart() } }
    }

    // each ring's name, over its slot
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
            x: av.cx - (r ? r.r : 0) - width / 2
            y: below ? av.cy + big * 0.58 * av.d(1) * av.k + av.d(14) * av.k
                     : av.cy - big * 0.58 * av.d(1) * av.k - av.d(30) * av.k - height
            text: r ? r.name : ""
            color: av.at === index ? av.rice.fg : av.rice.fgDim
            font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: av.d(14.5)
            opacity: M.clamp((av.stage.atomT - 0.75) * 4)
            Behavior on color { ColorAnimation { duration: Tokens.ms(300) } }
        }
    }
}
