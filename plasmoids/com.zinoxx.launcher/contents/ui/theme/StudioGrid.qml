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
    Rectangle { id: tileMask; width: sg.tileW; height: sg.tileH; radius: sg.d(14); visible: false; layer.enabled: true }    // (every tile's corners)
    Item {
        id: view
        x: -sg.d(12)
        width: sg.width + sg.d(24)
        height: sg.height
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
            onContentYChanged: sg.studio.relens()
            onMovementStarted: { scroll.stop(); sg.studio.quiet() }
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
                MouseArea {
                    width: sg.tileW; height: sg.tileH
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onEntered: sg.studio.pointedTile(region, tile.index)
                    onPositionChanged: sg.studio.pointedTile(region, tile.index)
                    onClicked: m => { if (m.button === Qt.LeftButton) { sg.studio.pointedTile(region, tile.index, true); if (tile.it) sg.activated(tile.it) } }
                }
            }
        }
        NumberAnimation { id: scroll; target: grid; property: "contentY"; duration: Tokens.ms(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove }
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
        function pick(i) { if (i !== sg.index && i >= 0 && i < sg.list.length) sg.moved(i) }
        function rowOf(i) { return Math.floor(i / sg.cols) }
        // keep the tile in sight, moving as little as can be (the row above or below peeks in)
        function reveal(i, animate) {
            const top = rowOf(i) * sg.cellH, ch = grid.contentHeight, h = grid.height
            let t = grid.contentY
            if (top < t + sg.d(4)) t = top - (rowOf(i) > 0 ? sg.cellH * 0.25 : 0)
            else if (top + sg.tileH > t + h - sg.d(60)) t = top + sg.tileH - h + sg.d(60) + sg.cellH * 0.25
            t = Math.max(0, Math.min(Math.max(0, ch - h), t))
            if (Math.abs(t - grid.contentY) < 0.5) return
            scroll.stop()
            if (animate) { scroll.from = grid.contentY; scroll.to = t; scroll.start() } else grid.contentY = t
        }
        function setIndex(i, animate) { i = Math.max(0, Math.min(sg.list.length - 1, i)); sg.moved(i); reveal(i, animate) }
        function step(dx, dy) {
            const n = sg.list.length, c = sg.cols, i = sg.index
            if (!n) return false
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
        function lensRect() {
            const i = sg.index, x = (i % sg.cols) * (sg.tileW + sg.gap), y = rowOf(i) * sg.cellH - grid.contentY
            return grid.mapToItem(sg.studio, x, y, sg.tileW, sg.tileH)
        }
        Component.onCompleted: revealSoon.restart()
    }
    // the list arrives after the page (or a new one replaces it): the grid goes to the focused one
    Timer { id: revealSoon; interval: 0; onTriggered: { region.reveal(sg.index, false); sg.studio.relens(true) } }
    property int lastCount: 0
    onListChanged: if (list.length !== lastCount) { lastCount = list.length; revealSoon.restart() }
    function toTop() { scroll.stop(); grid.contentY = 0; revealSoon.restart() }
    function wheel(dy) { scroll.stop(); grid.contentY = Math.max(0, Math.min(Math.max(0, grid.contentHeight - grid.height), grid.contentY - dy)); studio.quiet() }
}
