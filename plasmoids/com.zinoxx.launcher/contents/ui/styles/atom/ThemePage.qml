import QtQuick
import QtCore
import Atom
import Rice
import "../.."          // ThemeModel: what the Theme page shows and the commands that apply it (shared with the simplified style)

// Atom's Theme page. The outer ring is a dial of sections; the rings inside are the section's settings, every one a ring
// you turn. Wallpapers: a colour wheel of your own wallpapers, one ring per mood the theme engine finds (graphite, light,
// void, neon, soft), each one placed by its hue (rice.py walls-index); while one has the focus the scene is that
// wallpaper and every part of the page wears the palette it would make. Sizes are gauges (the lens is the knob); choices
// are rings of options. A applies (through ThemeModel: rice.py, rgb.py; dry runs in the nested tests).
Item {
    id: page
    required property var stage
    anchors.fill: parent
    readonly property string home: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "")

    ThemeModel { id: tm; launcher: page.stage.launcher; rice: page.stage.rice; screenName: page.stage.screenName }
    WatchedJson { id: index; path: page.home + "/.cache/rice/walls-index.json" }
    readonly property var walls: index.value && index.value.walls ? index.value.walls : null
    readonly property string inUse: String(page.stage.rice.wallpaper).split("/").pop()
    function row(id) { return (tm.rows || []).find(r => r.id === id) || null }

    // ---------------------------------------------------------------- the sections and their rings
    readonly property var sectionList: [
        { name: "Wallpapers", glyph: "wallpaper", label: "Wallpapers", desc: "Your wallpapers on a colour wheel: one ring per mood, each where its colour is" },
        { name: "Colours", glyph: "palette", label: "Colours", desc: "Mood, accent and how strong the colours are" },
        { name: "Themes", glyph: "layers", label: "Themes", desc: "Looks you saved: every screen's wallpaper and colours together" },
        { name: "Launcher", glyph: "apps", label: "Launcher", desc: "Its size, its style and what's behind it" },
        { name: "Desktop", glyph: "desktop_windows", label: "Desktop", desc: "The top bar, the taskbar and its islands" },
    ].concat((tm.lights && tm.lights.devices && tm.lights.devices.length) ? [{ name: "Lighting", glyph: "keyboard", label: "Lighting", desc: "Keyboard lights" }] : [])
    property string section: "Wallpapers"

    readonly property var moods: [["graphite", 178], ["light", 236], ["void", 294], ["neon", 356], ["soft", 436]]
    readonly property var hueNames: [[18, "Rose"], [45, "Red"], [72, "Orange"], [98, "Amber"], [125, "Yellow"], [165, "Green"], [205, "Teal"],
                                     [235, "Cyan"], [268, "Blue"], [292, "Indigo"], [318, "Violet"], [345, "Magenta"], [361, "Rose"]]
    function hueName(w) { return w.C < 0.03 ? (w.L > 0.7 ? "Snow" : w.L < 0.3 ? "Ink" : "Grey") : hueNames.find(x => w.hue < x[0])[1] }
    function cap1(s) { return s ? s[0].toUpperCase() + s.slice(1) : "" }
    function wallRings() {
        if (!walls) {           // the index isn't there yet (its first build takes a few seconds): the wallpapers in a ring
            const r = row("walls")
            return [{ name: "Wallpapers", radius: 330, size: 70, window: 16, items: r ? r.items.map(w => ({ name: w.file, art: "file://" + w.thumb, file: w.file, now: w.file === page.inUse })) : [] }]
        }
        const names = Object.keys(walls)
        return page.moods.map(m => {
            const r = m[1]
            const items = names.filter(n => walls[n].mood === m[0]).map(n => ({ name: page.hueName(walls[n]) + " " + m[0], file: n, w: walls[n],
                                                                                dot: walls[n].pal.primary, ang: walls[n].hue - 120, now: n === page.inUse }))
            items.sort((a, b) => a.ang - b.ang)
            const gap = (26 / r) * 180 / Math.PI           // nudged apart so none overlap
            for (let pass = 0; pass < 80; pass++) for (let i = 0; i < items.length; i++) {
                const a = items[i], b = items[(i + 1) % items.length]
                const dd = b.ang + (i === items.length - 1 ? 360 : 0) - a.ang
                if (items.length > 1 && dd < gap) { const push = (gap - dd) / 2; a.ang -= push; b.ang += push }
            }
            return { name: page.cap1(m[0]), radius: r, size: 18, placed: true, items: items }
        }).filter(s => s.items.length)
    }
    function gauge(name, it) {       // a size: a gauge of its steps over 270 deg (bottom-left, round the top, bottom-right)
        if (!it) return null
        const n = Math.round((it.max - it.min) / it.step) + 1, items = []
        for (let k = 0; k < n; k++) {
            const v = Math.round((it.min + k * it.step) * 100) / 100, end = k === 0 || k === n - 1
            items.push({ name: v.toFixed(2) + "×", v: v, mark: true, major: Math.abs(v * 4 - Math.round(v * 4)) < 1e-6, ang: 135 + k * 270 / (n - 1),
                         label: end ? v.toFixed(2) + "×" : "", now: Math.abs(v - it.v) < 0.001, slider: it })
        }
        return { name: name, items: items, placed: true, gauge: true, size: 14 }
    }
    function options(name, r, glyphs) {
        return r ? { name: name, size: 62, items: r.items.map(x => ({ name: x.name, label: x.name, glyph: glyphs[x.style || x.key] || "tune", now: !!x.current, it: x })) } : null
    }
    readonly property var styleGlyph: ({ matte: "grain", clear: "blur_on", noise: "texture", none: "image", solid: "rectangle" })
    function sectionRings(n) {
        const out = []
        if (n === "Wallpapers") return wallRings()
        if (n === "Colours") {
            const r = row("colours"), items = r ? r.items : []
            const g = gauge("Intensity", { min: 0.5, max: 1.5, step: 0.05, v: tm.intensity })
            if (g) { g.radius = 196; g.items.forEach(m => { m.intensity = true; m.slider = null }); out.push(g) }
            const sw = { auto: ["#ff6b9e", "#6bffb8", "#6bb8ff"], neon: ["#ff3fa4", "#2fa8ff", "#a64dff"], soft: ["#c7b8ff", "#ffd6e8", "#b8e6ff"],
                         light: ["#ffffff", "#dfe6f0", "#f6efe6"], void: ["#05060a", "#1b2340", "#0d1020"], graphite: ["#3a3d44", "#8a8f99", "#5d6168"] }
            out.push({ name: "Mood", radius: 318, size: 64, items: items.filter(x => x.kind === "mood" || x.kind === "colours-auto")
                      .map(x => ({ name: x.name, label: x.name, swc: sw[x.mood || "auto"], now: !!x.current, it: x })) })
            const hues = []
            for (let k = 0; k < 24; k++) { const c = Qt.hsla(k / 24, 0.78, 0.62, 1); hues.push({ name: "Accent", sw: c, hex: String(c), ang: 180 + k * 15, accent: true }) }
            out.push({ name: "Accent", radius: 430, size: 40, placed: true, items: hues })
        } else if (n === "Themes") {
            const r = row("looks")
            out.push({ name: "Saved", radius: 330, size: 96, items: r ? r.items.map(x => x.kind === "save"
                ? { name: "Save this look", label: "Save this look", glyph: "add", big: 72, it: x }
                : { name: x.name, label: x.name, art: x.thumb ? "file://" + x.thumb : "", now: !!x.current, it: x }) : [] })
        } else if (n === "Launcher") {
            const g = gauge("Size", (row("lsize") || { items: [] }).items[0]); if (g) { g.radius = 196; out.push(g) }
            const st = page.options("Style", row("lstyle"), { simplified: "view_agenda", atom: "public" }); if (st) { st.radius = 300; out.push(st) }
            const b = page.options("Backdrop", row("backdrop"), page.styleGlyph); if (b) { b.radius = 420; out.push(b) }
        } else if (n === "Desktop") {
            const t = page.gauge("Top bar", (row("top") || { items: [] }).items[0]); if (t) { t.radius = 196; out.push(t) }
            const s = page.gauge("Taskbar", (row("tsize") || { items: [] }).items[0]); if (s) { s.radius = 300; out.push(s) }
            const i = page.options("Islands", row("bar"), page.styleGlyph); if (i) { i.radius = 420; out.push(i) }
        } else if (n === "Lighting") {
            const g = { "Match screen": "palette", Gradient: "gradient", Breathing: "air", Starlight: "auto_awesome", Spectrum: "looks",
                        "Rainbow wave": "waves", Reactive: "keyboard", Pulse: "favorite", Off: "power_settings_new" }
            const kbs = (tm.rows || []).filter(r => String(r.id).startsWith("kb-") && r.items.length).slice(0, 2)
            kbs.forEach((r, k) => out.push({ name: r.title, radius: k ? 400 : 250, size: 58, items: r.items.map(x => x.kind === "accent"
                ? { name: x.name, label: x.name, sw: x.hex, now: !!x.current, it: x }
                : { name: x.name, label: x.name, glyph: g[x.name] || "light_mode", now: !!x.current, it: x }) }))
        }
        return out.filter(s => s && s.items.length)
    }
    readonly property var dial: ({ name: "Sections", radius: 520, size: 62, items: page.sectionList })
    readonly property var shells: { tm.rev; index.value; return page.sectionRings(page.section).concat([page.dial]) }
    onShellsChanged: Qt.callLater(page.focusInUse)
    property bool touched: false    // the keys or the pointer moved the focus: the page no longer goes to what's in use
    function focusInUse() {         // every ring at what's in use (the dial at its section); at first, the focus on it too
        for (let i = 0; i < page.shells.length; i++) {
            const r = atom.ringAt(i), s = page.shells[i]
            if (!r || !s) continue
            let j = s === page.dial ? page.sectionList.findIndex(x => x.name === page.section) : s.items.findIndex(x => x.now)
            if (j < 0) j = 0
            r.picked = -1
            if (s.placed) r.placedCur = j
            r.current = j
        }
        if (!page.touched && page.section === "Wallpapers") {
            const k = page.shells.findIndex(s => s !== page.dial && s.items.some(x => x.now))
            if (k >= 0) atom.at = k
        }
    }

    Rectangle {             // a disc of dark glass behind the rings (the scene is a sharp wallpaper here)
        readonly property real r: page.stage.d(575) * page.stage.atomK
        x: page.stage.atomAt.x - r; y: page.stage.atomAt.y - r
        width: 2 * r; height: width; radius: r
        color: C.alpha(page.stage.look.surfaceLowest, 0.5)
        border.width: 1; border.color: C.alpha(page.stage.look.fg, 0.08)
        opacity: M.clamp(page.stage.atomT * 2)
    }
    AtomView {
        id: atom
        stage: page.stage
        shells: page.shells
        tint: page.stage.look.primary
        Component.onCompleted: Qt.callLater(page.focusInUse)
        onLaunched: it => page.activate(it)
    }
    readonly property bool atDial: atom.ring && atom.at === page.shells.length - 1

    // the dial: resting on a section shows its rings (A opens it: the focus goes in)
    Connections { target: atom; function onFocusItemChanged() { if (page.atDial) sectionSettle.restart() } }
    Timer { id: sectionSettle; interval: 380; onTriggered: if (page.atDial && atom.focusItem) page.openSection(atom.focusItem.name, false) }
    function openSection(n, inward) {
        if (n !== page.section) { page.section = n; Qt.callLater(() => atom.at = page.shells.length - 1) }
        if (inward) Qt.callLater(() => { atom.at = Math.max(0, page.shells.length - 2) })
    }

    // what A does
    function activate(it) {
        if (!it) return
        if (page.atDial) { page.openSection(it.name, true); return }
        if (it.w || it.file) {
            const r = row("walls"), wi = r ? r.items.find(x => x.file === it.file) : null
            if (wi) { tm.apply(wi); page.stage.say("Applying " + it.name) } else page.stage.say("Still reading the wallpapers")
        } else if (it.intensity) {
            tm.setDraft("intensity", it.v)
            tm.run("live:intensity", tm.riceCmd(["theme", "set", "--screen", tm.target, "--intensity", String(it.v)]))
            page.stage.say("Intensity " + Math.round(it.v * 100) + "%")
        } else if (it.slider) { tm.slide(it.slider, it.v); page.stage.say(atom.ring.name + " " + it.name) }
        else if (it.accent) { tm.setAccent("primary", it.hex); page.stage.say("Accent set") }
        else if (it.it && it.it.kind === "save") { tm.savePreset(tm.suggestName()); page.stage.say("Saved") }
        else if (it.it && it.it.kind === "accent" && it.it.role) { tm.setAccent(it.it.role, it.it.hex); page.stage.say(it.name) }
        else if (it.it) { tm.apply(it.it); page.stage.say(it.name) }
    }
    function shuffle() {           // a wallpaper at random: the lens goes there
        const rings = page.shells.filter(s => s.placed && !s.gauge && s.items.length && s.items[0].file)
        if (!rings.length) return
        const s = rings[Math.floor(Math.random() * rings.length)], k = page.shells.indexOf(s), r = atom.ringAt(k)
        atom.at = k; atom.mode = "slot"
        if (r) { const j = Math.floor(Math.random() * s.items.length); r.picked = -1; r.placedCur = j; r.current = j }
    }

    // ---------------------------------------------------------------- the focus: the caption, the preview
    readonly property var caption: {
        const it = atom.focusItem, r = atom.ring
        if (!it || !r) return { where: ["Theme"], name: "Theme" }
        const n = (r.items.length > 1 ? [(r.placed ? r.order.indexOf(r.focusIndex) : r.focusIndex) + 1 + " of " + r.items.length] : [])
        if (page.atDial) return { where: ["Theme"].concat(n), name: it.name, desc: it.desc, acts: [["A", "Open"]] }
        if (it.w) return { where: ["Wallpapers", page.cap1(it.w.mood)].concat(n), name: page.cap1(it.name), desc: it.file + (it.now ? ", on your screens now" : ""),
                           facts: [[page.cap1(it.w.mood), "mood"], [it.w.pal.primary, "accent", it.w.pal.primary], [it.w.pal._scheme === "light" ? "Light" : "Dark", "interface"]],
                           acts: [["A", "Apply"], ["Y", "Shuffle"]], tools: [["shuffle", "Shuffle"], ["folder_open", "Folder"]] }
        if (it.mark) return { where: [page.section, r.name], name: it.name, desc: it.now ? "Now" : "", acts: [["A", "Set"]] }
        return { where: [page.section, r.name].concat(n), name: it.name, desc: it.now ? "In use" : (it.it && it.it.desc) || "",
                 acts: [["A", it.it && it.it.kind === "launcherstyle" && !it.now ? "Switch to it" : "Use"]] }
    }
    function publish() {
        if (!page.stage) return
        const it = atom.focusItem
        page.stage.caption = page.caption
        page.stage.previewValues = it && it.w ? Object.assign({}, page.stage.rice.values, it.w.pal) : null
        page.stage.focusItem = it && it.w && it.w.path ? { hero: "file://" + it.w.path, sharp: true } : null
        page.stage.focusTint = page.stage.look.primary
    }
    onCaptionChanged: publish()
    Component.onCompleted: {
        tm.reload()
        page.stage.shell('python3 "$HOME/.config/plasma-rice/rice.py" walls-index #windex')     // (only new or changed files)
        page.stage.pageApi = { act: i => i === 0 ? page.activate(atom.focusItem) : page.shuffle(), wheel: dy => atom.turn(dy > 0 ? -1 : 1),
                               tool: i => i === 0 ? page.shuffle() : Qt.openUrlExternally("file://" + ((tm.page && tm.page.dir) || page.home + "/Pictures/Wallpapers")),
                               north: () => page.shuffle() }
        page.stage.hints = { pad: [["↕", "Turn"], ["↔", "Ring"], ["A", "Apply"], ["Y", "Shuffle"], ["B", "Back"]],
                             keys: [["↑ ↓", "Turn"], ["← →", "Ring"], ["Enter", "Apply"], ["Esc", "Back"]] }
        publish()
    }
    Component.onDestruction: if (page.stage) { page.stage.previewValues = null; page.stage.focusItem = null }
    Connections {
        target: page.stage
        function onPageKey(event) {
            const k = event.key
            page.touched = true
            if (k === Qt.Key_Up) atom.turn(-1)
            else if (k === Qt.Key_Down) atom.turn(1)
            else if (k === Qt.Key_Left) atom.hop(1)
            else if (k === Qt.Key_Right) atom.hop(-1)
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) page.activate(atom.focusItem)
            else return
            event.accepted = true
        }
    }
}
