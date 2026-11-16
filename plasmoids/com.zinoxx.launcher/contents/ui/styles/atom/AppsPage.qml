import QtQuick
import org.kde.kirigami as Kirigami
import Rice

// Atom's Apps: every app. The outer ring is the categories (All, then the menu's: a glyph and a name each), the middle
// one that category's apps (16 at a time: the rest come round through the gap), the inner one what the app in focus can
// do (Open, its own actions from its .desktop file, Pin or Unpin). Turning the categories changes the apps once it
// rests (the old ones fall into the core, the new ones spiral out); in All, LT/RT (PageUp/PageDown) jump a letter.
Item {
    id: page
    required property var stage
    anchors.fill: parent
    readonly property var lc: page.stage ? page.stage.launcher : null

    // the categories (the launcher's; Recent is Home's)
    readonly property var cats: {
        if (!page.lc) return []
        const out = []
        for (const c of page.lc.categories) if (c.label !== "Recent") out.push({ name: c.label === "All" ? "All apps" : c.label, glyph: c.icon, label: c.label, model: c.model })
        return out
    }
    property int cat: 0
    property var apps: []
    // a category's apps, read through delegates (Kicker's models are lists of rows)
    Repeater {
        id: rows
        model: page.cats[page.cat] ? page.cats[page.cat].model : null
        delegate: Item {
            required property var model
            required property int index
            readonly property var entry: ({ key: String(model.favoriteId || model.display || ""), name: String(model.display || ""), desc: String(model.description || ""),
                                            icon: model.decoration, model: rows.model, row: index, roles: model })
        }
        onCountChanged: settle.restart()
    }
    Timer { id: settle; interval: 60; onTriggered: page.collect() }
    function collect() {
        const out = []
        for (let i = 0; i < rows.count; i++) { const r = rows.itemAt(i); if (r && r.entry.name) out.push(r.entry) }
        out.sort((a, b) => a.name.localeCompare(b.name))
        page.apps = out
    }
    // the app the actions are for: the one at the apps ring's focus (kept while the focus is on the actions)
    readonly property var app: { const r = atom.ringAt(1); return r ? r.focusItem : null }
    property var actions: []
    function actionsOf(a) {
        if (!a) return []
        const out = [{ name: "Open", glyph: "open_in_new", label: "Open", open: true }]
        for (const x of ((a.roles && a.roles.actionList) || [])) {
            if (x.actionId !== "_kicker_jumpListAction") continue     // the app's own (its .desktop actions); Plasma's are in the menu (X)
            out.push({ name: x.text, glyph: "bolt", label: x.text.length > 16 ? x.text.slice(0, 15) + "…" : x.text, act: x })
            if (out.length >= 6) break
        }
        const fav = a.roles && a.roles.favoriteId, pinned = fav && page.lc.isFavorite(fav)
        if (fav) out.push({ name: pinned ? "Unpin from Home" : "Pin to Home", glyph: "push_pin", label: pinned ? "Unpin" : "Pin", fav: fav })
        return out
    }
    Timer { id: actSettle; interval: 260; onTriggered: page.actions = page.actionsOf(page.app) }    // the inner ring follows the app, quietly
    onAppChanged: actSettle.restart()

    AtomView {
        id: atom
        stage: page.stage
        shells: [{ name: "Actions", items: page.actions, radius: 236, size: 52, window: 16 },
                 { name: page.cats[page.cat] ? page.cats[page.cat].label : "Apps", items: page.apps, radius: 384, size: 62, window: 19 },
                 { name: "Categories", items: page.cats, radius: 540, size: 64, window: 16 }]
        tint: page.tint
        Component.onCompleted: at = 1
        onLaunched: it => page.activate(it)
        onOptions: (it, dl) => { if (it && it.model && dl) page.stage.launcher.menu.openFor(dl, it.model, it.row) }
    }
    function activate(it) {
        if (!it) return
        if (atom.at === 2) { page.cat = page.cats.indexOf(it); atom.at = 1; return }          // a category: its apps
        if (atom.at === 1) { page.stage.launch(it); return }
        const a = page.apps.find(x => x.key === (page.app && page.app.key)) || page.app       // an action on the app in focus
        if (!a) return
        if (it.open) page.stage.launch(a)
        else if (it.fav) { page.lc.toggleFavorite(it.fav); page.actions = page.actionsOf(a) }
        else if (it.act) { a.model.trigger(a.row, it.act.actionId, it.act.actionArgument); page.lc.close() }
    }
    // the categories ring: the apps change once it rests on one
    Connections { target: atom; function onFocusItemChanged() { if (atom.at === 2) catSettle.restart() } }
    Timer { id: catSettle; interval: 380; onTriggered: { const i = page.cats.indexOf(atom.focusItem); if (i >= 0) page.cat = i } }
    onCatChanged: settle.restart()

    Kirigami.ImageColors { id: colours; source: atom.focusItem && atom.at === 1 ? atom.focusItem.icon : "" }
    Connections { target: atom; function onFocusItemChanged() { colours.update() } }
    readonly property color tint: C.appTint(colours, page.stage ? page.stage.look.primary : "#888888")

    readonly property var caption: {
        const it = atom.focusItem, r = atom.ring
        if (!it || !r) return { where: ["Apps"], name: "Apps" }
        if (atom.at === 2) return { where: ["Categories", (r.focusIndex + 1) + " of " + r.items.length], name: it.name,
            desc: (it.model ? it.model.count : 0) + " apps", acts: [["A", "Show"]] }
        if (atom.at === 0) return { where: [page.app ? page.app.name : "", (r.focusIndex + 1) + " of " + r.items.length], name: it.name, acts: [["A", it.open ? "Open" : it.fav ? (it.label) : "Run"]] }
        const letter = page.cat === 0 ? [it.name.charAt(0).toUpperCase()] : []
        return { where: [r.name === "All" ? "All apps" : r.name, (r.focusIndex + 1) + " of " + r.items.length].concat(letter), name: it.name, desc: it.desc,
                 acts: [["A", "Open"], ["X", "Options"]] }
    }
    function publish() { if (!page.stage) return; page.stage.caption = page.caption; page.stage.focusItem = null; page.stage.focusTint = page.tint }
    onCaptionChanged: publish()
    onTintChanged: publish()
    Component.onCompleted: {
        if (!page.stage) return
        page.stage.pageApi = { act: i => i === 0 ? atom.launch() : atom.openOptions(), wheel: dy => atom.turn(dy > 0 ? -1 : 1) }
        page.stage.hints = { pad: [["↕", "Turn"], ["↔", "Ring"], ["LT RT", "Letter"], ["A", "Open"], ["X", "Options"], ["LB RB", "Pages"], ["B", "Close"]],
                             keys: [["↑ ↓", "Turn"], ["← →", "Ring"], ["PgUp PgDn", "Letter"], ["Enter", "Open"], ["Tab", "Pages"], ["Esc", "Close"]] }
        publish()
    }
    function letter(dd) {          // the next (or previous) first letter on the apps ring
        const r = atom.ring
        if (atom.at !== 1 || !r || !r.items.length) return
        const n = r.items.length, Lt = i => r.items[i].name.charAt(0).toUpperCase()
        let j = r.focusIndex; const here = Lt(j)
        do j = (j + dd + n) % n; while (Lt(j) === here && j !== r.focusIndex)
        if (dd < 0) while (Lt((j - 1 + n) % n) === Lt(j) && (j - 1 + n) % n !== r.focusIndex) j = (j - 1 + n) % n
        r.picked = -1; atom.mode = "slot"; r.current = j
    }
    Connections {
        target: page.stage
        function onPageKey(event) {
            const k = event.key
            if (k === Qt.Key_Up) atom.turn(-1)
            else if (k === Qt.Key_Down) atom.turn(1)
            else if (k === Qt.Key_Left) atom.hop(1)
            else if (k === Qt.Key_Right) atom.hop(-1)
            else if (k === Qt.Key_PageDown) page.letter(1)
            else if (k === Qt.Key_PageUp) page.letter(-1)
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) atom.launch()
            else if (k === Qt.Key_Menu) atom.openOptions()
            else return
            event.accepted = true
        }
    }
}
