import QtQuick
import QtCore
import "Rice"

// Atom Home's data: every app and game as one kind of item, gathered from the launcher's Kicker models
// (favourites, recents, the menu's categories) and its own file (rice.py launcher-data: Steam's art for
// the games, when each app was last used), then laid out as pages of rows:
//   Home    your pins (their own order: muscle memory) then what you used lately · Games · Most used
//   Games   the library's covers · launchers and tools
//   Apps    a row per category
// An item: { key, id, name, desc, icon, favId, url, art: {portrait, hero, logo}, game, last, score,
//            model, row, roles } (model/row launch it; roles carry favoriteId and actionList for the menu)
// A row: { id, title, shape: "square" | "portrait" | "poster", items, divider, labeled, count }
Item {
    id: hm
    required property var launcher      // main.qml: favorites, categories
    visible: false

    property var pages: []
    property int rev: 0                 // bumps whenever the pages are rebuilt
    readonly property string home: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "")
    WatchedJson { id: data; path: hm.home + "/.cache/rice/launcher.json"; onChanged: hm.schedule() }

    // Kicker's roles are read by name through a delegate (their numbers are Kicker's private enum)
    component Harvest: Instantiator {
        signal changed()
        delegate: QtObject {
            required property var model
            required property int index
        }
        onObjectAdded: changed()
        onObjectRemoved: changed()
        function read() {
            const out = []
            for (let i = 0; i < count; i++) { const o = objectAt(i); if (o) out.push(o) }
            return out
        }
    }
    Harvest { id: favs; model: hm.launcher.favorites; onChanged: hm.schedule() }
    // one per category of the menu (All, Recent, then the menu's own)
    Instantiator {
        id: cats
        model: hm.launcher.categories
        delegate: Harvest {
            required property var modelData
            model: modelData.model
            onChanged: hm.schedule()
        }
        onObjectAdded: hm.schedule()
        onObjectRemoved: hm.schedule()
    }

    function schedule() { if (!timer.running) timer.start() }
    Timer { id: timer; interval: 60; onTriggered: hm.rebuild() }

    // a desktop file id from Kicker's favoriteId ("applications:x.desktop", "x.desktop") or its url
    function idOf(fav, url) {
        let s = String(fav || "").replace(/^applications:/, "")
        if (!/\.desktop$/.test(s)) { const m = /([^/]+\.desktop)$/.exec(String(url || "")); if (m) s = m[1] }
        return s
    }
    function itemOf(o, model) {
        const r = o.model, fav = String(r.favoriteId || ""), id = idOf(fav, r.url)
        const v = data.value || {}
        const g = v.games ? v.games[id] : null
        const u = v.usage ? v.usage[id] : null
        const f = p => p ? "file://" + p : ""
        return {
            key: id || fav || String(r.display || ""), id: id, name: String(r.display || ""), desc: String(r.description || ""),
            icon: r.decoration, favId: fav, url: String(r.url || ""),
            art: g ? { portrait: f(g.portrait), hero: f(g.hero), logo: f(g.logo), header: f(g.header) } : null,
            game: !!g, last: u ? u.last : 0, score: u ? u.score : 0,
            model: model, row: o.index, roles: r,
        }
    }
    function row(id, title, shape, items, opt) {
        opt = opt || {}
        const extra = opt.extra || []
        return { id: id, title: title, shape: shape, items: items.concat(extra),
                 divider: extra.length && items.length ? items.length : -1, labeled: !!opt.labeled, count: !!opt.count }
    }
    function rebuild() {
        const C = hm.launcher.categories
        const byLabel = {}
        for (let i = 0; i < cats.count; i++) {
            const h = cats.objectAt(i)
            if (h && C[i]) byLabel[C[i].label] = h.read().map(o => hm.itemOf(o, C[i].model))
        }
        const pins = favs.read().map(o => hm.itemOf(o, hm.launcher.favorites))
        const pinned = new Set(pins.map(p => p.key))
        const all = byLabel["All"] || []
        const recent = (byLabel["Recent"] || []).filter(a => !pinned.has(a.key)).slice(0, 10)
        // games: the menu's Games category, those with Steam's art first (the most recently played first)
        const games = (byLabel["Games"] || []).map(a => Object.assign(a, { game: true }))
        const byLast = (a, b) => (b.last || 0) - (a.last || 0)
        const covers = games.filter(a => a.art && a.art.portrait).sort(byLast)
        const tools = games.filter(a => !(a.art && a.art.portrait)).sort(byLast)
        const most = all.filter(a => a.score > 0).sort((a, b) => b.score - a.score).slice(0, 14)
        const skip = new Set(["All", "Recent"])
        const pages = [
            { id: "home", label: "Home", rows: [
                row("jump", "", "square", pins, { extra: recent }),
                row("games", "Games", "portrait", covers.concat(tools)),
                row("most", "Most used", "square", most, { labeled: true }),
            ]},
            { id: "games", label: "Games", rows: [
                row("library", "Library", "poster", covers.length ? covers : tools, { count: true }),
                row("tools", "Launchers & tools", "square", covers.length ? tools : [], { labeled: true, count: true }),
            ]},
            { id: "apps", label: "Apps", rows: C.filter(c => !skip.has(c.label)).map(c =>
                row("cat-" + c.label, c.label, "square", byLabel[c.label] || [], { labeled: true, count: true })) },
        ]
        for (const p of pages) p.rows = p.rows.filter(r => r.items.length)
        hm.pages = pages
        hm.rev++
    }
    Component.onCompleted: schedule()
}
