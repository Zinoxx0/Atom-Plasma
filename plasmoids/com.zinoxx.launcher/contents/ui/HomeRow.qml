import QtQuick
import "Rice"
import "Rice/Color.js" as C

// A row of Atom Home: its title, then its tiles in a strip. The focused tile sits at the anchor (the
// `anchor`-th slot) and the strip glides under it, within the row's ends (the last tile stops at the right
// margin). Only the keyboard moves the strip (settle(true)); the pointer focuses where it is, so nothing
// slides out from under it. A divider can part the row (pins | recents).
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
    implicitHeight: titleH + pad + tileSize.height + pad + (row.labeled ? u(30) : 0) + u(20)

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
            text: hr.row.items.length
            color: hr.rice.muted
            font.family: Tokens.font.ui
            font.weight: Font.DemiBold
            font.pixelSize: hr.u(13.5)
        }
    }

    property real offset: 0
    Behavior on offset {
        id: glide
        NumberAnimation { duration: Math.round(hr.focusMs * 1.4); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove }
    }
    Row {
        id: strip
        x: hr.side - hr.offset
        y: hr.titleH + hr.pad
        spacing: hr.gap
        Repeater {
            id: rep
            model: hr.row.items.length      // by count: a rebuilt row with as many items keeps its tiles
            delegate: Item {
                id: slot
                required property int index
                readonly property var entry: hr.row.items[index] || null
                readonly property real lead: index === hr.row.divider ? hr.gapDivider : 0
                readonly property Item tile: t
                width: hr.tileSize.width + lead
                height: hr.tileSize.height
                z: t.focused ? 2 : 0
                Rectangle {     // the divider (pins | recents)
                    visible: slot.lead > 0
                    x: Math.round(slot.lead / 2 - hr.gap / 2)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: parent.height * 0.56
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
    }
    function tileAt(i) { const s = rep.itemAt(i); return s ? s.tile : null }
    function slotX(i) { const s = rep.itemAt(i); return s ? s.x + s.lead : 0 }
    // the strip's place for the focus: the focused tile at the anchor, the row's ends kept
    function settle(animate) {
        if (rep.count === 0) return
        const a = slotX(Math.min(hr.anchor, rep.count - 1))
        const max = Math.max(0, strip.width - (hr.width - 2 * hr.side))
        const target = Math.max(0, Math.min(max, slotX(hr.current) - a))
        glide.enabled = animate
        hr.offset = target
        glide.enabled = true
    }
    // the tiles that show (their entrance staggers left to right)
    function shown() {
        const out = []
        for (let i = 0; i < rep.count; i++) {
            const s = rep.itemAt(i)
            if (s && s.x + s.width - hr.offset > -hr.side && s.x - hr.offset < hr.width) out.push(s.tile)
        }
        return out
    }
}
