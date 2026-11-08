import QtQuick
import "../Rice"

// One panel surface that changes shape (the heart of the shell's "morphing" feel): it grows out of the
// island it was opened from, glides and reshapes to another island's panel while open, and shrinks back
// into its island when it closes. Each kind's content is a QML file (`panels`, kind -> url); the sheet
// sizes itself to the content's implicit size and moves when that changes (a sub-page, a longer list).
//
// The content is laid out once at its final size and revealed by the growing shape (clipped), so text
// never reflows mid-morph. Bind BlurBehind / InputMask to `shape`.
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

    // the glass (plain colours)
    property color fill: Tokens.neutral.dark
    property real fillAlpha: 0.8
    property color rimA: "white"
    property color rimB: "white"

    // live shape, in this item's coordinates
    readonly property var shape: ({ x: sx, y: sy, width: sw, height: sh, radius: sr })
    readonly property bool shown: phase !== "closed"
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
    property bool animate: false
    readonly property bool collapsing: phase === "closing"
    readonly property int dur: collapsing ? Tokens.collapse : Tokens.morph
    readonly property int curve: collapsing ? Tokens.exit : Tokens.grow
    Behavior on sx { enabled: sheet.animate; NumberAnimation { duration: sheet.dur; easing.type: sheet.curve } }
    Behavior on sy { enabled: sheet.animate; NumberAnimation { duration: sheet.dur; easing.type: sheet.curve } }
    Behavior on sw { enabled: sheet.animate; NumberAnimation { duration: sheet.dur; easing.type: sheet.curve } }
    Behavior on sh { enabled: sheet.animate; NumberAnimation { duration: sheet.dur; easing.type: sheet.curve } }
    Behavior on sr { enabled: sheet.animate; NumberAnimation { duration: sheet.dur; easing.type: sheet.curve } }
    Behavior on lift { enabled: sheet.animate; NumberAnimation { duration: sheet.dur; easing.type: sheet.curve } }

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
    function goTo(r, radius, l) { sx = r.x; sy = r.y; sw = r.width; sh = r.height; sr = radius; lift = l }
    function islandRadius() { return Math.min(island.height, island.width) / 2 }
    onTargetChanged: if (phase === "opening" || phase === "open") goTo(target, radius, 1)

    // ------------------------------------------------------------------ content (two slots: cross-fade)
    property int front: 0
    readonly property var slots: [slotA, slotB]
    function load(k) {
        const back = 1 - front
        const s = slots[back]
        s.kindLoaded = k
        // every panel takes: ricePalette, screenName, ui (from props), kind and args (what it was opened with)
        s.setSource(panels[k] || "", Object.assign({ kind: k, args: Shell.args }, props))
        if (!s.item) { console.warn("Atom.Sheet: no panel for", k); return false }
        s.item.opacity = 0
        slots[front].leave()
        front = back
        return true
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
                if (phase === "closed") {
                    animate = false
                    goTo(island, islandRadius(), 0)
                    fade = 0
                }
                animate = true
                phase = "opening"
                fadeIn.restart()
                settle.restart()
            }
            goTo(target, radius, 1)         // open, or glide to another island's panel
            if (fresh) slots[front].enter(wasClosed)
        } else if (phase !== "closed") {
            phase = "closing"
            settle.stop()
            slots[front].leave()
            goTo(island, islandRadius(), 0)
            fadeOut.restart()
        }
    }
    Timer { id: settle; interval: sheet.dur; onTriggered: if (sheet.phase === "opening") sheet.phase = "open" }
    NumberAnimation { id: fadeIn; target: sheet; property: "fade"; to: 1; duration: Math.round(Tokens.morph * 0.3); easing.type: Easing.OutQuad }
    SequentialAnimation {
        id: fadeOut
        PauseAnimation { duration: Math.round(Tokens.collapse * 0.45) }
        NumberAnimation { target: sheet; property: "fade"; to: 0; duration: Math.round(Tokens.collapse * 0.55); easing.type: Easing.InQuad }
        ScriptAction { script: { sheet.phase = "closed"; slotA.setSource(""); slotB.setSource("") } }
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
    }
    Item {
        id: clipper
        x: sheet.sx; y: sheet.sy; width: sheet.sw; height: sheet.sh
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
                // laid out at the panel's final place, revealed by the growing shape; content on its way
                // out keeps the place it had
                property rect frozen: Qt.rect(0, 0, 0, 0)
                readonly property bool isFront: sheet.front === index
                readonly property rect place: isFront ? sheet.target : frozen
                x: place.x - sheet.sx + sheet.pad
                y: place.y - sheet.sy + sheet.pad
                width: item ? Math.min(item.implicitWidth, place.width - 2 * sheet.pad) : 0
                height: item ? Math.min(item.implicitHeight, place.height - 2 * sheet.pad) : 0
                focus: isFront
                Component.onCompleted: index === 0 ? sheet.slotA = slot : sheet.slotB = slot
                transform: Translate { id: rise }
                function enter(opening) {
                    leaving.stop()
                    entering.delay = opening ? Math.round(Tokens.morph * 0.35) : Math.round(Tokens.morph * 0.2)
                    entering.restart()
                    if (item && item.enter) item.enter()
                    Qt.callLater(() => { if (item) item.forceActiveFocus() })
                }
                function leave() {
                    frozen = sheet.target
                    if (!item) return
                    entering.stop()
                    leaving.restart()
                }
                SequentialAnimation {
                    id: entering
                    property int delay: 0
                    ScriptAction { script: { if (slot.item) slot.item.opacity = 0; rise.y = 6 } }
                    PauseAnimation { duration: entering.delay }
                    ParallelAnimation {
                        NumberAnimation { target: slot.item; property: "opacity"; to: 1; duration: Tokens.base; easing.type: Tokens.enter }
                        NumberAnimation { target: rise; property: "y"; to: 0; duration: Tokens.slow; easing.type: Tokens.enter }
                    }
                }
                SequentialAnimation {
                    id: leaving
                    NumberAnimation { target: slot.item; property: "opacity"; to: 0; duration: Tokens.fast; easing.type: Tokens.exit }
                    ScriptAction { script: { if (sheet.slots[sheet.front] !== slot) slot.setSource("") } }
                }
            }
        }
    }
    property Loader slotA: null
    property Loader slotB: null
}
