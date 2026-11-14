import QtQuick
import org.kde.plasma.core as PlasmaCore
import Atom
import "Rice"
import "Rice/Color.js" as C

// A row of Atom Home: its title, then its tiles in a strip. The strip is a horizontal ListView, so only
// the tiles in sight (and half a screen either side) exist: a row of 159 wallpapers costs what a row of ten
// does. The focused tile sits at the anchor (the `anchor`-th slot) and the strip glides under it, within the
// row's ends (the last tile stops at the right margin). The keyboard moves the strip (settle(true)); the
// pointer focuses where it is, so nothing slides out from under it; dragging, or a sideways wheel / touchpad
// (the stage hands it over: slide(ev)), moves the strip by hand. A divider can part the row (pins | recents).
// Depth: the focused row is the near one; the others sit behind it, their tiles a little smaller and every
// part of them see-through (the title keeps its size: the rows keep one rhythm whichever is near).
// Tiles that slide past the left margin fade out there: nothing runs off the left edge of the screen.
// A row can carry its own settings (the Theme page's: Shuffle, Intensity, Brightness...): they sit in its
// header, after the title, always in sight; `toolFocus` rings the one the keys are on.
Item {
    id: hr
    required property var row               // HomeModel's: { id, title, shape, items, divider, labeled, count }
    required property RicePalette rice
    property int current: 0
    property bool active: false
    property bool tilesFocused: true        // the keys are on its tiles (not on its header's tools)
    property real unit: 1
    property real side: 76
    property int anchor: 1
    property int focusMs: Tokens.ms(380)
    property real titleO: 1                 // the stage's entrance
    readonly property var tools: row.tools || []
    property int toolFocus: -1              // the header tool the keys are on (-1: none)
    signal toolActivated(string id)
    signal activated(int i, Item tile)
    signal pointed(int i, point at)         // the pointer is over tile i (at: where, in the window)
    signal pointerOut(int i)
    signal menu(int i, Item tile)
    function u(n) { return Math.round(n * unit) }

    readonly property real base: u(118)
    readonly property size tileSize: row.shape === "portrait" ? Qt.size(Math.round(base * 0.98), Math.round(base * 1.47))
                                   : row.shape === "poster" ? Qt.size(Math.round(base * 1.34), Math.round(base * 2.0))
                                   : row.shape === "wall" ? Qt.size(Math.round(base * 1.72), Math.round(base * 0.97))
                                   : row.shape === "look" ? Qt.size(Math.round(base * 2.05), Math.round(base * 1.2))
                                   : row.labeled ? Qt.size(Math.round(base * 0.86), Math.round(base * 0.86))
                                   : Qt.size(base, base)
    readonly property real pad: u(22)       // clear of the focused tile's lift and ring
    readonly property real gap: u(24)
    readonly property real gapDivider: u(40)
    readonly property real titleH: row.title ? u(34) : 0
    readonly property real labelH: row.labeled ? u(42) : 0
    readonly property int count: row.items ? row.items.length : 0
    readonly property bool moving: strip.moving || glide.running   // dragged, flicked or gliding
    implicitHeight: titleH + pad + tileSize.height + pad + labelH + u(16)

    // where tile i starts on the strip (no tile has to exist for this: they all have the row's size)
    function slotX(i) { return i * (tileSize.width + gap) + (row.divider >= 0 && i >= row.divider ? gapDivider : 0) }
    readonly property real stripW: count ? slotX(count - 1) + tileSize.width : 0
    // the strip's travel: 0 = the first tile at the left margin, maxOffset = the last at the right one
    readonly property real maxOffset: Math.max(0, stripW - (width - 2 * side))

    // 0 = the focused row, 1 = a row behind it
    property real depth: active ? 0 : 1
    Behavior on depth { NumberAnimation { duration: hr.focusMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
    Item {
        id: body
        anchors.fill: parent
        opacity: 1 - 0.55 * hr.depth
        // faded as one picture (a tile's shadow doesn't show through it)
        layer.enabled: hr.depth > 0.01

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
                color: hr.active ? hr.rice.fg : hr.rice.fgDim
                font.family: Tokens.font.ui
                font.weight: Font.DemiBold
                font.pixelSize: hr.u(20)
                Behavior on color { ColorAnimation { duration: Tokens.base } }
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
            Rectangle {     // title | tools
                visible: hr.tools.length > 0
                anchors.verticalCenter: parent.verticalCenter
                width: 1; height: hr.u(18)
                color: C.alpha(hr.rice.fg, 0.16)
            }
            Row {
                spacing: hr.u(8)
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    id: toolRep
                    model: hr.tools.length
                    delegate: Tool {
                        required property int index
                        tool: hr.tools[index] || ({})
                        focused: hr.toolFocus === index
                        rice: hr.rice
                        unit: hr.unit
                        onActivate: id => hr.toolActivated(id)
                    }
                }
            }
        }

        ListView {
            id: strip
            y: hr.titleH + hr.pad
            // behind: the tiles a little smaller, from the row's top left (they stay under their title)
            transform: Scale { origin.x: hr.side; origin.y: 0; xScale: 1 - 0.08 * hr.depth; yScale: xScale }
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
                // past the left margin it fades out (gone when half of it is past)
                opacity: Math.max(0, Math.min(1, 1 + (slot.x + slot.lead - strip.contentX - hr.side) / (hr.tileSize.width * 0.5)))
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
                    rowActive: hr.active && hr.tilesFocused
                    focusMs: hr.focusMs
                    onPointed: at => hr.pointed(slot.index, at)
                    onPointerOut: hr.pointerOut(slot.index)
                    onActivated: hr.activated(slot.index, t)
                    onMenu: hr.menu(slot.index, t)
                }
            }
        }

    }

    function tileAt(i) { const s = strip.itemAtIndex(i); return s ? s.tile : null }
    function toolAt(i) { return toolRep.itemAt(i) }

    // a header tool: a glass pill (icon and label), a round − / +, a toggle with its state, or a value
    component Tool: Rectangle {
        id: tl
        property var tool: ({})
        property bool focused: false
        property RicePalette rice: null     // (an inline component sees no ids of its file: all passed in)
        property real unit: 1
        function u(n) { return Math.round(n * unit) }
        signal activate(string id)
        readonly property string kind: tool.kind || "button"
        readonly property bool round: kind === "minus" || kind === "plus"
        readonly property bool hot: tma.containsMouse
        height: tl.u(34)
        width: round ? height : tlRow.implicitWidth + (kind === "value" ? tl.u(4) : tl.u(30))
        radius: height / 2
        color: kind === "value" ? "transparent" : C.alpha(tl.rice.fg, (focused ? 0.16 : hot ? 0.13 : 0.07) + (kind === "toggle" && tool.on ? 0.05 : 0))
        border.width: kind === "value" ? 0 : 1
        border.color: C.alpha(tl.rice.edge, focused ? 0.22 : 0.12)
        scale: tma.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: Tokens.fast } }
        Behavior on color { ColorAnimation { duration: Tokens.fast } }
        Row {
            id: tlRow
            anchors.centerIn: parent
            spacing: tl.u(7)
            Rectangle {     // a toggle's state
                visible: tl.kind === "toggle"
                anchors.verticalCenter: parent.verticalCenter
                width: tl.u(8); height: width; radius: width / 2
                color: tl.tool.on ? tl.rice.primary : "transparent"
                border.width: tl.tool.on ? 0 : 1
                border.color: C.alpha(tl.rice.fg, 0.4)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tl.tool.icon || ""
                color: tl.focused || tl.hot || tl.kind === "value" ? tl.rice.fg : tl.rice.fgDim
                font.family: Tokens.font.icons
                font.pixelSize: tl.u(19)
            }
            Text {
                visible: !tl.round && !!tl.tool.label
                anchors.verticalCenter: parent.verticalCenter
                text: tl.tool.label || ""
                color: tl.focused || tl.hot || tl.kind === "value" ? tl.rice.fg : tl.rice.fgDim
                font.family: Tokens.font.ui
                font.weight: Font.DemiBold
                font.pixelSize: tl.u(14.5)
                font.features: { "tnum": 1 }
            }
        }
        Rectangle {     // the keys' ring: the tiles' language (outside, with a gap)
            readonly property real g: Math.max(2, tl.u(3))
            readonly property real w: Math.max(2, tl.u(2))
            anchors.fill: parent
            anchors.margins: -(g + w)
            radius: height / 2
            color: "transparent"
            border.width: w
            border.color: tl.rice.light ? tl.rice.fg : "#ffffff"
            opacity: tl.focused ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
        }
        PlasmaCore.ToolTipArea {        // (around the MouseArea: under it, it would take the clicks)
            anchors.fill: parent
            active: !!tl.tool.tip
            mainText: tl.tool.tip || ""
            MouseArea {
                id: tma
                anchors.fill: parent
                enabled: tl.kind !== "value"
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: tl.activate(tl.tool.id)
            }
        }
    }
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
