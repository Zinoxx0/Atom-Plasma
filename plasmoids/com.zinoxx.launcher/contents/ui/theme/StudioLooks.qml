import QtQuick
import org.kde.kirigami as Kirigami
import Atom
import Rice

// The Theme page's Saved looks: each one as its desk in miniature (every screen with the wallpaper it gives it), one
// press loads it (the one in focus previews on the desk map and the page); X or a right click: load, save over,
// delete. Then "This desk", as it is now, to save as a new look (a name card opens at it).
Column {
    id: lc
    required property Item studio
    readonly property var lk: studio.look
    function d(px) { return studio.d(px) }
    readonly property var row: studio.row("looks")
    readonly property var looks: row ? row.items.filter(x => x.kind === "look") : []
    readonly property var save: row ? row.items.find(x => x.kind === "save") : null

    StudioCap { studio: lc.studio; text: "Your looks"; note: lc.looks.length ? "" : "none yet: save this desk below" }
    Item { width: 1; height: lc.d(14) }
    Flow {
        width: lc.studio.mainWidth
        spacing: lc.d(18)
        Repeater {
            model: lc.looks
            StudioCard {
                id: card
                required property var modelData
                studio: lc.studio
                picW: lc.d(400); picH: lc.d(150)
                fkey: "look:" + modelData.name
                name: modelData.name
                note: (modelData.layout || []).length + " screens"
                current: !!modelData.current
                desc: "<b>" + modelData.name + "</b> Every screen's wallpaper and colours, in one step." + (lc.studio.moreKey ? " " + lc.studio.moreKey + " for more." : "")
                act: "Load"
                property var look: modelData
                onActivated: lc.studio.model.apply(modelData)
                onMenu: lc.studio.lookMenu(modelData, card)
                MiniDesk { studio: lc.studio; anchors.fill: parent; thumbs: (card.modelData.preset && card.modelData.preset.thumbs) || {} }
            }
        }
    }
    Item { width: 1; height: lc.d(40) }
    StudioCap { studio: lc.studio; text: "This desk"; note: "as it is now" }
    Item { width: 1; height: lc.d(14) }
    StudioCard {
        id: saveCard
        studio: lc.studio
        picW: lc.d(400); picH: lc.d(150)
        fkey: "save"
        name: "Save this look"
        desc: "<b>Save this look</b> Keep every screen's wallpaper and colours under a short name."
        act: "Save as…"
        onActivated: lc.studio.saveLook(saveCard)
        MiniDesk {
            studio: lc.studio
            anchors.fill: parent
            dim: true
            thumbs: { const o = {}; for (const s of (lc.studio.model.screens || [])) o[s.name] = s.thumb; return o }
            Rectangle {
                anchors.centerIn: parent
                width: lc.d(64); height: width; radius: width / 2
                color: lc.lk.fg
                Text { anchors.centerIn: parent; text: "add"; color: lc.lk.surfaceLowest; font.family: Tokens.font.icons; font.pixelSize: lc.d(34) }
            }
        }
    }
}
