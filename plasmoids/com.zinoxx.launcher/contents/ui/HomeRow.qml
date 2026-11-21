import QtQuick
import Atom
import Rice

// A row of Atom Home: its title, then its tiles in a grid that takes at most 65% of the screen's width (the
// user, 2026-11-15: no endless strips). A row with more than one line of tiles shows its first line with a
// "Show more" tile in the last place; each "Show more" adds two lines under it, the last line keeping one
// more place for "Show less" while there's still more to show; "Show less" takes two lines away again
// (5 -> 3 -> 1). How many lines show is the stage's (`lines`, per page and row); the controls are slots like
// the tiles (entryAt), so the keys, the pad and the pointer reach them the same way. The row doesn't move
// sideways: dragging moves the page (the stage's Flickable). A divider can part the row (pins | recents).
// Every row is drawn the same, at full strength (the focus outline alone says where you are), and every
// row of apps has one tile size.
Item {
    id: hr
    required property var row               // HomeModel's: { id, title, shape, items, divider, labeled, count }
    required property RicePalette rice
    property int current: 0
    property bool active: false
    property bool tilesFocused: true        // the keys are on its tiles (not on the top bar)
    property real unit: 1
    property real side: 76
    property int lines: 1                   // how many lines show (1, 3, 5...: the stage's, per row)
    property int focusMs: Tokens.ms(380)
    property real titleO: 1                 // the stage's entrance
    property bool pointerMode: false        // the pointer is the input in use: tiles show its hover and their corner buttons
    property var isPinned: null             // item -> pinned (the stage's)
    signal pinToggle(int i)
    signal activated(int i, Item tile)
    signal pointed(int i, point at)         // the pointer is over tile i (at: where, in the window)
    signal pointerOut(int i)
    signal menu(int i, Item tile)
    function u(n) { return Math.round(n * unit) }

    readonly property real base: u(118)
    readonly property size tileSize: row.shape === "portrait" ? Qt.size(Math.round(base * 0.98), Math.round(base * 1.47))
                                   : row.shape === "poster" ? Qt.size(Math.round(base * 1.34), Math.round(base * 2.0))
                                   : row.labeled ? Qt.size(Math.round(base * 0.9), Math.round(base * 0.9))
                                   : Qt.size(base, base)
    readonly property real pad: u(22)       // clear of the focused tile's lift and ring
    readonly property real gap: u(24)
    readonly property real gapDivider: u(40)
    readonly property real titleH: row.title ? u(34) : 0
    readonly property real labelH: row.labeled ? u(42) : 0
    readonly property int count: row.items ? row.items.length : 0
    readonly property bool moving: false    // (rows don't move sideways any more: the page does)

    // ---- the grid: columns in 65% of the width, the lines shown, and the controls in the last places
    readonly property real lineGap: u(18)
    readonly property real cellW: tileSize.width + gap
    readonly property real lineH: tileSize.height + labelH
    readonly property int columns: Math.max(1, Math.floor((width * 0.65 + gap) / cellW))
    readonly property var layout: {
        const c = columns, L = Math.max(1, lines)
        if (count <= c) return { n: count, more: false, less: false }
        if (L <= 1) return { n: c - 1, more: true, less: false }
        if (count + 1 <= L * c) return { n: count, more: false, less: true }
        return { n: L * c - 2, more: true, less: true }
    }
    readonly property int shownItems: layout.n
    readonly property int slotCount: layout.n + (layout.more ? 1 : 0) + (layout.less ? 1 : 0)
    readonly property int linesShown: Math.max(1, Math.ceil(slotCount / columns))
    // what slot i holds: an item, or a control ({ ctl: "more" | "less", name, icon, meta, desc })
    function entryAt(i) {
        if (i < layout.n) return row.items[i] || null
        const k = i - layout.n, rest = count - layout.n
        const kinds = (layout.more ? ["more"] : []).concat(layout.less ? ["less"] : [])
        const ctl = kinds[k]
        if (!ctl) return null
        return ctl === "more" ? moreEntry : lessEntry
    }
    readonly property var moreEntry: ({ ctl: "more", key: "ctl:more:" + row.id, name: "Show more", icon: "expand_more",
        meta: [(count - layout.n) + " more"], desc: "Two more lines of " + String(row.title || "it").toLowerCase() + ", under this one." })
    readonly property var lessEntry: ({ ctl: "less", key: "ctl:less:" + row.id, name: "Show less", icon: "expand_less",
        meta: ["Two lines fewer"], desc: "Back to fewer lines of " + String(row.title || "it").toLowerCase() + "." })
    function lineOf(i) { return Math.floor(i / columns) }
    function lineY(l) { return titleH + pad + l * (lineH + lineGap) }       // a line's top, in the row
    readonly property real fullHeight: titleH + pad + linesShown * lineH + (linesShown - 1) * lineGap + pad + u(16)
    implicitHeight: fullHeight
    Behavior on implicitHeight { NumberAnimation { id: grow; duration: Math.round(hr.focusMs * 0.95); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }

    Item {
        id: body
        anchors.fill: parent

        Row {
            id: header
            x: hr.side
            height: hr.titleH
            spacing: hr.u(18)
            opacity: hr.titleO
            Text {
                id: titleText
                height: hr.titleH
                visible: !!hr.row.title
                verticalAlignment: Text.AlignVCenter
                text: hr.row.title
                color: hr.rice.fg
                font.family: Tokens.font.ui
                font.weight: Font.Bold
                font.pixelSize: hr.u(20)
                rightPadding: hr.row.count ? countText.implicitWidth + hr.u(10) : 0
                Text {
                    id: countText
                    anchors.right: parent.right
                    anchors.baseline: parent.baseline
                    visible: !!hr.row.count
                    text: hr.count
                    color: hr.rice.muted
                    font.family: Tokens.font.ui
                    font.weight: Font.DemiBold
                    font.pixelSize: hr.u(14.5)
                }
            }
        }

        Item {
            id: grid
            y: hr.titleH + hr.pad
            width: hr.width
            height: hr.height - y
            clip: grow.running          // (growing or shrinking: what's past its edge waits)
            Repeater {
                id: slots
                model: hr.slotCount     // by count: a rebuilt row with as many slots keeps its tiles
                delegate: Item {
                    id: slot
                    required property int index
                    readonly property var entry: (hr.layout, hr.entryAt(index))
                    readonly property Item tile: t
                    readonly property bool parted: index > 0 && index === hr.row.divider && index % hr.columns !== 0
                    x: hr.side + (index % hr.columns) * hr.cellW
                    y: Math.floor(index / hr.columns) * (hr.lineH + hr.lineGap)
                    width: hr.tileSize.width
                    height: hr.lineH
                    z: t.focused ? 2 : 0
                    Rectangle {     // the divider (pins | recents), in the gap before it
                        visible: slot.parted
                        x: -Math.round(hr.gap / 2)
                        y: hr.tileSize.height * 0.22
                        width: 1
                        height: hr.tileSize.height * 0.56
                        color: C.alpha(hr.rice.fg, 0.16)
                    }
                    HomeTile {
                        id: t
                        width: hr.tileSize.width
                        height: hr.tileSize.height
                        item: slot.entry
                        shape: hr.row.shape
                        rice: hr.rice
                        unit: hr.unit
                        labeled: hr.row.labeled
                        current: slot.index === hr.current
                        rowActive: hr.active && hr.tilesFocused
                        focusMs: hr.focusMs
                        pointerMode: hr.pointerMode
                        pinned: !!(hr.isPinned && slot.entry && !slot.entry.ctl && hr.isPinned(slot.entry))
                        onPinToggle: hr.pinToggle(slot.index)
                        onPointed: at => hr.pointed(slot.index, at)
                        onPointerOut: hr.pointerOut(slot.index)
                        onActivated: hr.activated(slot.index, t)
                        onMenu: hr.menu(slot.index, t)
                    }
                }
            }
        }

    }

    function tileAt(i) { const s = slots.itemAt(i); return s ? s.tile : null }

    // (no strip to settle or slide any more: kept so the stage's calls stay simple)
    function settle(animate) {}
    function slide(ev) {}
    // the tiles that show (their entrance staggers left to right, line by line)
    function shown() {
        const out = []
        for (let i = 0; i < slotCount; i++) { const t = tileAt(i); if (t) out.push(t) }
        return out
    }
}
