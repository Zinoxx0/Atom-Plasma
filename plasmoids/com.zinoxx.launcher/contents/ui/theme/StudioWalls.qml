import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import Atom
import Rice

// The Theme page's Wallpapers: mood chips (All, then each mood the theme engine reads, with counts) over a grid of
// every wallpaper, sorted by the accent each one would give (a dot in its corner says which), badged with the screens
// it's on. The grid is one place for the focus that walks itself (Focusable region): the keys move a tile at a time
// and the grid scrolls to keep it in sight; the pointer picks the tile it rests on (nothing scrolls under it).
Item {
    id: wv
    required property Item studio
    readonly property var lk: studio.look
    function d(px) { return studio.d(px) }
    readonly property var list: studio.shownWalls

    Row {
        id: chips
        spacing: wv.d(10)
        Repeater {
            model: wv.studio.moodChips
            StudioChip {
                required property var modelData
                studio: wv.studio
                fkey: "flt:" + modelData.id
                text: modelData.name
                count: String(modelData.count)
                chosen: wv.studio.filter === modelData.id
                desc: "<b>" + modelData.name + "</b> " + (modelData.id === "all" ? "Every wallpaper, by the accent it gives." : "The wallpapers the theme engine reads as " + modelData.id + ".")
                act: "Show"
                onActivated: wv.studio.setFilter(modelData.id)
            }
        }
    }

    // ---------------------------------------------------------------- the grid
    readonly property real gap: d(18)
    readonly property int cols: Math.max(3, Math.round((width + gap) / (d(244) + gap)))
    readonly property real tileW: (width - gap * (cols - 1)) / cols
    readonly property real tileH: tileW * 9 / 16
    readonly property real cellH: tileH + gap
    Rectangle { id: tileMask; width: wv.tileW; height: wv.tileH; radius: wv.d(14); visible: false; layer.enabled: true }    // (every tile's corners)
    Item {
        id: view
        y: chips.height + wv.d(24)
        x: -wv.d(12)
        width: wv.width + wv.d(24)
        height: wv.height - y
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
                GradientStop { position: Math.min(0.3, wv.d(14) / Math.max(1, view.height)); color: "black" }
                GradientStop { position: Math.max(0.7, 1 - wv.d(70) / Math.max(1, view.height)); color: "black" }
                GradientStop { position: 1; color: grid.contentY + grid.height < grid.contentHeight - 1 ? "transparent" : "black" }
            }
        }
        GridView {
            id: grid
            x: wv.d(12)
            y: wv.d(10)
            width: wv.width + wv.gap
            height: parent.height - y
            cellWidth: wv.tileW + wv.gap
            cellHeight: wv.cellH
            model: wv.list.length
            reuseItems: true
            cacheBuffer: Math.round(wv.cellH * 2)
            boundsBehavior: Flickable.StopAtBounds
            onContentYChanged: wv.studio.relens()
            onMovementStarted: { scroll.stop(); wv.studio.quiet() }
            delegate: Item {
                id: tile
                required property int index
                readonly property var w: wv.list[index] || null
                width: grid.cellWidth; height: grid.cellHeight
                RoundImage {
                    width: wv.tileW; height: wv.tileH
                    radius: wv.d(14)
                    mask: tileMask
                    fill: C.alpha(wv.lk.surfaceHigh, 0.5)
                    shadowBlur: wv.d(14)
                    source: tile.w ? "file://" + tile.w.thumb : ""
                }
                Row {       // the screens it's on
                    x: wv.d(8); y: wv.d(8)
                    spacing: wv.d(4)
                    Repeater {
                        model: tile.w ? wv.studio.screensOn(tile.w.file) : []
                        Rectangle {
                            required property var modelData
                            width: bt.width + wv.d(14); height: wv.d(19); radius: wv.d(6)
                            color: C.alpha(wv.lk.surfaceLowest, 0.78)
                            Text { id: bt; anchors.centerIn: parent; text: modelData; color: wv.lk.fg; font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: wv.d(11) }
                        }
                    }
                }
                Rectangle {     // the accent it would give
                    visible: !!(tile.w && tile.w.accent)
                    x: wv.tileW - width - wv.d(10); y: wv.tileH - height - wv.d(10)
                    width: wv.d(14); height: width; radius: width / 2
                    color: tile.w && tile.w.accent ? tile.w.accent : "transparent"
                    border.width: wv.d(2); border.color: Qt.rgba(0, 0, 0, 0.35)
                }
                MouseArea {
                    width: wv.tileW; height: wv.tileH
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onEntered: wv.studio.pointedTile(region, tile.index)
                    onPositionChanged: wv.studio.pointedTile(region, tile.index)
                    onClicked: m => { if (m.button === Qt.LeftButton) { wv.studio.pointedTile(region, tile.index, true); wv.studio.applyWall(tile.w) } }
                }
            }
        }
        NumberAnimation { id: scroll; target: grid; property: "contentY"; duration: Tokens.ms(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove }
    }

    // the grid as one place for the focus
    Focusable {
        id: region
        studio: wv.studio
        x: view.x; y: view.y
        width: view.width; height: view.height
        region: true
        mouse: false
        fkey: "walls:grid"
        lensRadius: wv.d(14)
        readonly property var w: wv.list[wv.studio.wallIndex] || null
        tag: w ? w.name : ""
        desc: w ? "<b>" + w.name + "</b> " + (w.mood ? w.mood + " mood · " : "") + "A sets it on " + wv.studio.targetLabel : ""
        act: "Set on " + wv.studio.targetLabel
        onActivated: wv.studio.applyWall(w)
        function current() { return w }
        function rowOf(i) { return Math.floor(i / wv.cols) }
        // keep the tile in sight, moving as little as can be (the row above or below peeks in)
        function reveal(i, animate) {
            const top = rowOf(i) * wv.cellH, ch = grid.contentHeight, h = grid.height
            let t = grid.contentY
            if (top < t + wv.d(4)) t = top - (rowOf(i) > 0 ? wv.cellH * 0.25 : 0)
            else if (top + wv.tileH > t + h - wv.d(60)) t = top + wv.tileH - h + wv.d(60) + wv.cellH * 0.25
            t = Math.max(0, Math.min(Math.max(0, ch - h), t))
            if (Math.abs(t - grid.contentY) < 0.5) return
            scroll.stop()
            if (animate) { scroll.from = grid.contentY; scroll.to = t; scroll.start() } else grid.contentY = t
        }
        function setIndex(i, animate) { wv.studio.setWallIndex(Math.max(0, Math.min(wv.list.length - 1, i))); reveal(wv.studio.wallIndex, animate) }
        function step(dx, dy) {
            const n = wv.list.length, c = wv.cols, i = wv.studio.wallIndex
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
        // otherwise where it was (or the wallpaper in use)
        function enterFrom(r, dx, dy) {
            if (dy > 0) {
                const row = Math.ceil((grid.contentY - wv.d(4)) / wv.cellH), p = mapFromItem(wv.studio, r.x + r.width / 2, 0)
                const col = Math.max(0, Math.min(wv.cols - 1, Math.floor((p.x - wv.d(12)) / (wv.tileW + wv.gap))))
                setIndex(Math.min(wv.list.length - 1, Math.max(0, row) * wv.cols + col), true)
            } else reveal(wv.studio.wallIndex, true)
        }
        function lensRect() {
            const i = wv.studio.wallIndex, x = (i % wv.cols) * (wv.tileW + wv.gap), y = rowOf(i) * wv.cellH - grid.contentY
            return grid.mapToItem(wv.studio, x, y, wv.tileW, wv.tileH)
        }
        Component.onCompleted: Qt.callLater(() => reveal(wv.studio.wallIndex, false))
    }
    // the list arrives after the page (rice.py page): the grid goes to the focused one once it's there
    property bool revealed: false
    onListChanged: if (!revealed && list.length) { revealed = true; Qt.callLater(() => { region.reveal(wv.studio.wallIndex, false); wv.studio.relens(true) }) }
    Connections { target: wv.studio; function onWallsFiltered() { scroll.stop(); grid.contentY = 0; Qt.callLater(() => region.reveal(wv.studio.wallIndex, false)) } }
    function wheel(dy) { scroll.stop(); grid.contentY = Math.max(0, Math.min(Math.max(0, grid.contentHeight - grid.height), grid.contentY - dy)); studio.quiet() }
}
