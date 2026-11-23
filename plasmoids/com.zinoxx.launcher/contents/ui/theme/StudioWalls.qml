import QtQuick
import Atom
import Rice

// The Theme page's Wallpapers: mood chips (All, then each mood the theme engine reads, with counts) over a grid of
// every wallpaper (StudioGrid), sorted by the accent each one would give (a dot in its corner says which), badged
// with the screens it's on. A sets the focused one on the screen being edited.
Item {
    id: wv
    required property Item studio
    function d(px) { return studio.d(px) }

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
    StudioGrid {
        id: grid
        studio: wv.studio
        y: chips.height + wv.d(24)
        width: wv.width
        height: wv.height - y
        fkey: "walls:grid"
        list: wv.studio.shownWalls
        index: wv.studio.wallIndex
        act: "Set on " + wv.studio.targetLabel
        badgesOf: function (w) { return wv.studio.screensOn(w.file) }
        dotOf: function (w) { return w.accent || "" }
        descOf: function (w) { return "<b>" + w.name + "</b>" + (w.mood ? " " + w.mood + " mood" : "") + (wv.studio.actKey ? " · " + wv.studio.actKey + " sets it on " + wv.studio.targetLabel : "") }
        onMoved: i => wv.studio.setWallIndex(i)
        onActivated: w => wv.studio.applyWall(w)
    }
    Connections { target: wv.studio; function onWallsFiltered() { grid.toTop() } }
    function wheel(dy) { grid.wheel(dy) }
}
