import QtQuick
import org.kde.kirigami as Kirigami
import "Rice"
import "Rice/Color.js" as C

// A theme's screens as it was saved: each monitor at its real place and shape (a portrait one stays tall),
// filled with its wallpaper, fitted into a fixed box so every theme chip has the same footprint whatever
// the setup. Too many screens to read (more than `maxTiles`, or a tile under `minTile` px wide) show the
// main one with a count.
Item {
    id: lg
    required property RicePalette pal
    property var layout: []                 // [{x, y, w, h, thumb, main}]
    property real minTile: 3
    property int maxTiles: 5
    implicitWidth: 44
    implicitHeight: 18

    readonly property real minX: layout.length ? Math.min(...layout.map(e => e.x)) : 0
    readonly property real minY: layout.length ? Math.min(...layout.map(e => e.y)) : 0
    readonly property real spanW: layout.length ? Math.max(...layout.map(e => e.x + e.w)) - minX : 1
    readonly property real spanH: layout.length ? Math.max(...layout.map(e => e.y + e.h)) - minY : 1
    readonly property real k: Math.min(width / Math.max(1, spanW), height / Math.max(1, spanH))
    readonly property real ox: (width - spanW * k) / 2
    readonly property real oy: (height - spanH * k) / 2
    readonly property bool crowded: layout.length > maxTiles || layout.some(e => e.w * k - 1.5 < minTile)
    readonly property var main: layout.find(e => e.main) ?? layout[0]

    Repeater {
        model: lg.crowded ? [] : lg.layout
        Kirigami.ShadowedImage {
            required property var modelData
            x: lg.ox + (modelData.x - lg.minX) * lg.k + 0.75
            y: lg.oy + (modelData.y - lg.minY) * lg.k + 0.75
            width: Math.max(2, modelData.w * lg.k - 1.5)
            height: Math.max(2, modelData.h * lg.k - 1.5)
            radius: 2.5
            color: C.alpha(lg.pal.fg, 0.12)
            border.width: 1
            border.color: C.alpha(lg.pal.edge, 0.18)
            source: modelData.thumb ? "file://" + modelData.thumb : ""
            sourceSize.width: 96
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }
    Kirigami.ShadowedImage {        // crowded: the main screen, with how many there were
        visible: lg.crowded && !!lg.main
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 28; height: lg.height
        radius: 3
        color: C.alpha(lg.pal.fg, 0.12)
        source: lg.main && lg.main.thumb ? "file://" + lg.main.thumb : ""
        sourceSize.width: 96
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    Text {
        visible: lg.crowded
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "×" + lg.layout.length
        color: lg.pal.fgDim
        font.family: Tokens.font.ui
        font.weight: Font.DemiBold
        font.pixelSize: Tokens.size.caption
    }
}
