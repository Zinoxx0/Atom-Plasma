import QtQuick
import org.kde.kirigami as Kirigami
import Rice

// Atom's search: KRunner's matches (the launcher's runner: apps, settings, files, maths, units...) on one ring round the
// core, the best in the slot (up/down turn it, Enter or a click opens), and "Search the web" always last (KDE's default
// web shortcut is unset here: DuckDuckGo, as KDE falls back to). The stage owns the query (typing anywhere adds to it).
Item {
    id: page
    required property var stage
    anchors.fill: parent
    readonly property var runner: page.stage ? page.stage.launcher.runnerModel : null
    readonly property string query: page.stage ? page.stage.launcher.query : ""
    property var results: []

    // every group's matches, read through delegates (one list, rebuilt a beat after anything changes)
    Repeater {
        id: groups
        model: page.runner
        delegate: Item {
            required property int index
            readonly property var matches: page.runner ? page.runner.modelForRow(index) : null
            readonly property string groupName: matches ? String(matches.name || "") : ""
            readonly property alias rows: rowRep
            Repeater {
                id: rowRep
                model: parent.matches
                delegate: Item {
                    required property var model
                    readonly property string name: String(model.display || "")
                    readonly property var icon: model.decoration
                    readonly property string desc: String(model.description || "")
                }
                onCountChanged: settle.restart()
            }
        }
        onCountChanged: settle.restart()
    }
    Connections { target: page.runner; function onQueryFinished() { settle.restart() } }
    onQueryChanged: settle.restart()
    Timer { id: settle; interval: 60; onTriggered: page.collect() }
    function collect() {
        const out = []
        for (let g = 0; g < groups.count; g++) {
            const gi = groups.itemAt(g)
            if (!gi || !gi.rows) continue
            for (let i = 0; i < gi.rows.count && out.length < 39; i++) {
                const r = gi.rows.itemAt(i)
                if (r && r.name) out.push({ name: r.name, icon: r.icon, desc: r.desc || gi.groupName, kind: gi.groupName, model: gi.matches, row: i })
            }
        }
        if (page.query.trim()) out.push({ name: "Search the web", icon: "internet-web-browser", desc: "“" + page.query + "” on DuckDuckGo", kind: "Web", web: true })
        page.results = out
    }

    AtomView {
        id: atom
        stage: page.stage
        shells: page.results.length ? [{ name: "Results", items: page.results, radius: 300, size: 66, window: 16 }] : []
        tint: page.tint
        onLaunched: it => page.open(it)
        onOptions: (it, dl) => { if (it && it.model && !it.web && dl) page.stage.launcher.menu.openFor(dl, it.model, it.row) }
    }
    function open(it) {
        if (!it) return
        if (it.web) { Qt.openUrlExternally("https://duckduckgo.com/?q=" + encodeURIComponent(page.query)); page.stage.launcher.close(); return }
        page.stage.launcher.launch(it.model, it.row)
    }
    ImagePalette { id: colours; source: atom.focusItem ? atom.focusItem.icon : "" }
    readonly property color tint: C.appTint(colours, page.stage ? page.stage.look.primary : "#888888")

    readonly property var caption: {
        const it = atom.focusItem, r = atom.ring
        if (!page.query.trim()) return { where: ["Search"], name: "Type to search", desc: "Apps, settings, files, maths and units" }
        if (!it || !r) return { where: ["Search", "“" + page.query + "”"], name: "Nothing yet", desc: "Still looking" }
        return { where: ["Search", "“" + page.query + "”", (r.focusIndex + 1) + " of " + r.items.length], name: it.name, desc: it.desc,
                 acts: [["A", it.web ? "Search" : "Open"]].concat(it.web ? [] : [["X", "Options"]]) }
    }
    function publish() {
        if (!page.stage) return
        page.stage.caption = page.caption
        page.stage.focusItem = null
        page.stage.focusTint = page.tint
    }
    onCaptionChanged: publish()
    onTintChanged: publish()
    onResultsChanged: if (atom.ring) { atom.ring.current = 0; atom.ring.picked = -1; atom.mode = "slot" }   // the best match in the slot
    Component.onCompleted: {
        if (!page.stage) return
        page.stage.pageApi = { act: i => i === 0 ? atom.launch() : atom.openOptions(), wheel: dy => atom.turn(dy > 0 ? -1 : 1) }
        page.stage.hints = { pad: [["↕", "Turn"], ["A", "Open"], ["X", "Options"], ["B", "Back"]],
                             keys: [["↑ ↓", "Turn"], ["Enter", "Open"], ["Esc", "Back"]] }
        collect(); publish()
    }
    Connections {
        target: page.stage
        function onPageKey(event) {
            const k = event.key
            if (k === Qt.Key_Up) atom.turn(-1)
            else if (k === Qt.Key_Down) atom.turn(1)
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) atom.launch()
            else if (k === Qt.Key_Menu) atom.openOptions()
            else return
            event.accepted = true
        }
    }
}
