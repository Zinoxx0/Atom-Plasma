import QtQuick
import Atom
import "Rice"
import "Rice/Color.js" as C

// A row of Atom Home: its title, then its tiles in a strip. The strip is a horizontal ListView, so only
// the tiles in sight (and half a screen either side) exist: a row of 159 wallpapers costs what a row of ten
// does. The focused tile sits at the anchor (the `anchor`-th slot) and the strip glides under it, within the
// row's ends (the last tile stops at the right margin). The keyboard moves the strip (settle(true)); the
// pointer focuses where it is, so nothing slides out from under it; dragging, or a sideways wheel / touchpad
// (the stage hands it over: slide(ev)), moves the strip by hand. A divider can part the row (pins | recents).
Item {
    id: hr
    required property var row               // HomeModel's: { id, title, shape, items, divider, labeled, count }
    required property RicePalette rice
    property int current: 0
    property bool active: false
    property real unit: 1
    property real side: 76
    property int anchor: 1
    property int focusMs: Tokens.ms(380)
    property real titleO: 1                 // the stage's entrance
    signal activated(int i, Item tile)
    signal pointed(int i)
    signal menu(int i, Item tile)
    function u(n) { return Math.round(n * unit) }

    readonly property real base: u(118)
    readonly property size tileSize: row.shape === "portrait" ? Qt.size(Math.round(base * 0.98), Math.round(base * 1.47))
                                   : row.shape === "poster" ? Qt.size(Math.round(base * 1.34), Math.round(base * 2.0))
                                   : row.shape === "wall" ? Qt.size(Math.round(base * 1.72), Math.round(base * 0.97))
                                   : row.shape === "look" ? Qt.size(Math.round(base * 2.05), Math.round(base * 1.2))
                                   : row.labeled ? Qt.size(Math.round(base * 0.86), Math.round(base * 0.86))
                                   : Qt.size(base, base)
    readonly property real pad: u(16)
    readonly property real gap: u(18)
    readonly property real gapDivider: u(30)
    readonly property real titleH: row.title ? u(26) : 0
    readonly property real labelH: row.labeled ? u(30) : 0
    readonly property int count: row.items ? row.items.length : 0
    readonly property bool moving: strip.moving || glide.running   // dragged, flicked or gliding
    implicitHeight: titleH + pad + tileSize.height + pad + labelH + u(20)

    Text {
        x: hr.side
        height: hr.titleH
        visible: !!hr.row.title
        opacity: hr.titleO
        verticalAlignment: Text.AlignVCenter
        text: hr.row.title + (hr.row.count ? "   " : "")
        color: hr.active ? hr.rice.fg : hr.rice.fgDim
        font.family: Tokens.font.ui
        font.weight: Font.DemiBold
        font.pixelSize: hr.u(18.5)
        Behavior on color { ColorAnimation { duration: Tokens.base } }
        Text {
            anchors.left: parent.right
            anchors.baseline: parent.baseline
            visible: hr.row.count
            text: hr.count
            color: hr.rice.muted
            font.family: Tokens.font.ui
            font.weight: Font.DemiBold
            font.pixelSize: hr.u(13.5)
        }
    }

    // where tile i starts on the strip (no tile has to exist for this: they all have the row's size)
    function slotX(i) { return i * (tileSize.width + gap) + (row.divider >= 0 && i >= row.divider ? gapDivider : 0) }
    readonly property real stripW: count ? slotX(count - 1) + tileSize.width : 0
    // the strip's travel: 0 = the first tile at the left margin, maxOffset = the last at the right one
    readonly property real maxOffset: Math.max(0, stripW - (width - 2 * side))

    ListView {
        id: strip
        y: hr.titleH + hr.pad
        width: hr.width
        height: hr.tileSize.height + hr.labelH
        orientation: ListView.Horizontal
        spacing: hr.gap
        leftMargin: hr.side
        rightMargin: hr.side
        model: hr.count                     // by count: a rebuilt row with as many items keeps its tiles
        reuseItems: true
        cacheBuffer: Math.round(hr.width / 2)
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 2600
        maximumFlickVelocity: 5000
        interactive: hr.maxOffset > 0
        highlightFollowsCurrentItem: false
        currentIndex: -1
        onMovementStarted: glide.stop()
        onMovementEnded: if (Shell.debug) console.warn("ATOM row", hr.row.id, "dragged to", Math.round(contentX))
        NumberAnimation {
            id: glide
            target: strip; property: "contentX"
            duration: Math.round(hr.focusMs * 1.4)
            easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove
        }
        delegate: Item {
            id: slot
            required property int index
            readonly property var entry: hr.row.items[index] || null
            readonly property real lead: index === hr.row.divider ? hr.gapDivider : 0
            readonly property Item tile: t
            width: hr.tileSize.width + lead
            height: hr.tileSize.height + hr.labelH
            z: t.focused ? 2 : 0
            ListView.onReused: { t.opacity = 1; t.enter = 0 }
            Rectangle {     // the divider (pins | recents)
                visible: slot.lead > 0
                x: Math.round(slot.lead / 2 - hr.gap / 2)
                y: hr.tileSize.height * 0.22
                width: 1
                height: hr.tileSize.height * 0.56
                color: C.alpha(hr.rice.fg, 0.16)
            }
            HomeTile {
                id: t
                x: slot.lead
                width: hr.tileSize.width
                height: hr.tileSize.height
                item: slot.entry
                shape: hr.row.shape
                rice: hr.rice
                unit: hr.unit
                labeled: hr.row.labeled
                current: slot.index === hr.current
                rowActive: hr.active
                focusMs: hr.focusMs
                onPointed: hr.pointed(slot.index)
                onActivated: hr.activated(slot.index, t)
                onMenu: hr.menu(slot.index, t)
            }
        }
    }

    function tileAt(i) { const s = strip.itemAtIndex(i); return s ? s.tile : null }
    // the strip's place for the focus: the focused tile at the anchor, the row's ends kept
    function settle(animate) {
        if (count === 0) return
        const a = slotX(Math.min(anchor, count - 1))
        const target = Math.max(0, Math.min(maxOffset, slotX(current) - a)) - side
        glide.stop()
        if (animate && Math.abs(strip.contentX - target) > 0.5) { glide.from = strip.contentX; glide.to = target; glide.start() }
        else strip.contentX = target
    }
    // a sideways wheel or touchpad moves the strip by hand
    function slide(ev) {
        if (!strip.interactive) return
        const px = ev.pixelDelta.x || ev.pixelDelta.y
        const d = px ? -px : -(ev.angleDelta.x || ev.angleDelta.y) / 120 * (tileSize.width + gap)
        glide.stop()
        strip.contentX = Math.max(-side, Math.min(maxOffset - side, strip.contentX + d))
    }
    // the tiles that show (their entrance staggers left to right)
    function shown() {
        const out = []
        const off = strip.contentX + side           // how far the strip has travelled
        for (let i = 0; i < count; i++) {
            const x = side + slotX(i) - off         // the tile's place in the row
            if (x >= width) break
            if (x + tileSize.width <= 0) continue
            const t = tileAt(i)
            if (t) out.push(t)
        }
        return out
    }
}
