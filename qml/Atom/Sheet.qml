import QtQuick
import Rice

// One panel surface that changes shape (the heart of the shell's "morphing" feel): it grows out of the
// island it was opened from, glides and reshapes to another island's panel while open, and shrinks back
// into its island when it closes. Each kind's content is a QML file (`panels`, kind -> url); the sheet
// sizes itself to the content's implicit size and moves when that changes (a sub-page, a longer list).
//
// The shape moves on critically damped springs (no overshoot), stepped every frame: a new target half-way
// (the pointer moving on to another island, the content growing) bends the motion without a jolt, and a
// slow frame slows it down instead of making it jump. The content is laid out once at its final size and
// rides along centred in the glass, clipped by it, so text never reflows mid-morph; switching panels
// cross-fades the old content out quickly and the new one in. Bind InputMask to `shape` and BlurBehind to
// `shape` while `frosted`.
Item {
    id: sheet

    // present(kind, island) / dismiss(): what to show and where from. The window calls these (not
    // bindings), so the island is always known before the sheet starts moving.
    readonly property string kind: _kind
    property string _kind: ""
    property var panels: ({})                   // kind -> url of its content
    property rect island: Qt.rect(0, 0, 0, 0)   // the island it grows from (this item's coordinates)
    property rect bounds: Qt.rect(0, 0, width, height)     // where it may go
    property real gap: 12                       // between the panel and the island's top
    property real pad: Tokens.space.lg          // around the content
    property real radius: Tokens.radius.xl
    property var props: ({})                    // given to every content item (palette, screen, ...)

    // the glass (plain colours; optional Liquid Glass when pal + liquid are supplied)
    property color fill: Tokens.neutral.dark
    property real fillAlpha: 0.8
    property color rimA: "white"
    property color rimB: "white"
    property var pal: null
    property string glassStyle: ""

    // live shape, in this item's coordinates (a new object once per frame, not once per edge)
    readonly property var shape: shapeNow
    property var shapeNow: ({ x: 0, y: 0, width: 0, height: 0, radius: 0 })
    readonly property bool shown: phase !== "closed"
    // KWin's blur behind it, only while the glass is all there: blur at full strength under glass still
    // fading in or out smeared the island it grows from, then popped off
    readonly property bool frosted: shown && fade > 0.95 && sw > 2 && sh > 2
    property string phase: "closed"             // closed, opening, open, closing
    readonly property Item content: slots[front] ? slots[front].item : null

    // ------------------------------------------------------------------ geometry
    property real sx: 0
    property real sy: 0
    property real sw: 0
    property real sh: 0
    property real sr: 0
    property real lift: 0           // the glass's shadow, 0 while it is still the island
    property real fade: 0           // the whole sheet's opacity (its first and last moments)
    // where each spring is going and how fast it moves now (px/s)
    property real gx: 0; property real gy: 0; property real gw: 0; property real gh: 0; property real gr: 0; property real gl: 0
    property real vx: 0; property real vy: 0; property real vw: 0; property real vh: 0; property real vr: 0; property real vl: 0
    property bool moving: false
    // spring stiffness (rad/s): 22 covers 90% of the way in ~0.18 s, starting gently and easing out; it folds
    // back into its island quicker. Follows the system animation speed (0 = no animations: it jumps).
    readonly property real stiffness: (phase === "closing" ? 30 : 22) / Math.max(Tokens.speed, 0.01)

    // where the current content wants the panel: centred over its island, kept inside the bounds
    readonly property size want: content ? Qt.size(Math.ceil(content.implicitWidth) + 2 * pad,
                                                   Math.ceil(content.implicitHeight) + 2 * pad)
                                         : Qt.size(0, 0)
    readonly property rect target: {
        const w = Math.min(want.width, bounds.width), h = Math.min(want.height, bounds.height)
        const cx = island.x + island.width / 2
        const x = Math.max(bounds.x, Math.min(bounds.x + bounds.width - w, cx - w / 2))
        const y = Math.max(bounds.y, island.y - gap - h)
        return Qt.rect(Math.round(x), Math.round(y), w, h)
    }
    function islandRadius() { return Math.min(island.height, island.width) / 2 }
    onTargetChanged: if (phase === "opening" || phase === "open") goTo(target, radius, 1)

    // head for a shape (the springs keep the speed they have)
    function goTo(r, rad, l) {
        gx = r.x; gy = r.y; gw = r.width; gh = r.height; gr = rad; gl = l
        if (Tokens.speed <= 0) rest()
        else moving = true
    }
    // be there now, at rest
    function place(r, rad, l) {
        gx = r.x; gy = r.y; gw = r.width; gh = r.height; gr = rad; gl = l
        rest()
    }
    function rest() {
        sx = gx; sy = gy; sw = gw; sh = gh; sr = gr; lift = gl
        vx = 0; vy = 0; vw = 0; vh = 0; vr = 0; vl = 0
        moving = false
        publish()
        settled()
    }
    function publish() { shapeNow = { x: sx, y: sy, width: sw, height: sh, radius: sr } }
    // one frame of the springs: the exact critically damped step, so any frame rate gives the same curve
    function step(dt) {
        const w = stiffness, e = Math.exp(-w * dt)
        const one = (x, v, g) => { const d = x - g, c = v + w * d; return [g + (d + c * dt) * e, (v - w * c * dt) * e] }
        let s
        s = one(sx, vx, gx); sx = s[0]; vx = s[1]
        s = one(sy, vy, gy); sy = s[0]; vy = s[1]
        s = one(sw, vw, gw); sw = s[0]; vw = s[1]
        s = one(sh, vh, gh); sh = s[0]; vh = s[1]
        s = one(sr, vr, gr); sr = s[0]; vr = s[1]
        s = one(lift, vl, gl); lift = s[0]; vl = s[1]
        const near = (x, v, g) => Math.abs(x - g) < 0.25 && Math.abs(v) < 6
        if (near(sx, vx, gx) && near(sy, vy, gy) && near(sw, vw, gw) && near(sh, vh, gh) && near(sr, vr, gr)
                && Math.abs(lift - gl) < 0.01)
            rest()
        else
            publish()
    }
    FrameAnimation {
        running: sheet.moving
        // (a long frame counts as a normal one: the motion pauses through a hitch instead of skipping ahead)
        onTriggered: sheet.step(frameTime > 0 ? Math.min(frameTime, 0.02) : 1 / 120)
    }
    function settled() {
        if (phase === "opening") phase = "open"
        tidy()
    }

    // ------------------------------------------------------------------ content (two slots: cross-fade)
    property int front: 0
    readonly property var slots: [slotA, slotB]
    function load(k) {
        const back = 1 - front
        const s = slots[back]
        const a = JSON.stringify(Shell.args || {})
        // the content on its way out comes back as it is (switching away and straight back); else new content
        if (!(s.item && s.kindLoaded === k && s.argsLoaded === a)) {
            s.kindLoaded = k
            s.argsLoaded = a
            // every panel takes: ricePalette, screenName, ui (from props), kind and args (what it was opened with)
            s.setSource(panels[k] || "", Object.assign({ kind: k, args: Shell.args }, props))
            if (!s.item) { console.warn("Atom.Sheet: no panel for", k); return false }
            s.item.opacity = 0
        }
        slots[front].leave()
        front = back
        return true
    }
    // content that has faded out goes once the shape is at rest (destroying a panel mid-glide cost a frame)
    function tidy() {
        if (moving) return
        for (const s of slots)
            if (s && s !== slots[front] && s.gone) { s.setSource(""); s.kindLoaded = ""; s.argsLoaded = ""; s.gone = false }
    }

    function present(k, from) {
        if (!(k in panels)) { dismiss(); return }
        const sameIsland = island.x === from.x && island.y === from.y && island.width === from.width
        if (k === _kind && sameIsland && (phase === "open" || phase === "opening")) return
        island = from
        _kind = k
        update()
    }
    function dismiss() {
        if (_kind === "" && (phase === "closed" || phase === "closing")) return
        _kind = ""
        update()
    }
    function update() {
        if (kind) {
            const wasClosed = phase === "closed" || phase === "closing"
            // new content, or the content that was on its way out comes back
            const fresh = wasClosed || slots[front].kindLoaded !== kind || !slots[front].item
            if (slots[front].kindLoaded !== kind || !slots[front].item) { if (!load(kind)) return }
            if (wasClosed) {
                fadeOut.stop()
                if (phase === "closed") {           // born as the island itself, then grows out of it
                    place(island, islandRadius(), 0)
                    fade = 0
                }
                phase = "opening"
                fadeIn.restart()
            }
            goTo(target, radius, 1)         // open, or glide to another island's panel
            if (fresh) slots[front].enter(wasClosed)
        } else if (phase !== "closed") {
            phase = "closing"
            slots[front].leave()
            fadeIn.stop()
            goTo(island, islandRadius(), 0)
            fadeOut.restart()
        }
    }
    NumberAnimation { id: fadeIn; target: sheet; property: "fade"; to: 1; duration: Tokens.fast; easing.type: Easing.OutQuad }
    SequentialAnimation {
        id: fadeOut
        PauseAnimation { duration: Tokens.ms(40) }
        NumberAnimation { target: sheet; property: "fade"; to: 0; duration: Tokens.ms(140); easing.type: Easing.InOutQuad }
        ScriptAction { script: sheet.closed() }
    }
    function closed() {
        phase = "closed"
        place(island, islandRadius(), 0)
        for (const s of slots) { s.setSource(""); s.kindLoaded = ""; s.argsLoaded = ""; s.gone = false }
    }

    // ------------------------------------------------------------------ drawing
    Glass {
        id: glass
        x: sheet.sx; y: sheet.sy; width: sheet.sw; height: sheet.sh
        visible: sheet.shown && sheet.sw > 1
        opacity: sheet.fade
        radius: sheet.sr
        fill: sheet.fill
        fillAlpha: sheet.fillAlpha
        rimA: sheet.rimA
        rimB: sheet.rimB
        lift: sheet.lift
        glassStyle: sheet.glassStyle
        pal: sheet.pal
        screenSize: Qt.size(sheet.width, sheet.height)
        screenPos: Qt.point(sheet.sx, sheet.sy)
    }
    Item {
        id: clipper
        // the clip keeps clear of the glass's round corners, so content never pokes out of them while the
        // shape changes (at rest the panel's padding keeps it clear anyway)
        readonly property real inset: Math.ceil(sheet.sr * 0.3)
        x: sheet.sx + inset; y: sheet.sy + inset
        width: Math.max(0, sheet.sw - 2 * inset); height: Math.max(0, sheet.sh - 2 * inset)
        visible: glass.visible
        opacity: sheet.fade
        clip: true
        // Esc anywhere in a panel closes it (content that wants Esc for itself accepts it first)
        Keys.onEscapePressed: Shell.close()
        Repeater {
            model: 2
            delegate: Loader {
                id: slot
                required property int index
                property string kindLoaded: ""
                property string argsLoaded: ""
                property bool gone: false           // faded out, waiting for the shape to rest to be unloaded
                readonly property bool isFront: sheet.front === index
                // laid out at its final size; content on its way out keeps the size it had
                property bool held: false
                property real heldW: 0
                property real heldH: 0
                width: held ? heldW : item ? Math.min(item.implicitWidth, Math.max(0, sheet.bounds.width - 2 * sheet.pad)) : 0
                height: held ? heldH : item ? Math.min(item.implicitHeight, Math.max(0, sheet.bounds.height - 2 * sheet.pad)) : 0
                // centred in the glass, on whole pixels: it rides along as the glass glides and grows
                x: Math.round(sheet.sx + (sheet.sw - width) / 2) - clipper.x
                y: Math.round(sheet.sy + (sheet.sh - height) / 2) - clipper.y
                focus: isFront
                enabled: isFront                    // (faded-out content takes no clicks)
                Component.onCompleted: index === 0 ? sheet.slotA = slot : sheet.slotB = slot
                transform: Translate { id: nudge }
                function enter(opening) {
                    leaving.stop()
                    held = false
                    gone = false
                    entering.delay = opening ? Tokens.ms(70) : Tokens.ms(40)
                    entering.rise = opening ? 6 : 0
                    entering.restart()
                    if (item && item.enter) item.enter()
                    Qt.callLater(() => { if (item) item.forceActiveFocus() })
                }
                function leave() {
                    if (!item) return
                    heldW = width
                    heldH = height
                    held = true
                    entering.stop()
                    leaving.restart()
                }
                SequentialAnimation {
                    id: entering
                    property int delay: 0
                    property real rise: 0
                    ScriptAction { script: nudge.y = entering.rise }
                    PauseAnimation { duration: entering.delay }
                    ParallelAnimation {
                        NumberAnimation { target: slot.item; property: "opacity"; to: 1; duration: Tokens.ms(200); easing.type: Easing.OutCubic }
                        NumberAnimation { target: nudge; property: "y"; to: 0; duration: Tokens.ms(320); easing.type: Easing.OutCubic }
                    }
                }
                SequentialAnimation {
                    id: leaving
                    NumberAnimation { target: slot.item; property: "opacity"; to: 0; duration: Tokens.ms(110); easing.type: Easing.OutQuad }
                    ScriptAction { script: { if (sheet.slots[sheet.front] !== slot) { slot.gone = true; sheet.tidy() } } }
                }
            }
        }
    }
    property Loader slotA: null
    property Loader slotB: null
}
