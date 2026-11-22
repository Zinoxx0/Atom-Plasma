import QtQuick
import org.kde.kirigami as Kirigami
import Rice

// Atom's Home: the atom of what you use. Pinned (your pins) inside, Play (games with their art, the launchers) in the
// middle, Recent (what you used lately, then the most used) outside; the focus's caption on the left. HomeModel (the
// launcher's shared data) feeds it. Its rings are docks (AtomView.dock: the focus big, its neighbours making room).
Item {
    id: page
    required property var stage
    anchors.fill: parent

    // HomeModel's Home page as rings
    function asItem(a) {
        const art = a.art && a.art.portrait ? a.art : null
        return { key: a.key, name: a.name, desc: a.desc, icon: a.icon, art: art ? art.portrait : "", hero: art ? art.hero : "",
                 logo: art ? art.logo : "", big: art ? 104 : 0, model: a.model, row: a.row, roles: a.roles, last: a.last, game: a.game }
    }
    readonly property var shells: {
        page.stage.home.rev
        const rows = ((page.stage.home.pages[0] || {}).rows) || []
        const byId = id => rows.find(r => r.id === id)
        const jump = byId("jump"), games = byId("games"), tools = byId("tools"), most = byId("most")
        const cut = jump ? (jump.divider >= 0 ? jump.divider : jump.items.length) : 0
        const pins = jump ? jump.items.slice(0, cut) : []
        const recent = jump ? jump.items.slice(cut) : []
        const seen = new Set()
        const uniq = list => list.filter(a => !seen.has(a.key) && seen.add(a.key))
        const out = []
        const add = (name, list, radius, size) => { const items = uniq(list).map(page.asItem); if (items.length) out.push({ name, items, radius, size, window: 16 }) }
        add("Pinned", pins, 236, 66)
        add("Play", (games ? games.items : []).concat(tools ? tools.items : []), 384, 62)
        add("Recent", recent.concat(most ? most.items : []), 530, 58)
        return out
    }

    AtomView {
        id: atom
        stage: page.stage
        shells: page.shells
        dock: true
        tint: page.tint
        onLaunched: it => page.stage.launch(it)
        onOptions: (it, dl) => { if (it && it.model && dl) page.stage.launcher.menu.openFor(dl, it.model, it.row) }
    }

    // the focus's colour, off its icon (or a game's art)
    ImagePalette { id: colours; source: atom.focusItem ? (atom.focusItem.art || atom.focusItem.icon) : "" }
    readonly property color tint: C.appTint(colours, page.stage.look.primary)

    // what the stage shows for the focus: the caption, the scene's light and art
    function ago(t) {
        if (!t) return "Not yet"
        const s = Date.now() / 1000 - t
        if (s < 3600) return "Just now"
        if (s < 86400) return Math.floor(s / 3600) + " h ago"
        if (s < 2 * 86400) return "Yesterday"
        if (s < 7 * 86400) return Math.floor(s / 86400) + " days ago"
        return Qt.formatDate(new Date(t * 1000), "MMM d")
    }
    readonly property var caption: {
        const it = atom.focusItem, r = atom.ring
        if (!it || !r) return { where: ["Home"], name: "Nothing here yet", desc: "Pin apps from the Apps page" }
        return { where: [r.name, (r.focusIndex + 1) + " of " + r.items.length], name: it.name, logo: it.logo || "",
                 desc: it.desc, facts: it.game ? [[page.ago(it.last), "last played"]] : [[page.ago(it.last), "last opened"]],
                 acts: [["A", it.game ? "Play" : "Open"], ["X", "Options"]] }
    }
    function publish() {
        if (!page.visible || !page.stage) return
        page.stage.caption = page.caption
        page.stage.focusItem = atom.focusItem ? { hero: atom.focusItem.hero || "" } : null
        page.stage.focusTint = page.tint
    }
    onCaptionChanged: publish()
    onTintChanged: publish()
    onVisibleChanged: if (visible) { install(); publish() }
    Component.onCompleted: { install(); publish() }
    function install() {
        if (!page.stage) return
        page.stage.pageApi = {
            act: i => i === 0 ? atom.launch() : atom.openOptions(),
            wheel: (dy, at) => atom.wheelAt(dy > 0 ? -1 : 1, at),
        }
        page.stage.hints = {
            pad: [["↕", "Turn"], ["↔", "Ring"], ["A", "Open"], ["X", "Options"], ["LB RB", "Pages"], ["Y", "Theme"], ["B", "Close"]],
            keys: [["↑ ↓", "Turn"], ["← →", "Ring"], ["Enter", "Open"], ["Menu", "Options"], ["Tab", "Pages"], ["Esc", "Close"]],
        }
    }
    Connections {
        target: page.stage
        enabled: page.visible
        function onPageKey(event) {
            const k = event.key
            if (k === Qt.Key_Up) atom.turn(-1)
            else if (k === Qt.Key_Down) atom.turn(1)
            else if (k === Qt.Key_Left) atom.hop(1)
            else if (k === Qt.Key_Right) atom.hop(-1)
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) atom.launch()
            else if (k === Qt.Key_Menu) atom.openOptions()
            else return
            event.accepted = true
        }
    }
}
