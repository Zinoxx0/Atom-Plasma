import QtQuick
import QtQuick.Effects
import QtCore
import org.kde.plasma.extras as PlasmaExtras
import Atom
import Atom.Native
import Rice
import ".."             // ThemeModel (what it shows, the commands that apply it), AccentEditor, NamingCard

// The Theme page, the same in every launcher style (the user, 2026-11-21: one design for both; designed in the Atom
// lab, ~/Projects/personal/atom-lab studies/theme-page.html). Everything on one screen, nothing folded away.
//   left   two panels of one kind (StudioSide): the screen being edited (the desk map is also the picker: a screen,
//          or all of them) with what belongs to it (Wallpapers, Colours), then Everywhere (Saved looks, Launcher,
//          Desktop, Lighting); each section shows its value now
//   right  the section, whole (Studio*.qml): wallpapers as a grid sorted by the accent each gives (rice.py
//          walls-index), filtered by mood; every choice as a picture of what it does; sizes as tick sliders
// The wallpaper (or saved look) in focus previews: on the desk map and on the whole page (the host wears its
// picture and palette: preview()). One lens walks it all: the keys and a pad's D-pad spatially (each part
// registers: Focusable), the pointer where it rests. A applies (ThemeModel: rice.py, rgb.py; dry runs under
// Shell.debug), B goes back to the sections and then out (key() returns false), LB/RB (Tab) the section, PgUp/PgDn
// the screen, Y shuffles (north()), X (Menu) a look's menu or an accent's editor.
// The host gives: the launcher, the ThemeModel, the screen's palette (rice), the palette to draw with (look: the host
// previews through it), its unit and where its content starts; it forwards its keys, the wheel and the pad's Y, and
// takes the keys back when an editor closes (giveKeys) or the focus goes up past the top (leave).
Item {
    id: ts
    required property var launcher
    required property var model
    required property RicePalette rice
    required property RicePalette look
    required property string screenName
    required property real unit
    property real topInset: d(140)
    property bool active: true              // the keys are here (not on the host's top bar)
    property string inputMode: Gamepad.inUse ? "pad" : "keys"   // pointer | keys | pad (hints show only the input in use)
    property bool padHints: inputMode === "pad"                 // frozen while pointer fades hints out (no glyph flash)
    onInputModeChanged: if (inputMode !== "pointer") padHints = inputMode === "pad"
    readonly property string actKey: inputMode === "pad" ? "A" : inputMode === "keys" ? "Enter" : ""
    readonly property string moreKey: inputMode === "pad" ? "X" : inputMode === "keys" ? "Menu" : ""
    property real veil: 0.5                 // the uniform shade over the backdrop (the text's contrast)
    property point origin: Qt.point(0, 0)   // the window's place on the desktop (the tests' logged positions)
    property string wideFamily: wideFont.status === FontLoader.Ready ? wideFont.name : Tokens.font.display
    signal preview(var values, string image, string thumb)
    signal leave()
    signal giveKeys()
    FontLoader { id: wideFont; source: Qt.resolvedUrl("../../fonts/HubotSans.ttf") }
    // the lab's pixels: drawn on the 1440p with the launcher at unit 0.836
    function d(px) { return px * unit / 0.836 }
    function wideAxes(w, wt) { return { "wdth": w, "wght": wt } }
    function cap1(s) { return s ? s[0].toUpperCase() + s.slice(1) : "" }
    function fileName(p) { return p ? String(p).split("/").pop() : "" }
    readonly property string home: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "")
    readonly property real mainX: d(600)
    readonly property real mainWidth: Math.max(d(400), width - mainX - d(72))

    // ---------------------------------------------------------------- the screen being edited
    readonly property var targetScreen: { const t = model.target; return (model.screens || []).find(s => s.name === (t === "all" ? screenName : t)) || null }
    readonly property string targetName: model.target === "all" ? "Every screen" : targetScreen ? targetScreen.label : model.target
    readonly property string targetLabel: model.target === "all" ? "every screen" : "the " + targetName
    readonly property string targetThumb: targetScreen ? targetScreen.thumb || "" : ""
    RicePalette { id: tpal; output: ts.model.target === "all" ? ts.screenName : ts.model.target }
    readonly property RicePalette targetPal: tpal
    function setTarget(t) {
        if (!t || t === model.target) return
        model.target = t
        if (Shell.debug) console.warn("ATOM theme target", t)
        say("Editing " + targetLabel)
        if (!(focused && focused.region)) wallFile = fileName(targetScreen ? targetScreen.image : "")
    }
    function cycleTarget(dir) {
        const ids = (model.screens || []).slice().sort((a, b) => a.x - b.x).map(s => s.name).concat(["all"])
        setTarget(ids[(Math.max(0, ids.indexOf(model.target)) + dir + ids.length) % ids.length])
    }
    function screensOn(file) { return (model.screens || []).filter(s => fileName(s.image) === file).map(s => s.label) }

    // ---------------------------------------------------------------- the wallpapers (rice.py page + walls-index)
    WatchedJson { id: index; path: ts.home + "/.cache/rice/walls-index.json" }
    readonly property var hueNames: [[18, "Rose"], [45, "Red"], [72, "Orange"], [98, "Amber"], [125, "Yellow"], [165, "Green"], [205, "Teal"],
                                     [235, "Cyan"], [268, "Blue"], [292, "Indigo"], [318, "Violet"], [345, "Magenta"], [361, "Rose"]]
    function hueName(m) { return m.C < 0.03 ? (m.L > 0.7 ? "Snow" : m.L < 0.3 ? "Ink" : "Grey") : (hueNames.find(x => m.hue < x[0]) || [0, "Rose"])[1] }
    // every wallpaper, sorted by the accent it gives (the greys last, light to dark), named by that accent and its
    // mood (numbered when a name repeats)
    readonly property var allWalls: {
        const page = model.page, ix = (index.value && index.value.walls) || {}
        if (!page || !page.walls) return []
        const order = m => !m ? 2000 : m.C < 0.03 ? 1000 + (1 - m.L) : (m.hue + 345) % 360
        const list = page.walls.map(w => { const m = ix[w.name] || null
            return { file: w.name, path: page.dir + "/" + w.name, thumb: w.thumb, mood: m ? m.mood : "", pal: m ? m.pal : null,
                     accent: m && m.pal ? m.pal.primary : "", o: order(m), base: m ? hueName(m) + " " + m.mood : w.name.replace(/\.[^.]+$/, "") } })
        list.sort((a, b) => a.o - b.o || (a.file < b.file ? -1 : 1))
        const count = {}, seen = {}
        for (const w of list) count[w.base] = (count[w.base] || 0) + 1
        for (const w of list) { if (count[w.base] > 1) { seen[w.base] = (seen[w.base] || 0) + 1; w.name = cap1(w.base) + " " + seen[w.base] } else w.name = cap1(w.base) }
        return list
    }
    function wallByFile(f) { return allWalls.find(w => w.file === f) || null }
    function wallName(f) { const w = wallByFile(f); return w ? w.name : f }
    property string filter: "all"
    signal wallsFiltered()
    readonly property var shownWalls: filter === "all" ? allWalls : allWalls.filter(w => w.mood === filter)
    readonly property var moodChips: [{ id: "all", name: "All", count: allWalls.length }].concat(["neon", "soft", "void", "light", "graphite"]
        .map(m => ({ id: m, name: cap1(m), count: allWalls.filter(w => w.mood === m).length })).filter(c => c.count > 0))
    property string wallFile: ""            // the wallpaper the grid's focus is on
    readonly property int wallIndex: Math.max(0, shownWalls.findIndex(w => w.file === wallFile))
    onAllWallsChanged: if (!wallFile && targetScreen) wallFile = fileName(targetScreen.image)
    function setWallIndex(i) { const w = shownWalls[i]; if (w && w.file !== wallFile) { wallFile = w.file; relens(); schedulePreview() } }
    function setFilter(m) {
        if (m === filter) return
        filter = m
        if (!shownWalls.some(w => w.file === wallFile) && shownWalls.length) wallFile = shownWalls[0].file
        if (Shell.debug) console.warn("ATOM theme filter", m)
        wallsFiltered()
    }
    function applyWall(w) {
        if (!w) return
        if (model.busy) { say("Still applying the last one"); return }
        model.apply({ kind: "wall", key: "wall:" + w.file, path: w.path })
        say(w.name + " on " + targetLabel)
    }
    function shuffle() { model.tool("walls:random"); say("A random wallpaper on " + targetLabel) }

    // ---------------------------------------------------------------- Find more online (wallhaven, StudioOnline)
    property bool online: false
    property string onlineQuery: ""
    property var onlineResults: []          // [{ id, url, thumb (a local copy), res, fav }]
    property int onlineIndex: 0
    property string onlineState: ""         // "" | "busy" | "empty" | "error"
    property var adding: ({})               // id -> "busy" | the path it was saved to
    signal onlineFresh()
    readonly property var onlineIdeas: {
        const recent = (launcher.cfg && launcher.cfg.tagHistory ? Array.from(launcher.cfg.tagHistory) : []).slice(0, 4)
        const ideas = ["night city", "rain", "cozy", "sunset", "mountains", "stars", "minimal", "cyberpunk", "autumn", "lake"]
        return recent.map(q => ({ q: q, recent: true })).concat(ideas.filter(q => recent.indexOf(q) < 0).slice(0, 10 - recent.length).map(q => ({ q: q, recent: false })))
    }
    function added(it) { const s = adding[it.id]; return !!s && s !== "busy" }
    function openOnline() {
        online = true
        if (Shell.debug) console.warn("ATOM theme online")
        enterTimer.restart()
    }
    function closeOnline() {
        online = false
        focusLater("walls:grid")
    }
    function browse(q, more) {
        q = String(q || "").trim()
        stopTyping()
        if (onlineState === "busy") return
        if (!more) {
            onlineQuery = q
            onlineResults = []
            onlineIndex = 0
            if (q && launcher.cfg) launcher.cfg.tagHistory = [q].concat(Array.from(launcher.cfg.tagHistory || []).filter(h => h.toLowerCase() !== q.toLowerCase())).slice(0, 6)
        }
        onlineState = "busy"
        const scr = model.target === "all" ? screenName : model.target
        const argv = ["python3", home + "/.config/plasma-rice/bin/wallhaven.py", "--browse", "--screen", scr]
        if (more && onlineResults.length) argv.push("--skip", onlineResults.map(r => r.id).join(","))
        argv.push("24", q)
        if (Shell.debug) console.warn("ATOM theme browse", JSON.stringify(q), more ? "(more)" : "")
        sh.exec("wbrowse", argv)
    }
    // A on a result: into your wallpapers (once in: on the screen)
    function onlinePick(it) {
        if (!it) return
        const st = adding[it.id]
        if (st === "busy") return
        if (st) { applyWall({ file: fileName(st), path: st, name: "The new one" }); return }
        setAdding(it.id, "busy")
        if (Shell.debug) { console.warn("ATOM theme run wallhaven.py --get", it.url); setAdding(it.id, "/dry-run/wallhaven-" + it.id + ".jpg"); return }
        sh.exec("wget", ["python3", home + "/.config/plasma-rice/bin/wallhaven.py", "--get", it.url])
    }
    function setAdding(id, v) { const a = Object.assign({}, adding); if (v) a[id] = v; else delete a[id]; adding = a }
    // typing in the search field: it takes the keyboard, and gives it back when the focus moves on
    property Item typingField: null
    function startTyping(field) { typingField = field; field.forceActiveFocus(); field.cursorPosition = field.text.length }
    function stopTyping() { if (!typingField) return; const f = typingField; typingField = null; f.focus = false; giveKeys() }
    function north() { if (section !== "walls") return false; shuffle(); return true }

    // ---------------------------------------------------------------- the sections
    readonly property var sections: [
        { id: "walls", icon: "wallpaper", name: "Wallpapers", scope: "here" },
        { id: "colours", icon: "palette", name: "Colours", scope: "here" },
        { id: "looks", icon: "bookmarks", name: "Saved looks", scope: "every" },
        { id: "launcher", icon: "apps", name: "Launcher", scope: "every" },
        { id: "desk", icon: "desktop_windows", name: "Desktop", scope: "every" },
        { id: "lights", icon: "keyboard", name: "Lighting", scope: "every" },
    ]
    property string section: "walls"
    property var lastKey: ({})              // per section: where the focus was in it
    function row(id) { return (model.rows || []).find(r => r.id === id) || null }
    function curName(id) { const r = row(id); const it = r ? r.items.find(x => x.current) : null; return it ? it.name : "" }
    function summary(id) {
        if (id === "walls") return targetScreen ? wallName(fileName(targetScreen.image)) + (model.target === "all" ? " · every screen" : "") : ""
        if (id === "colours") return model.moodLabel() + " · intensity " + Math.round(model.intensity * 100) + "%"
        if (id === "looks") { const l = (model.page && model.page.presets) || []; return l.length ? l.length + " saved · " + l.map(p => p.name).join(", ") : "None yet" }
        if (id === "launcher") { const s = row("lsize"); return [curName("lstyle"), s ? model.sizeText(s.items[0].v) : "", curName("backdrop")].filter(Boolean).join(" · ") }
        if (id === "desk") { const t = row("top"), b = row("tsize")
            return [t ? "Top bar " + model.sizeText(t.items[0].v) : "", b ? "taskbar " + model.sizeText(b.items[0].v) : "", curName("bar")].filter(Boolean).join(" · ") }
        if (id === "lights") { const k = (model.lights && model.lights.devices) || []; model.draft
            return k.length ? k.filter(x => x.ready && Object.assign({}, x.settings || {}, model.kbDraft(x.id)).on !== false).length + " of " + k.length + " keyboards on" : "No keyboards" }
        return ""
    }
    function setSection(id, enter) {
        if (id !== "walls") online = false
        if (id !== section) {
            section = id
            if (Shell.debug) console.warn("ATOM theme section", id)
        }
        if (enter) enterTimer.restart()
        relensSoon()
    }
    Timer { id: enterTimer; interval: 0; onTriggered: ts.focusKey(ts.entryKey(), "key") }
    function stepSection(dir) {
        const i = sections.findIndex(s => s.id === section), n = sections[(i + dir + sections.length) % sections.length]
        const inSide = !!(focused && focused.inSide)
        setSection(n.id, !inSide)
        if (inSide) focusKey("sec:" + n.id, "key")
    }
    function openSection(rowId) { setSection({ walls: "walls", colours: "colours", lights: "lights" }[rowId] || "walls", true) }
    // where the focus lands in a section: where it was, else the wallpaper in use, else its first part
    function entryKey() {
        const l = lastKey[section]
        if (l && findKey(l)) return l
        if (section === "walls") return online ? (onlineResults.length ? "on:grid" : "on:field") : "walls:grid"
        let best = null
        for (const f of regs) if (!f.inSide && f.visible) { const p = f.mapToItem(ts, 0, 0); if (!best || p.y < best.y - 1 || (Math.abs(p.y - best.y) <= 1 && p.x < best.x)) best = { f: f, x: p.x, y: p.y } }
        return best ? best.f.fkey : "sec:" + section
    }
    readonly property var head: {
        const n = targetScreen ? "<b>" + wallName(fileName(targetScreen.image)) + "</b>" : ""
        if (section === "walls" && online) return { title: "Find more online", count: onlineResults.length ? String(onlineResults.length) : "", chip: true,
                                                    sub: "from wallhaven · scenery shaped for this screen, none you have",
                                                    tools: [["arrow_back", "Your wallpapers", "", "online:back"]].concat(onlineResults.length ? [["refresh", "More", "", "online:more"]] : []) }
        if (section === "walls") return { title: "Wallpapers", count: String(allWalls.length), chip: true, sub: n + " is on it now · sorted by the accent each one gives",
                                          tools: [["shuffle", "Shuffle", "Y", "walls:random"], ["folder_open", "Folder", "", "walls:folder"],
                                                  ["travel_explore", "Find more online", "", "walls:discover"]] }
        if (section === "colours") return { title: "Colours", count: "", chip: true, sub: "read from " + n, tools: [] }
        if (section === "looks") return { title: "Saved looks", count: String(((model.page && model.page.presets) || []).length), chip: false,
                                          sub: "Every screen's wallpaper and colours in one step · the one in focus previews on your desk", tools: [] }
        if (section === "launcher") return { title: "Launcher", count: "", chip: false, sub: "Every screen · the power page wears the same backdrop", tools: [] }
        if (section === "desk") return { title: "Desktop", count: "", chip: false, sub: "Every screen · the bar on top and the taskbar's islands", tools: [] }
        return { title: "Lighting", count: "", chip: false, sub: "Each keyboard on its own: the screen it follows, its effect, its brightness", tools: [] }
    }
    function toolDo(id) {
        if (Shell.debug) console.warn("ATOM theme tool", id)
        if (id === "walls:random") shuffle()
        else if (id === "walls:discover") openOnline()
        else if (id === "online:back") closeOnline()
        else if (id === "online:more") browse(onlineQuery, true)
        else model.tool(id)
    }
    function slide(it, v) {
        if (!it) return
        if (Shell.debug) console.warn("ATOM theme slide", it.key, Number(v).toFixed(2))
        model.slide(it, v)
    }

    // ---------------------------------------------------------------- the focus: registered parts, one lens
    property var regs: []
    property Item focused: null
    function reg(f) { regs.push(f) }
    function unreg(f) { const i = regs.indexOf(f); if (i >= 0) regs.splice(i, 1); if (focused === f) { focused = null; refocusTimer.restart() } }
    function findKey(k) { return regs.find(f => f.fkey === k && f.visible) || null }
    function focusKey(k, from) { const f = findKey(k); if (f) focusItem(f, from) }
    // (timers, not Qt.callLater: they die with the page, a late call on a gone page threw)
    Timer { id: refocusTimer; interval: 0; onTriggered: ts.refocus() }
    Timer { id: relensTimer; interval: 0; onTriggered: ts.relens() }
    function relensSoon() { relensTimer.restart() }
    property string pendingKey: ""
    Timer { id: focusTimer; interval: 0; onTriggered: { const k = ts.pendingKey; ts.pendingKey = ""; ts.focusKey(k, "key") } }
    function focusLater(k) { pendingKey = k; focusTimer.restart() }
    function refocus() { if (!focused) focusKey(entryKey(), "jump") }
    function focusItem(f, from) {
        if (!f) return
        const was = focused
        if (typingField && f.fkey !== "on:field") stopTyping()
        focused = f
        if (!f.inSide && f.fkey) { const l = Object.assign({}, lastKey); l[section] = f.fkey; lastKey = l }
        if (from === "key" && f.rail && f.fkey.slice(4) !== section) setSection(f.fkey.slice(4), false)     // walking the sections shows them
        if (from === "key") quietUntil = Date.now() + 450
        relens(!was || from === "jump")
        schedulePreview()
        if (Shell.debug && f !== was) { console.warn("ATOM theme focus", f.fkey, "(" + from + ")"); partsLog.restart() }
    }
    function rectOf(f) {
        if (f.region) return f.lensRect()
        const t = f.lensItem || f
        return t.mapToItem(ts, 0, 0, t.width, t.height)
    }
    // the keys and the D-pad: the nearest part that way (a slider takes left and right; a region walks itself first)
    function move(dx, dy) {
        const cur = focused
        if (!cur) { refocus(); return }
        if (cur.slider && dx) { cur.nudged(dx); return }
        if (cur.region && cur.step(dx, dy)) return
        if (dx > 0 && cur.rail) { focusKey(entryKey(), "key"); return }
        const c = rectOf(cur), ccx = c.x + c.width / 2, ccy = c.y + c.height / 2
        let best = null, bs = 1e9
        for (const el of regs) {
            if (el === cur || !el.visible || el.opacity <= 0) continue
            if (dy && el.inSide !== cur.inSide) continue        // (up and down stay in their column: past its top is the top bar)
            const r = el.region ? el.mapToItem(ts, 0, 0, el.width, el.height) : rectOf(el)
            const rcx = r.x + r.width / 2, rcy = r.y + r.height / 2
            if (!(dx ? (dx > 0 ? rcx > ccx + 2 : rcx < ccx - 2) : (dy > 0 ? rcy > ccy + 2 : rcy < ccy - 2))) continue
            const p = dx ? (dx > 0 ? r.x - (c.x + c.width) : c.x - (r.x + r.width)) : (dy > 0 ? r.y - (c.y + c.height) : c.y - (r.y + r.height))
            const ov = dx ? Math.min(c.y + c.height, r.y + r.height) - Math.max(c.y, r.y) : Math.min(c.x + c.width, r.x + r.width) - Math.max(c.x, r.x)
            const s = Math.max(p, 0) + (ov > 0 ? 0 : -ov * 3) + (dx ? Math.abs(rcy - ccy) : Math.abs(rcx - ccx)) * 0.05
            if (s < bs) { bs = s; best = el }
        }
        if (!best) { if (dy < 0) leave(); return }
        if (dx < 0 && best.inSide && !cur.inSide) best = findKey("sec:" + section) || best      // back to the section it came from
        if (best.region) best.enterFrom(c, dx, dy)
        focusItem(best, "key")
    }
    function activate() {
        const f = focused
        if (!f) return
        if (Shell.debug) console.warn("ATOM theme activate", f.fkey)
        if (f.rail) setSection(f.fkey.slice(4), true)
        else f.activated()
    }
    // the pointer: it takes the focus where it rests, only when it really moved (a grid scrolling under a still
    // pointer, or a section changing under it, isn't the pointer)
    property double movedAt: 0
    property double quietUntil: 0
    function quiet() { quietUntil = Date.now() + 200 }
    HoverHandler { id: pointer }
    readonly property point pointerAt: pointer.point.scenePosition     // (in the window: the page sliding under a still pointer isn't a move)
    onPointerAtChanged: movedAt = Date.now()
    function pointerFresh() { const t = Date.now(); return t - movedAt < 150 && t > quietUntil }
    function pointed(f) { if (f !== focused && pointerFresh()) focusItem(f, "mouse") }
    // a grid's tile under the pointer: the grid picks it (its owner keeps the index), then the focus is there
    function pointedTile(region, i, click) {
        if (!click && !pointerFresh()) return
        region.pick(i)
        if (focused !== region) focusItem(region, "mouse"); else { relens(); schedulePreview() }
    }
    function clicked(f, focusOnly) {
        focusItem(f, "mouse")
        if (focusOnly) return
        if (f.rail) setSection(f.fkey.slice(4), false)
        else f.activated()
    }
    function wheel(dy) { if (section === "walls" && wallsLoader.item) wallsLoader.item.wheel(dy) }

    // the lens: one ring that glides from part to part (outside it, a gap away), its glow under the content
    property real lx: 0
    property real ly: 0
    property real lw: 0
    property real lh: 0
    property real lr: 0
    property bool lensJump: true
    function relens(jump) {
        const f = focused
        if (!f) return
        const r = rectOf(f)
        if (!r) return
        lensJump = !!jump || lw === 0
        lx = r.x - f.lensGap; ly = r.y - f.lensGap; lw = r.width + 2 * f.lensGap; lh = r.height + 2 * f.lensGap; lr = f.lensRadius + f.lensGap
        lensJump = false
    }
    onWidthChanged: relensSoon()
    onUnitChanged: relensSoon()             // (the launcher's own size changed: everything moved)
    onHeightChanged: relensSoon()

    // ---------------------------------------------------------------- the preview: what the focus would give
    property var deskPv: null               // {connector: thumb} for the desk map
    Timer { id: pvTimer; interval: 160; onTriggered: ts.updatePreview() }
    function schedulePreview() { pvTimer.restart() }
    function updatePreview() {
        const f = focused
        let pv = null, values = null, image = "", thumb = ""
        if (f && f.region && f.current) {
            const w = f.current()
            if (w) {
                pv = {}
                for (const s of model.targets) pv[s.name] = w.thumb
                image = w.path || ""; thumb = w.thumb
                values = w.pal ? Object.assign({}, rice.values, w.pal) : null
            }
        } else if (f && f.look && f.look.preset) {
            const p = f.look.preset
            pv = Object.assign({}, p.thumbs || {})
            image = f.look.image || ""; thumb = (p.thumbs || {})[screenName] || ""
            const w = wallByFile(fileName(image))
            values = w && w.pal ? Object.assign({}, rice.values, w.pal) : null
        }
        deskPv = pv
        preview(values, image, thumb)
    }

    // ---------------------------------------------------------------- the keys (the host forwards them)
    function key(event) {
        if (accentEd.open || naming.open) return false
        const k = event.key
        if (k === Qt.Key_Left) move(-1, 0)
        else if (k === Qt.Key_Right) move(1, 0)
        else if (k === Qt.Key_Up) move(0, -1)
        else if (k === Qt.Key_Down) move(0, 1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) activate()
        else if (k === Qt.Key_Escape) {
            if (online && focused && !focused.inSide) closeOnline()
            else if (focused && !focused.inSide) focusKey("sec:" + section, "key")
            else return false
        }
        else if (k === Qt.Key_Tab) stepSection(1)
        else if (k === Qt.Key_Backtab) stepSection(-1)
        else if (k === Qt.Key_PageUp || k === Qt.Key_PageDown) cycleTarget(k === Qt.Key_PageDown ? 1 : -1)
        else if (k === Qt.Key_Menu) { if (focused) focused.menu() }
        else if (focused && focused.fkey === "on:field" && event.text && event.text >= " " && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            const f = wallsLoader.item && wallsLoader.item.field
            if (!f) return false
            startTyping(f); f.insert(f.cursorPosition, event.text)
        }
        else return false
        return true
    }

    // ---------------------------------------------------------------- the editors and menus it opens
    function editAccent(it, at) { if (it && at) accentEd.openFor(it, at) }
    function saveLook(at) { naming.openAt(at, model.suggestName()) }
    function lookMenu(it, at) { lookMenuObj.it = it; lookMenuObj.visualParent = at; lookMenuObj.open(0, at.height + d(10)) }

    // ---------------------------------------------------------------- news
    property string news: ""
    function say(t) { news = t; newsTimer.restart() }
    Timer { id: newsTimer; interval: 2200; onTriggered: ts.news = "" }
    Connections { target: ts.model; function onStatusChanged() { if (ts.model.status) ts.say(ts.model.status) } }

    // ================================================================ the page
    // uniform: no edge anywhere (stronger for a light palette: a light wallpaper previewed over the room's dark scrims)
    Rectangle { anchors.fill: parent; color: C.alpha(ts.look.surfaceLowest, ts.look.light ? Math.max(ts.veil, 0.62) : ts.veil) }
    RectangularShadow {         // the lens's glow, under the content
        visible: ts.active && !!ts.focused && ts.lw > 0
        x: ts.lx; y: ts.ly; width: ts.lw; height: ts.lh
        radius: ts.lr; blur: ts.d(30); spread: ts.d(2)
        color: C.alpha(ts.look.primary, 0.55)
        Behavior on x { enabled: !ts.lensJump; NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Behavior on y { enabled: !ts.lensJump; NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Behavior on width { enabled: !ts.lensJump; NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Behavior on height { enabled: !ts.lensJump; NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
    }

    StudioSide {
        id: sideCol
        studio: ts
        x: ts.d(72)
        y: ts.topInset + ts.d(10)
        transformOrigin: Item.TopLeft
        scale: Math.min(1, (ts.height - y - ts.d(110)) / Math.max(1, implicitHeight))
        onScaleChanged: ts.relensSoon()
    }

    Item {
        id: mainCol
        x: ts.mainX
        y: ts.topInset
        width: ts.mainWidth
        height: ts.height - y - ts.d(96)
        // the header: the section's name (and count), what it's about (the screen's chip), its tools
        Item {
            id: header
            width: parent.width
            height: ts.d(96)
            Column {
                anchors.bottom: parent.bottom
                spacing: ts.d(12)
                Row {
                    spacing: ts.d(12)
                    Text {
                        id: title
                        text: ts.head.title
                        color: ts.look.fg
                        font.family: ts.wideFamily; font.variableAxes: ts.wideAxes(118, 650); font.pixelSize: ts.d(50)
                    }
                    Text { anchors.baseline: title.baseline; visible: ts.head.count !== ""; text: ts.head.count; color: ts.look.fgDim; font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: ts.d(20) }
                }
                Row {
                    spacing: ts.d(10)
                    ScreenTag { id: headTag; studio: ts; visible: ts.head.chip; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        // (never under the header's buttons)
                        width: Math.min(implicitWidth, header.width - headTools.width - (headTag.visible ? headTag.width + ts.d(10) : 0) - ts.d(32))
                        elide: Text.ElideRight
                        text: ts.head.sub
                        textFormat: Text.StyledText
                        color: ts.look.fgDim
                        font.family: Tokens.font.ui; font.pixelSize: ts.d(17)
                    }
                }
            }
            Row {
                id: headTools
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: ts.d(2)
                spacing: ts.d(10)
                Repeater {
                    model: ts.head.tools
                    StudioChip {
                        required property var modelData
                        studio: ts
                        fkey: "tool:" + modelData[3]
                        icon: modelData[0]
                        text: modelData[1]
                        pad: modelData[2]
                        desc: "<b>" + modelData[1] + "</b> " + ({ "walls:random": "A random wallpaper for " + ts.targetLabel + ".", "walls:folder": "Open the wallpapers' folder.",
                                                                  "walls:discover": "Look on wallhaven for more, shaped for this screen.", "online:back": "Back to the wallpapers you have.",
                                                                  "online:more": "The next ones it found." })[modelData[3]]
                        act: modelData[1]
                        onActivated: ts.toolDo(modelData[3])
                    }
                }
            }
        }
        // the section (only the one in view exists)
        Item {
            id: body
            y: header.height + ts.d(30)
            width: parent.width
            height: parent.height - y
            Loader {
                id: wallsLoader
                anchors.fill: parent
                active: ts.section === "walls"
                sourceComponent: ts.online ? onlineC : wallsC
                onLoaded: ts.relensSoon()
            }
            Loader {
                id: otherLoader
                active: ts.section !== "walls"
                sourceComponent: ts.section === "colours" ? coloursC : ts.section === "looks" ? looksC : ts.section === "launcher" ? launcherC
                               : ts.section === "desk" ? deskC : lightsC
                transformOrigin: Item.TopLeft
                scale: item ? Math.min(1, body.height / Math.max(1, item.implicitHeight), body.width / Math.max(1, item.implicitWidth)) : 1
                onLoaded: ts.relensSoon()
            }
            NumberAnimation on opacity { id: bodyIn; from: 0; to: 1; duration: Tokens.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn }
        }
    }
    onSectionChanged: bodyIn.restart()
    onOnlineChanged: bodyIn.restart()
    Component { id: wallsC; StudioWalls { studio: ts } }
    Component { id: onlineC; StudioOnline { studio: ts } }
    Component { id: coloursC; StudioColours { studio: ts } }
    Component { id: looksC; StudioLooks { studio: ts } }
    Component { id: launcherC; StudioLauncher { studio: ts } }
    Component { id: deskC; StudioDesktop { studio: ts } }
    Component { id: lightsC; StudioLights { studio: ts } }

    // the lens's ring (over everything), and a wallpaper's name in it
    Rectangle {
        visible: ts.active && !!ts.focused && ts.lw > 0
        x: ts.lx; y: ts.ly; width: ts.lw; height: ts.lh
        radius: ts.lr
        color: "transparent"
        border.width: ts.d(2.5)
        border.color: ts.look.fg
        Behavior on x { enabled: !ts.lensJump; NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Behavior on y { enabled: !ts.lensJump; NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Behavior on width { enabled: !ts.lensJump; NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Behavior on height { enabled: !ts.lensJump; NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Rectangle {
            visible: !!(ts.focused && ts.focused.tag)
            x: ts.d(12) + (ts.focused ? ts.focused.lensGap : 0); y: parent.height - height - ts.d(12) - (ts.focused ? ts.focused.lensGap : 0)
            width: tagT.width + ts.d(22); height: ts.d(28); radius: ts.d(9)
            color: C.alpha(ts.look.surfaceLowest, 0.82)
            Text { id: tagT; anchors.centerIn: parent; text: ts.focused ? ts.focused.tag : ""; color: ts.look.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: ts.d(14) }
        }
    }

    // the footer: what the focus is, and the keys (a pad's buttons when it's the one in use); not while the keys are on
    // the host's top bar (it has its own)
    Item {
        opacity: ts.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.ms(250) } }
        x: ts.d(72)
        width: ts.width - 2 * ts.d(72)
        y: ts.height - ts.d(34) - height
        height: ts.d(40)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - (hintsRow.visible ? hintsRow.width + ts.d(40) : 0)
            elide: Text.ElideRight
            text: ts.focused ? ts.focused.desc : ""
            textFormat: Text.StyledText
            color: ts.look.fgDim
            font.family: Tokens.font.ui; font.pixelSize: ts.d(15.5)
        }
        Row {
            id: hintsRow
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            spacing: ts.d(26)
            opacity: ts.inputMode === "pointer" ? 0 : 1
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Tokens.ms(260) } }
            Repeater {
                model: ts.hints
                Row {
                    required property var modelData
                    spacing: ts.d(9)
                    Repeater {
                        model: modelData[0]
                        Rectangle {
                            required property var modelData
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property bool face: modelData.length === 1
                            width: Math.max(ts.d(28), kt.implicitWidth + ts.d(14)); height: ts.d(28)
                            radius: face ? height / 2 : ts.d(8)
                            color: "transparent"
                            border.width: ts.d(1.5); border.color: C.alpha(ts.look.fg, 0.38)
                            Text { id: kt; anchors.centerIn: parent; text: modelData; color: ts.look.fg; font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: ts.d(12.5) }
                        }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; color: ts.look.fgDim; font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: ts.d(15) }
                }
            }
        }
    }
    readonly property var hints: {
        const f = focused, a = f ? f.act : "Choose", pad = padHints, walls = section === "walls"
        const out = []
        if (f && f.slider) out.push([pad ? ["◀", "▶"] : ["←", "→"], "Adjust"])
        out.push([pad ? ["A"] : ["Enter"], a])
        if (pad && walls) out.push([["Y"], "Shuffle"])
        if (f && (f.look || String(f.fkey).startsWith("acc:"))) out.push([pad ? ["X"] : ["Menu"], "More"])
        if (!pad && (walls || section === "colours")) out.push([["PgUp", "PgDn"], "Screen"])
        out.push([pad ? ["LB", "RB"] : ["Tab"], "Section"])
        out.push([pad ? ["B"] : ["Esc"], f && !f.inSide ? "Back" : "Close"])
        return out
    }

    // news (applied, editing another screen, an error)
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: ts.height - ts.d(100) - height - (ts.news ? 0 : ts.d(16))
        width: newsT.width + ts.d(44); height: ts.d(46); radius: ts.d(16)
        color: ts.look.fg
        opacity: ts.news ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.ms(300) } }
        Behavior on y { NumberAnimation { duration: Tokens.ms(400); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Text { id: newsT; anchors.centerIn: parent; text: ts.news || " "; color: ts.look.surfaceLowest; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: ts.d(16) }
    }

    // ---------------------------------------------------------------- the editors (an accent's colour; naming a look)
    AccentEditor {
        id: accentEd
        anchors.fill: parent
        z: 60
        rice: ts.look
        model: ts.model
        unit: ts.unit
        onClosed: { focus = false; ts.giveKeys() }      // (a FocusScope remembers its focused child)
    }
    NamingCard {
        id: naming
        anchors.fill: parent
        z: 60
        rice: ts.look
        model: ts.model
        unit: ts.unit
        onClosed: { focus = false; ts.giveKeys() }
    }
    PlasmaExtras.Menu {
        id: lookMenuObj
        property var it: null
        PlasmaExtras.MenuItem { text: "Load"; icon: "view-refresh"; onClicked: if (lookMenuObj.it) ts.model.apply(lookMenuObj.it) }
        PlasmaExtras.MenuItem { text: "Save the current look over it"; icon: "document-save"; onClicked: if (lookMenuObj.it) ts.model.savePreset(lookMenuObj.it.name) }
        PlasmaExtras.MenuItem { separator: true }
        PlasmaExtras.MenuItem { text: "Delete"; icon: "edit-delete"; onClicked: if (lookMenuObj.it) ts.model.deletePreset(lookMenuObj.it.name) }
    }

    // ---------------------------------------------------------------- the tests: where the parts sit
    Timer {
        id: partsLog
        interval: Tokens.ms(520)
        onTriggered: {
            for (const f of ts.regs) {
                if (!f.visible || !f.fkey) continue
                const r = ts.rectOf(f)
                console.warn("ATOM theme part", f.fkey, "at", Math.round(ts.origin.x + r.x + r.width / 2), Math.round(ts.origin.y + r.y + r.height / 2))
            }
        }
    }

    RiceShell {
        id: sh
        onNewData: (source, data) => {
            const kind = (source.match(/#(\w+)(?: \d+)?$/) || [])[1], out = data["stdout"] ?? ""
            if (kind === "wbrowse") {
                try {
                    const r = JSON.parse(out), have = new Set(ts.onlineResults.map(x => x.id))
                    const more = (r.picks || []).filter(x => !have.has(x.id))
                    const first = !ts.onlineResults.length
                    ts.onlineResults = ts.onlineResults.concat(more)
                    ts.onlineState = ts.onlineResults.length ? "" : "empty"
                    if (first && more.length) { ts.onlineFresh(); ts.focusLater("on:grid") }
                    else if (!more.length && !first) ts.say("Nothing more for that")
                } catch (e) { ts.onlineState = "error" }
            } else if (kind === "wget") {
                let saved = []
                try { saved = JSON.parse(out).saved || [] } catch (e) { }
                for (const it of ts.onlineResults) if (ts.adding[it.id] === "busy") ts.setAdding(it.id, saved.find(p => p.indexOf("wallhaven-" + it.id + ".") >= 0) || "")
                if (saved.length) {
                    ts.say("Added to your wallpapers")
                    ts.model.reload()
                    sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" walls-index #windex')
                } else ts.say("Couldn't download it")
            }
            disconnectSource(source)
        }
    }
    Component.onCompleted: {
        model.reload()
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" walls-index #windex')     // (only new or changed files)
        if (targetScreen) wallFile = fileName(targetScreen.image)
        Qt.callLater(() => focusKey("walls:grid", "jump"))
    }
    Component.onDestruction: preview(null, "", "")
}
