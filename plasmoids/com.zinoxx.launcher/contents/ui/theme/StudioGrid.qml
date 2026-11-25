import QtQuick
import QtQuick.Effects
import Atom
import Rice

// A grid of pictures on the Theme page (your wallpapers; what wallhaven found): rounded tiles that fade out at the
// bottom (and at the top once scrolled), each with its badges (the screens it's on), a colour dot (the accent it
// gives) and a state ("Adding…", "Added"). The grid is ONE place for the focus that walks itself (a Focusable
// region): the keys move a tile at a time and it scrolls to keep it in sight; the pointer picks the tile it rests
// on (nothing scrolls under it). Its owner keeps the index (index, moved(i)) and says what a tile shows.
Item {
    id: sg
    required property Item studio
    property var list: []
    property int index: 0
    property string fkey: "grid"
    property string act: "Choose"
    property var thumbOf: function (it) { return it.thumb }
    property var badgesOf: function (it) { return [] }
    property var dotOf: function (it) { return "" }
    property var stateOf: function (it) { return "" }      // "" | "busy" | "done"
    property var tagOf: function (it) { return it.name || "" }
    property var descOf: function (it) { return "" }
    signal moved(int i)
    signal activated(var it)
    readonly property var lk: studio.look
    readonly property alias focusRegion: region
    function d(px) { return studio.d(px) }

    readonly property real gap: d(18)
    readonly property int cols: Math.max(3, Math.round((width + gap) / (d(244) + gap)))
    readonly property real tileW: (width - gap * (cols - 1)) / cols
    readonly property real tileH: tileW * 9 / 16
    readonly property real cellH: tileH + gap
    property int hoverIdx: -1
    property string scrollMode: "idle"      // "idle" | "reveal" | "wheel" | "drag"
    property bool syncingScroll: false
    property bool clampingScroll: false
    function rowOf(i) { return Math.floor(i / sg.cols) }
    function maxScrollY() { return Math.max(0, grid.contentHeight - grid.height) }
    function isTileSafe(i) {
        if (i < 0 || i >= sg.list.length || grid.height <= 0) return false
        const top = rowOf(i) * sg.cellH - grid.contentY
        const bot = top + sg.tileH
        const atBottom = grid.contentY + grid.height >= grid.contentHeight - 1
        const botMargin = atBottom ? sg.d(10) : sg.d(36)
        return top >= -sg.d(2) && bot <= grid.height - botMargin
    }
    function tileAtGrid(mx, my, requireSafe) {
        if (!sg.list.length || mx < 0 || mx >= sg.width || my < 0 || my >= grid.height) return -1
        const stepX = sg.tileW + sg.gap
        const col = Math.floor(mx / stepX)
        if (col < 0 || col >= sg.cols || mx - col * stepX > sg.tileW) return -1
        const cy = my + grid.contentY
        const row = Math.floor(cy / sg.cellH)
        if (row < 0 || cy - row * sg.cellH > sg.tileH) return -1
        const i = row * sg.cols + col
        if (i < 0 || i >= sg.list.length) return -1
        if (requireSafe && !isTileSafe(i)) return -1
        return i
    }
    Rectangle { id: tileMask; width: sg.tileW; height: sg.tileH; radius: sg.d(14); visible: false; layer.enabled: true }    // (every tile's corners)
    Item {
        id: view
        x: -sg.d(12)
        width: sg.width + sg.d(24)
        height: sg.height
        clip: true
        // the tiles fade out at the bottom (more below) and just at the top (scrolled)
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: fade; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
        Rectangle {
            id: fade
            anchors.fill: parent
            visible: false
            layer.enabled: true
            gradient: Gradient {
                GradientStop { position: 0; color: grid.contentY > 1 ? "transparent" : "black" }
                GradientStop { position: Math.min(0.3, sg.d(14) / Math.max(1, view.height)); color: "black" }
                GradientStop { position: Math.max(0.7, 1 - sg.d(70) / Math.max(1, view.height)); color: "black" }
                GradientStop { position: 1; color: grid.contentY + grid.height < grid.contentHeight - 1 ? "transparent" : "black" }
            }
        }
        GridView {
            id: grid
            x: sg.d(12)
            y: sg.d(10)
            width: sg.width + sg.gap
            height: parent.height - y
            cellWidth: sg.tileW + sg.gap
            cellHeight: sg.cellH
            model: sg.list.length
            reuseItems: true
            cacheBuffer: Math.round(sg.cellH * 2)
            boundsBehavior: Flickable.StopAtBounds
            onContentYChanged: {
                if (gridHover.hovered) sg.hoverIdx = sg.tileAtGrid(gridHover.point.position.x, gridHover.point.position.y, true)
                if (sg.clampingScroll) return
                if (sg.studio.focused === region) sg.studio.followScroll(region)
            }
            onMovementStarted: {
                sg.scrollMode = "drag"
                sg.syncingScroll = true
                scrollS.to = grid.contentY
                scrollS.jump(grid.contentY)
                sg.syncingScroll = false
                sg.studio.quiet(350)
            }
            onMovementEnded: {
                if (sg.scrollMode === "drag") sg.scrollMode = "idle"
                if (sg.studio.focused === region) region.syncVisibleFocus()
            }
            delegate: Item {
                id: tile
                required property int index
                readonly property var it: sg.list[index] || null
                readonly property string state_: it ? sg.stateOf(it) : ""
                width: grid.cellWidth; height: grid.cellHeight
                RoundImage {
                    width: sg.tileW; height: sg.tileH
                    radius: sg.d(14)
                    mask: tileMask
                    fill: C.alpha(sg.lk.surfaceHigh, 0.5)
                    shadowBlur: sg.d(14)
                    source: tile.it && sg.thumbOf(tile.it) ? "file://" + sg.thumbOf(tile.it) : ""
                }
                Row {       // its badges (the screens it's on)
                    x: sg.d(8); y: sg.d(8)
                    spacing: sg.d(4)
                    Repeater {
                        model: tile.it ? sg.badgesOf(tile.it) : []
                        Rectangle {
                            required property var modelData
                            width: bt.width + sg.d(14); height: sg.d(19); radius: sg.d(6)
                            color: C.alpha(sg.lk.surfaceLowest, 0.78)
                            Text { id: bt; anchors.centerIn: parent; text: modelData; color: sg.lk.fg; font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: sg.d(11) }
                        }
                    }
                }
                Rectangle {     // its colour (the accent it would give)
                    readonly property string c: tile.it ? sg.dotOf(tile.it) : ""
                    visible: c !== ""
                    x: sg.tileW - width - sg.d(10); y: sg.tileH - height - sg.d(10)
                    width: sg.d(14); height: width; radius: width / 2
                    color: c || "transparent"
                    border.width: sg.d(2); border.color: Qt.rgba(0, 0, 0, 0.35)
                }
                Rectangle {     // its state: on its way, or in
                    visible: tile.state_ !== ""
                    x: sg.tileW - width - sg.d(8); y: sg.d(8)
                    width: stT.width + sg.d(18); height: sg.d(24); radius: sg.d(8)
                    color: tile.state_ === "done" ? sg.lk.primary : C.alpha(sg.lk.surfaceLowest, 0.82)
                    Row {
                        id: stT
                        anchors.centerIn: parent
                        spacing: sg.d(4)
                        Text { anchors.verticalCenter: parent.verticalCenter; text: tile.state_ === "done" ? "check" : "downloading"; color: tile.state_ === "done" ? sg.lk.surfaceLowest : sg.lk.fg; font.family: Tokens.font.icons; font.pixelSize: sg.d(15) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: tile.state_ === "done" ? "Added" : "Adding…"; color: tile.state_ === "done" ? sg.lk.surfaceLowest : sg.lk.fg; font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: sg.d(11.5) }
                    }
                }
                // click-only MouseArea inside contentItem so GridView's native click-and-drag scrolling still steals drags
                // (hover is handled strictly by inputLayer in viewport coords so cached off-screen rows never steal hover)
                MouseArea {
                    width: sg.tileW; height: sg.tileH
                    hoverEnabled: false
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: m => {
                        if (m.button !== Qt.LeftButton) return
                        const p = mapToItem(grid, m.x, m.y)
                        if (p.y < 0 || p.y >= grid.height) return
                        sg.studio.pointedTile(region, tile.index, true)
                        if (tile.it) sg.activated(tile.it)
                    }
                }
            }
        }
        Spring {
            id: scrollS
            stiffness: 22
            epsilon: 0.25
            onValueChanged: {
                if (sg.syncingScroll) return
                const clamped = Math.max(0, Math.min(sg.maxScrollY(), value))
                sg.syncingScroll = true
                grid.contentY = clamped
                sg.syncingScroll = false
                if (sg.scrollMode === "wheel" && Math.abs(to - value) < sg.tileH * 0.35 && sg.studio.focused === region) {
                    region.syncVisibleFocus()
                }
            }
            onMovingChanged: {
                if (!moving) {
                    const wasWheel = sg.scrollMode === "wheel"
                    if (sg.scrollMode !== "drag") sg.scrollMode = "idle"
                    if (wasWheel && sg.studio.focused === region) region.syncVisibleFocus()
                }
            }
        }
    }
    // hover and wheel in viewport coordinates (outside GridView so Flickable never reparents handlers into
    // contentItem, never hits off-screen cacheBuffer delegates, and never blocks native click-and-drag on GridView)
    Item {
        id: inputLayer
        x: 0
        y: grid.y
        width: sg.width
        height: grid.height
        HoverHandler {
            id: gridHover
            cursorShape: sg.hoverIdx >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
            onPointChanged: {
                sg.studio.notePointer(point.scenePosition)
                const i = sg.tileAtGrid(point.position.x, point.position.y, true)
                sg.hoverIdx = i
                if (i >= 0) sg.studio.pointedTile(region, i)
            }
            onHoveredChanged: if (!hovered) sg.hoverIdx = -1
        }
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: ev => {
                const isPad = ev.device && ev.device.type === PointerDevice.TouchPad && Math.abs(ev.angleDelta.y) < 120
                const dy = (isPad && ev.pixelDelta.y) ? ev.pixelDelta.y * 1.4
                         : (ev.angleDelta.y ? ev.angleDelta.y / 120 * sg.d(320) : ev.pixelDelta.y)
                sg.wheel(dy)
                ev.accepted = true
            }
        }
    }

    // the grid as one place for the focus
    Focusable {
        id: region
        studio: sg.studio
        anchors.fill: view
        region: true
        mouse: false
        fkey: sg.fkey
        lensRadius: sg.d(14)
        readonly property var w: sg.list[sg.index] || null
        tag: w ? sg.tagOf(w) : ""
        desc: w ? sg.descOf(w) : ""
        act: sg.act
        onActivated: if (w) sg.activated(w)
        function current() { return w }
        function pick(i, revealIfClipped) {
            if (i < 0 || i >= sg.list.length) return
            if (revealIfClipped && !sg.isTileSafe(i)) reveal(i, true)
            if (i !== sg.index) sg.moved(i)
        }
        function rowOf(i) { return sg.rowOf(i) }
        // keep the tile in sight, moving as little as can be (the row above or below peeks in);
        // same spring stiffness as the lens so rapid repeats keep full velocity and never fall off-screen
        function reveal(i, animate) {
            if (!sg.list.length || grid.height <= 0) return
            const r = rowOf(i), top = r * sg.cellH, h = grid.height, maxY = sg.maxScrollY()
            let t = scrollS.moving ? scrollS.to : grid.contentY
            if (top < t + sg.d(4)) t = top - (r > 0 ? sg.cellH * 0.25 : 0)
            else if (top + sg.tileH > t + h - sg.d(60)) t = top + sg.tileH - h + sg.d(60) + sg.cellH * 0.25
            t = Math.max(0, Math.min(maxY, t))
            if (!animate) {
                sg.scrollMode = "idle"
                sg.syncingScroll = true
                sg.clampingScroll = true
                scrollS.to = t
                scrollS.jump(t)
                grid.contentY = t
                sg.clampingScroll = false
                sg.syncingScroll = false
                return
            }
            sg.scrollMode = "reveal"
            if (!scrollS.moving && Math.abs(scrollS.value - grid.contentY) > 0.5) {
                sg.syncingScroll = true
                scrollS.jump(grid.contentY)
                sg.syncingScroll = false
            }
            // under sustained fast key/pad repeat, never let scroll lag more than ~1 row behind the focused tile
            let cur = scrollS.value
            if (top + sg.tileH > cur + h + sg.cellH * 0.85) cur = Math.min(maxY, top + sg.tileH - (h - sg.d(36)))
            else if (top < cur - sg.cellH * 0.85) cur = Math.max(0, top - sg.d(4))
            if (Math.abs(cur - scrollS.value) > 0.5) {
                sg.syncingScroll = true
                sg.clampingScroll = true
                scrollS.value = cur
                grid.contentY = cur
                sg.clampingScroll = false
                sg.syncingScroll = false
            }
            scrollS.to = t
            if (!scrollS.moving) sg.scrollMode = "idle"
        }
        function nearestVisibleIndex(fromIdx) {
            const maxRow = rowOf(sg.list.length - 1)
            const atBottom = grid.contentY + grid.height >= grid.contentHeight - 1
            const botMargin = atBottom ? sg.d(10) : sg.d(36)
            let firstRow = Math.max(0, Math.ceil((grid.contentY - sg.d(2)) / sg.cellH))
            let lastRow = Math.min(maxRow, Math.floor((grid.contentY + grid.height - botMargin - sg.tileH) / sg.cellH))
            if (lastRow < firstRow) {
                const mid = Math.max(0, Math.min(maxRow, Math.floor((grid.contentY + grid.height * 0.5) / sg.cellH)))
                firstRow = mid
                lastRow = mid
            }
            const col = fromIdx % sg.cols
            const r = Math.max(firstRow, Math.min(lastRow, rowOf(fromIdx)))
            return Math.min(sg.list.length - 1, r * sg.cols + col)
        }
        // once wheel or drag scrolling settles, never leave focus on an invisible off-screen tile
        function syncVisibleFocus() {
            if (!sg.list.length || grid.height <= 0) return
            const under = gridHover.hovered ? sg.tileAtGrid(gridHover.point.position.x, gridHover.point.position.y, true) : -1
            if (under >= 0) {
                if (under !== sg.index) sg.moved(under)
                return
            }
            if (sg.isTileSafe(sg.index)) return
            const ni = nearestVisibleIndex(sg.index)
            if (ni !== sg.index) sg.moved(ni)
        }
        function setIndex(i, animate) {
            if (!sg.list.length) return
            i = Math.max(0, Math.min(sg.list.length - 1, i))
            reveal(i, animate)
            sg.moved(i)
        }
        function step(dx, dy) {
            const n = sg.list.length, c = sg.cols
            if (!n) return false
            if (!sg.isTileSafe(sg.index) && sg.scrollMode !== "reveal") {
                const vis = nearestVisibleIndex(sg.index)
                if (vis !== sg.index) { setIndex(vis, true); return true }
            }
            const i = sg.index
            if (dx) {
                const col = i % c
                if ((dx < 0 && col === 0) || (dx > 0 && (col === c - 1 || i >= n - 1))) return false
                setIndex(i + dx, true); return true
            }
            const ni = i + dy * c
            if (ni < 0) return false
            if (ni >= n) { if (rowOf(n - 1) > rowOf(i)) { setIndex(n - 1, true); return true } return false }
            setIndex(ni, true); return true
        }
        // coming in from elsewhere: from above, the tile under where the focus was in the first row in sight;
        // otherwise where it was
        function enterFrom(r, dx, dy) {
            if (dy > 0 && sg.list.length) {
                const row = Math.ceil((grid.contentY - sg.d(4)) / sg.cellH), p = mapFromItem(sg.studio, r.x + r.width / 2, 0)
                const col = Math.max(0, Math.min(sg.cols - 1, Math.floor((p.x - sg.d(12)) / (sg.tileW + sg.gap))))
                setIndex(Math.min(sg.list.length - 1, Math.max(0, row) * sg.cols + col), true)
            } else reveal(sg.index, true)
        }
        function lensClipRect() {
            return view.mapToItem(sg.studio, 0, 0, view.width, view.height)
        }
        function lensRect() {
            if (!sg.list.length) return null
            const i = sg.index, x = (i % sg.cols) * (sg.tileW + sg.gap), y = rowOf(i) * sg.cellH - grid.contentY
            return grid.mapToItem(sg.studio, x, y, sg.tileW, sg.tileH)
        }
        Component.onCompleted: revealSoon.restart()
    }
    // the list arrives after the page (or a new one replaces it): the grid goes to the focused one
    Timer { id: revealSoon; interval: 0; onTriggered: { region.reveal(sg.index, false); if (sg.studio.focused === region) sg.studio.relens(true) } }
    property int lastCount: 0
    onListChanged: if (list.length !== lastCount) { lastCount = list.length; revealSoon.restart() }
    function toTop() {
        sg.scrollMode = "idle"
        sg.syncingScroll = true
        sg.clampingScroll = true
        scrollS.to = 0
        scrollS.jump(0)
        grid.contentY = 0
        sg.clampingScroll = false
        sg.syncingScroll = false
        revealSoon.restart()
    }
    function wheel(dy) {
        const maxY = sg.maxScrollY()
        if (maxY <= 0) return
        const base = scrollS.moving ? scrollS.to : grid.contentY
        const target = Math.max(0, Math.min(maxY, base - dy))
        sg.scrollMode = "wheel"
        if (!scrollS.moving && Math.abs(scrollS.value - grid.contentY) > 0.5) {
            sg.syncingScroll = true
            scrollS.jump(grid.contentY)
            sg.syncingScroll = false
        }
        scrollS.to = target
        if (!scrollS.moving) sg.scrollMode = "idle"
        sg.studio.quiet(320)
    }
}
