import QtQuick
import Atom
import Rice

// Atom Home's Theme page: what `rice.py page` says (the collection, the screens, the saved themes, the moods,
// the size settings) and `rgb.py status` (the keyboards), as rows of items, and the actions that change them
// (the same commands the Theme panels run: rice.py <image> / preset load / theme set / ui set, rgb.py set).
// Applying re-themes the desktop, and the launcher with it: its palette follows. Under the nested tests
// (Shell.debug) nothing is run: "ATOM theme run <args>" says what would have been.
// Items: { kind: look | save | wall | colours-auto | mood | accent | backdrop | barstyle | kb | lsize | top | tsize, key,
// name, ... }; the three sizes are sliders ({ slider: true, v, min, max, step, def }: ThemeSlider, slide(it, v)).
// Rows come in groups (a header row before each: Look, Launcher, Desktop > Taskbar, Keyboard lighting), the
// themes above them all; Stage keeps which are open (all closed whenever the page is opened).
// Each row also carries its own settings, shown in its header (nothing hides behind a settings button):
// tools: [{ id, kind: button | toggle | minus | plus | value, icon, label, tip, on }] (tool(id) does them).
// Live edits (an accent's colour, the intensity, the keyboards' brightness) queue: one command runs at a time
// and only the latest value waits behind it.
Item {
    id: tm
    visible: false
    required property var launcher
    required property RicePalette rice
    required property string screenName     // the launcher's screen: the one edited unless "all"
    property var page: null                 // rice.py page
    property var lights: null               // rgb.py status
    property string target: screenName      // an output name, or "all"
    property string busy: ""                // the key of what's being applied ("" = nothing)
    property string status: ""              // what the last command said when it failed
    property var rows: []
    property int rev: 0
    property string pageRaw: ""
    property string lightsRaw: ""
    property var live: null                 // the live edit waiting behind a running one: { key, argv }
    property var draft: ({})                // values shown while they're on their way: { "accent:primary": "#hex", intensity, brightness }

    readonly property var screens: page ? page.screens : []
    readonly property var targets: target === "all" ? screens : screens.filter(s => s.name === target)
    readonly property string targetLabel: target === "all" ? "every screen" : "the " + ((screens.find(s => s.name === target) || {}).label || target)

    RiceShell {
        id: sh
        onNewData: (source, data) => {
            const out = data["stdout"] ?? ""
            const kind = (source.match(/#(\w+)(?: \d+)?$/) || [])[1]
            // the same answer as last time changes nothing (the stage asks on every opening)
            if (kind === "tpage") { if (out && out !== tm.pageRaw) try { tm.page = JSON.parse(out); tm.pageRaw = out; tm.build() } catch (e) { } }
            else if (kind === "tlights") { if (out && out !== tm.lightsRaw) try { tm.lights = JSON.parse(out); tm.lightsRaw = out; tm.build() } catch (e) { } }
            else if (kind === "tapply") {
                const code = data["exit code"] ?? 0
                tm.status = code !== 0 ? String(data["stderr"] ?? "").trim().split("\n").pop() : ""
                tm.busy = ""
                if (tm.live) { const l = tm.live; tm.live = null; tm.run(l.key, l.argv) }
                else tm.reload()
            }
            disconnectSource(source)
        }
    }
    function reload() {
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" page #tpage')
        sh.connectSource('python3 "$HOME/.config/plasma-rice/bin/rgb.py" status #tlights')
    }
    function riceCmd(args) { return ["python3", sh.home + "/.config/plasma-rice/rice.py"].concat(args) }
    function run(key, argv) {
        if (busy) { if (key.startsWith("live:")) live = { key: key, argv: argv }; return }
        if (Shell.debug) { console.warn("ATOM theme run", argv.slice(1).join(" ")); return }   // the nested tests: never for real
        busy = key
        status = ""
        sh.exec("tapply", argv)
    }
    // what Enter (or the bright pill) does to an item
    function apply(it) {
        if (!it || busy) return
        if (it.kind === "wall") run(it.key, riceCmd([it.path, "--screen", target]))
        else if (it.kind === "look") run(it.key, riceCmd(["preset", "load", it.name]))
        else if (it.kind === "colours-auto") run(it.key, riceCmd(["theme", "reset", "--screen", target]))
        else if (it.kind === "mood") run(it.key, riceCmd(["theme", "set", "--screen", target, "--mood", it.mood]))
        else if (it.slider) slide(it, it.v)
        else if (it.kind === "backdrop") run(it.key, riceCmd(["backdrop", it.style]))
        else if (it.kind === "light") run(it.key, ["python3", sh.home + "/.config/plasma-rice/bin/rgb.py", "set", "all"].concat(it.args))
        else if (it.kind === "kb") {
            const a = it.args
            for (let i = 0; i + 1 < a.length; i += 2) setDraft("kb:" + it.dev + ":" + a[i].slice(2), a[i + 1] === "true" ? true : a[i + 1] === "false" ? false : a[i + 1])
            run(it.key, ["python3", sh.home + "/.config/plasma-rice/bin/rgb.py", "set", it.dev].concat(a))
        }
        else if (it.kind === "barstyle") run(it.key, riceCmd(["bar", "style", it.style]))
        else if (it.kind === "launcherstyle") { if (!it.current) { run(it.key, riceCmd(["launcher", "style", it.style])); launcher.restyle(it.style) } }
    }

    // ------------------------------------------------------------------ live edits and the rows' tools
    function setDraft(k, v) { const d = Object.assign({}, draft); d[k] = v; draft = d; build() }
    function dropDraft(k, v) { if (draft[k] !== undefined && Math.abs(draft[k] - v) < 0.001) { const d = Object.assign({}, draft); delete d[k]; draft = d } }
    // a size slider let go at v (on its steps): shown at once, applied in the background (the latest waits)
    function slide(it, v) {
        if (!it || !it.slider) return
        v = Math.round(Math.round(Math.max(it.min, Math.min(it.max, v)) / it.step) * it.step * 100) / 100
        setDraft("slider:" + it.key, v)
        const argv = it.key === "lsize" ? ["launcher", "size", String(v)] : it.key === "top" ? ["top", "size", String(v)]
                   : ["ui", "set", "--size", String(v)]
        run("live:" + it.key, riceCmd(argv))
    }
    function sizeText(v) { return Number(v).toFixed(2) + "×" }
    function setAccent(role, hex) {
        if (role.startsWith("kb:")) {       // a keyboard's own colour (the accent editor, reused)
            const id = role.slice(3)
            setDraft("kb:" + id + ":colour", hex); setDraft("kb:" + id + ":mode", "manual"); setDraft("kb:" + id + ":effect", "static"); setDraft("kb:" + id + ":on", true)
            run("live:kb", ["python3", sh.home + "/.config/plasma-rice/bin/rgb.py", "set", id, "--mode", "manual", "--effect", "static", "--colour", hex, "--on", "true"])
            return
        }
        setDraft("accent:" + role, hex)
        run("live:accent", riceCmd(["theme", "set", "--screen", target, "--" + role, hex]))
    }
    // the three accents back to the wallpaper's, in one go
    function resetAccents() {
        for (const r of ["primary", "secondary", "tertiary"]) setDraft("accent:" + r, undefined)
        run("live:accent", riceCmd(["theme", "set", "--screen", target, "--primary", "auto", "--secondary", "auto", "--tertiary", "auto"]))
    }
    function setIntensity(v) {
        v = Math.round(Math.max(0.3, Math.min(1.5, v)) * 10) / 10
        setDraft("intensity", v)
        run("live:intensity", riceCmd(["theme", "set", "--screen", target, "--intensity", String(v)]))
    }
    // a keyboard: the screen it follows ("lead" = the theme's), its brightness, on or off
    function setFollow(id, to) {
        setDraft("kb:" + id + ":follow", to)
        run("live:follow:" + id, ["python3", sh.home + "/.config/plasma-rice/bin/rgb.py", "set", id, "--follow", to])
    }
    function setKbBright(id, v) {
        v = Math.max(0, Math.min(100, Math.round(v)))
        setDraft("kb:" + id + ":brightness", v)
        run("live:kbright:" + id, ["python3", sh.home + "/.config/plasma-rice/bin/rgb.py", "set", id, "--brightness", String(v)])
    }
    function kbPower(id, on) {
        setDraft("kb:" + id + ":on", on)
        run("live:kbon:" + id, ["python3", sh.home + "/.config/plasma-rice/bin/rgb.py", "set", id, "--on", String(on)])
    }
    function resetAccent(role) {
        if (role.startsWith("kb:")) {       // "Automatic": back to following its screen
            const id = role.slice(3)
            setDraft("kb:" + id + ":mode", "auto")
            run("live:kb", ["python3", sh.home + "/.config/plasma-rice/bin/rgb.py", "set", id, "--mode", "auto", "--on", "true"])
            return
        }
        setDraft("accent:" + role, undefined)
        run("live:accent", riceCmd(["theme", "set", "--screen", target, "--" + role, "auto"]))
    }
    readonly property real intensity: { const d = draft.intensity; if (d !== undefined) return d; const ov = here().overrides || {}; return ov.intensity !== undefined && ov.intensity !== "auto" ? Number(ov.intensity) : 1 }
    readonly property var lightDevs: tm.lights && tm.lights.devices ? tm.lights.devices.filter(d => d.ready) : []
    readonly property int brightness: draft.brightness !== undefined ? draft.brightness : lightDevs.length ? (lightDevs[0].settings || {}).brightness ?? 0 : 0
    // the screen whose colours are shown: the one being edited (every screen: the launcher's own)
    function here() { const n = target === "all" ? screenName : target; return screens.find(s => s.name === n) || screens.find(s => s.name === screenName) || screens.find(s => s.main) || screens[0] || {} }
    // presets: names up to 10 characters (rice.py trims them the same way)
    function savePreset(name) { const n = String(name || "").trim().slice(0, 10); if (n) run("save", riceCmd(["preset", "save", n])) }
    function deletePreset(name) { run("delete:" + name, riceCmd(["preset", "delete", name])) }
    function suggestName() {
        const used = (page ? page.presets : []).map(p => p.name)
        const base = Qt.formatDate(new Date(), "MMM d").toLowerCase()
        let n = base, i = 2
        while (used.indexOf(n) >= 0) n = base + " " + i++
        return n.slice(0, 10)
    }
    // what a tool in a row's header does
    signal openFinder()                     // "Find more online": the wallhaven search (the old detailed panel)
    function tool(id) {
        if (id === "walls:random") run(id, riceCmd(["random", "--screen", target]))
        else if (id === "walls:folder") { if (page && page.dir) Qt.openUrlExternally("file://" + page.dir) }
        else if (id === "walls:discover") openFinder()
        else if (id === "ui:auto") {        // the taskbar's size on each screen's standard size, or the same everywhere
            const ui = page && page.ui || {}
            const on = !(draft["ui:auto"] ?? !!ui.auto)
            setDraft("ui:auto", on)
            run("live:uiauto", riceCmd(["ui", "set", "--auto", String(on)]))
        }
        else if (id === "intensity-" || id === "intensity+") {
            const v = Math.round(Math.max(0.3, Math.min(1.5, intensity + (id === "intensity+" ? 0.1 : -0.1))) * 10) / 10
            setDraft("intensity", v)
            run("live:intensity", riceCmd(["theme", "set", "--screen", target, "--intensity", String(v)]))
        } else if (id === "bright-" || id === "bright+") {
            const v = Math.max(0, Math.min(100, Math.round(brightness / 10) * 10 + (id === "bright+" ? 10 : -10)))
            setDraft("brightness", v)
            run("live:bright", ["python3", sh.home + "/.config/plasma-rice/bin/rgb.py", "set", "all", "--brightness", String(v)])
        } else if (id.startsWith("follow:")) {      // the next screen it follows: the theme's, then each screen
            const dev = (tm.lights && tm.lights.devices || []).find(d => d.id === id.slice(7))
            if (!dev) return
            const cur = (Object.assign({}, dev.settings || {}, kbDraft(dev.id))).follow || "lead"
            const order = ["lead"].concat(screens.map(x => x.name))
            const next = order[(Math.max(0, order.indexOf(cur)) + 1) % order.length]
            setDraft("kb:" + dev.id + ":follow", next)
            run("live:follow", ["python3", sh.home + "/.config/plasma-rice/bin/rgb.py", "set", dev.id, "--follow", next])
        } else if (id.startsWith("kbright")) {
            const dev = (tm.lights && tm.lights.devices || []).find(d => d.id === id.split(":")[1])
            if (!dev) return
            const cur = (Object.assign({}, dev.settings || {}, kbDraft(dev.id))).brightness ?? 0
            const v = Math.max(0, Math.min(100, Math.round(cur / 10) * 10 + (id.startsWith("kbright+") ? 10 : -10)))
            setDraft("kb:" + dev.id + ":brightness", v)
            run("live:kbright:" + dev.id, ["python3", sh.home + "/.config/plasma-rice/bin/rgb.py", "set", dev.id, "--brightness", String(v)])
        } else if (id.startsWith("power:")) {
            const dev = lightDevs.find(d => d.id === id.slice(6))
            if (!dev) return
            const on = !((draft["on:" + dev.id] ?? (dev.settings || {}).on) !== false)
            setDraft("on:" + dev.id, on)
            run("live:power", ["python3", sh.home + "/.config/plasma-rice/bin/rgb.py", "set", dev.id, "--on", String(on)])
        }
    }
    // a fresh answer from rice.py / rgb.py replaces what was shown while on its way
    onPageRawChanged: if (!busy && !live) draft = ({})
    onLightsRawChanged: if (!busy && !live) {       // the keyboards' answer replaces what was shown on its way
        const d = {}; for (const k in draft) if (!k.startsWith("kb:")) d[k] = draft[k]; draft = d
    }

    function screenLabel(name) { const sc = screens.find(x => x.name === name || x.id === name); return sc ? sc.label : name }
    function moodLabel() { const ov = here().overrides || {}; return ov.mood ? ov.mood[0].toUpperCase() + ov.mood.slice(1) : "Automatic colours" }
    function kbDraft(id) {
        const o = {}
        for (const k of ["on", "mode", "style", "effect", "follow", "brightness", "colour"]) if (draft["kb:" + id + ":" + k] !== undefined) o[k] = draft["kb:" + id + ":" + k]
        return o
    }
    function barStyleName() { return ({ solid: "Solid", matte: "Noisy matte", clear: "Clear blur", none: "No blur" })[Prefs.barStyle] || "Solid" }
    readonly property var backdropNames: ({ matte: "Noisy matte", clear: "Clear blur", noise: "Noisy only", none: "No blur" })
    // the groups (a group inside another: its parent), in their order
    readonly property var groupParent: ({ bar: "desk" })
    // ------------------------------------------------------------------ the rows
    function fileName(p) { return p ? String(p).split("/").pop() : "" }
    function build() {
        if (!page) return
        const out = []
        const here = tm.here()
        // themes: whole looks, every screen's wallpaper and hand-picked colours
        const looks = page.presets.map(p => ({
            kind: "look", key: "look:" + p.name, name: p.name, preset: p, current: !!p.current,
            layout: (p.layout || []).map(e => ({ x: e.x, y: e.y, w: e.w, h: e.h, main: e.main, thumb: e.thumb })),
            thumb: (p.thumbs && (p.thumbs[screenName] || Object.values(p.thumbs)[0])) || "",
            image: (() => { const pl = p.plan && p.plan[screenName]; const e = (p.layout || []).find(x => pl && x.id === pl.from) || (p.layout || []).find(x => x.main) || (p.layout || [])[0]; return e ? e.image || "" : "" })(),
            meta: [(p.layout || []).length + " screens", p.current ? "On screen now" : ""].filter(Boolean),
            desc: "Every screen's wallpaper and hand-picked colours, together. Screens it doesn't know mirror the main one.",
        }))
        looks.push({ kind: "save", key: "save", name: "Save this look", meta: [], desc: "Keep every screen's wallpaper and colours under a short name, to come back to in one step." })
        // (above the groups, always in sight: a theme is the whole look at once)
        out.push({ id: "looks", group: "", title: "Themes", shape: "look", items: looks, divider: -1, labeled: false, count: true, tools: [] })
        // the collection
        const on = name => screens.filter(s => fileName(s.image) === name).map(s => s.label)
        const walls = page.walls.map((w, i) => ({
            kind: "wall", key: "wall:" + w.name, name: "", file: w.name, path: page.dir + "/" + w.name, thumb: w.thumb, n: i + 1,
            onScreens: on(w.name), current: targets.some(s => fileName(s.image) === w.name),
            meta: on(w.name).length ? ["On the " + on(w.name).join(" and ")] : [], desc: w.name,
        }))
        out.push({ id: "walls", title: "Wallpapers", shape: "wall", items: walls, divider: -1, labeled: false, count: true, tools: [
            { id: "walls:random", kind: "button", icon: "shuffle", label: "Shuffle" },
            { id: "walls:folder", kind: "button", icon: "folder_open", label: "Folder" },
            { id: "walls:discover", kind: "button", icon: "travel_explore", label: "Find more online" },
        ] })
        // colours: the wallpaper's own, a mood, or an accent of your own
        const ov = here.overrides || {}
        const mood = ov.mood || "auto"
        const colours = [{ kind: "colours-auto", key: "colours:auto", name: "Automatic", current: Object.keys(ov).length === 0,
                           meta: ["From the wallpaper"], desc: "The wallpaper's own colours: its mood and three accents, read when it's set." }]
        const moodWords = { neon: "Saturated accents that glow.", soft: "Pastel accents, gentle on the eyes.", light: "Light surfaces with deep accents.",
                            void: "Near black, one quiet accent.", graphite: "Neutral greys; colour only where it matters." }
        for (const m of page.moods || [])
            colours.push({ kind: "mood", key: "mood:" + m, mood: m, name: m[0].toUpperCase() + m.slice(1), current: mood === m,
                           meta: [mood === m ? "Hand-picked" : "A mood"], desc: moodWords[m] || "" })
        for (const r of ["primary", "secondary", "tertiary"])
            colours.push({ kind: "accent", key: "accent:" + r, role: r, name: r[0].toUpperCase() + r.slice(1), hex: draft["accent:" + r] || String(tm.rice[r]),
                           current: !!ov[r], meta: [ov[r] ? "Hand-picked" : "From the wallpaper"],
                           desc: "Pick your own to mismatch on purpose; a new wallpaper on that screen brings the automatic one back." })
        out.push({ id: "colours", title: "Colours", shape: "chip", items: colours, divider: -1, labeled: true, count: false, tools: [
            { id: "intensity-", kind: "minus", icon: "remove", tip: "Calmer accents" },
            { id: "intensity", kind: "value", icon: "contrast", label: "Intensity " + Math.round(intensity * 100) + "%" },
            { id: "intensity+", kind: "plus", icon: "add", tip: "Stronger accents" },
        ] })
        // the sizes, each a slider in steps of 0.05 on each screen's standard size (how big a pixel looks from where
        // you sit): the launcher's, the top bar's, the taskbar's (ui: also the same size everywhere, "Automatic" off)
        const ui = page.ui || {}
        const Sl = (key, kind, name, v, def, desc, meta, defLabel) => ({ kind: kind, key: key, slider: true, name: name, v: v, min: 0.8, max: 1.8,
                                                                         step: 0.05, def: def, defLabel: defLabel || "Standard", current: false, meta: meta, desc: desc })
        const lnow = draft["slider:lsize"] ?? launcher.homeSize
        out.push({ id: "lsize", title: "Launcher size", shape: "slider", divider: -1, labeled: false, count: false, tools: [], items: [
            Sl("lsize", "lsize", "Launcher size", lnow, 1.0, "This launcher and its pages on every screen, on each screen's standard size. The desktop keeps its own sizes.",
               [sizeText(lnow), "Each screen's standard size × this"]) ] })
        // which launcher this is (settings launcher.style): picking the other closes this one and opens it (main.qml restyle)
        const ls = Shell.styleOverride || Prefs.launcherStyle
        const L = (style, name, desc) => ({ kind: "launcherstyle", key: "lstyle:" + style, style: style, name: name, current: ls === style,
                                            meta: [ls === style ? "Now" : "Opens at once"], desc: desc })
        out.push({ id: "lstyle", title: "Launcher style", shape: "look", divider: -1, labeled: false, count: false, tools: [], items: [
            L("simplified", "Simplified", "Rows of your apps and games under a big picture of the one in focus."),
            L("atom", "Atom's", "Your apps as an atom: rings round a glass core you turn, games as banners, your wallpapers as a colour wheel."),
        ] })
        // its backdrop (Atom Backdrop), the power page's too: they always wear the same one
        const bd = Prefs.backdropStyle
        const D = (style, desc) => ({ kind: "backdrop", key: "backdrop:" + style, style: style, name: backdropNames[style], current: bd === style,
                                      meta: [bd === style ? "Now" : "The launcher and the power page"], desc: desc })
        out.push({ id: "backdrop", title: "Backdrop style", shape: "look", divider: -1, labeled: false, count: false, tools: [], items: [
            D("matte", "Your wallpaper, frosted, under a fine grain: a still, matte finish. The windows behind it are hidden."),
            D("clear", "A live blur of whatever is behind, windows too, like glass."),
            D("noise", "Your wallpaper as it is, sharp, under the same fine grain: its texture without the blur. The windows behind it are hidden."),
            D("none", "Your wallpaper as it is, sharp, with no blur or filter: only the dark shade that keeps the text readable."),
        ] })
        // the top bar (Glimpse's band): its own size
        const tnow = draft["slider:top"] ?? ((page.top || {}).size || 1.05)
        out.push({ id: "top", title: "Top bar size", shape: "slider", divider: -1, labeled: false, count: false, tools: [], items: [
            Sl("top", "top", "Top bar size", tnow, 1.05, "The bar at the top of every screen: its strip and the window shelf it opens, on each screen's standard size.",
               [sizeText(tnow), "Each screen's standard size × this"], "Default") ] })
        // the taskbar: its size (its popups and the desk's clocks follow it), then its islands' glass
        const auto = draft["ui:auto"] ?? !!ui.auto
        const bnow = draft["slider:tsize"] ?? (ui.size || 1)
        const own = (ui.screens || []).filter(x => x.own).map(x => "the " + String(x.label).toLowerCase() + " keeps its own " + sizeText(x.own))
        out.push({ id: "tsize", title: "Taskbar size", shape: "slider", divider: -1, labeled: false, count: false, items: [
            Sl("tsize", "tsize", "Taskbar size", bnow, 1.0,
               (auto ? "The taskbar, its popups and the desk's clocks, on each screen's standard size." : "The taskbar, its popups and the desk's clocks, this size on every screen.")
               + (own.length ? " (" + own.join(", ") + ".)" : ""),
               [sizeText(bnow), auto ? "Each screen's standard size × this" : "The same on every screen"], auto ? "Standard" : "1×") ],
            tools: [{ id: "ui:auto", kind: "toggle", icon: "auto_awesome", label: "Automatic", on: auto,
                      tip: auto ? "On: each screen at its standard size × this" : "Off: this size on every screen" }] })
        // the taskbar's islands: their glass (rice.py bar style: Panel Colorizer looks, on every bar)
        const bs = Prefs.barStyle
        const B = (style, name, desc) => ({ kind: "barstyle", key: "bar:" + style, style: style, name: name, current: bs === style,
                                            meta: [bs === style ? "Now" : "Every bar"], desc: desc })
        out.push({ id: "bar", title: "Island style", shape: "look", divider: -1, labeled: false, count: false, tools: [], items: [
            B("solid", "Solid", "Dark glass you can't see through: the islands as they've always been."),
            B("matte", "Noisy matte", "Frosted, with the launcher's fine grain: the wallpaper softly through it."),
            B("clear", "Clear blur", "Glass: a clear blur of what's behind, lightly tinted."),
            B("none", "No blur", "A tint over the wallpaper as it is, sharp, with no blur."),
        ] })
        // keyboard lighting: one row per keyboard, each its own: which screen it follows (its colours come from that
        // screen's palette), how it shows them (styles), or its own effect and colour (manual), its brightness, on/off
        const kbs = tm.lights && tm.lights.devices ? tm.lights.devices : []
        for (const d of kbs) {
            const ds = Object.assign({}, d.settings || {}, kbDraft(d.id))
            const on = ds.on !== false, auto = ds.mode === "auto"
            const short = d.id === "laptop" ? "Laptop" : String(d.name || d.id).split(" ")[0]
            const follow = ds.follow || "lead"
            const fname = follow === "lead" ? "the theme's screen" : "the " + screenLabel(follow)
            const items = []
            const styleWords = { solid: ["Match screen", "The screen's accent, solid."], gradient: ["Gradient", "The screen's two accents across the keys."],
                                 breathe: ["Breathing", "The screen's accents, slowly brighter, then dimmer."], starlight: ["Starlight", "The accents twinkling, key by key."] }
            for (const st of d.styles || []) {
                const w = styleWords[st.id] || [st.name, ""]
                items.push({ kind: "kb", key: "kb:" + d.id + ":style:" + st.id, dev: d.id, name: w[0], effect: st.id === "solid" ? "auto" : st.id,
                             args: ["--mode", "auto", "--style", st.id, "--on", "true"], current: on && auto && ds.style === st.id,
                             meta: [on && auto && ds.style === st.id ? "Now" : "From " + fname], desc: w[1] + " It follows " + fname + "." })
            }
            const effWords = { static: null, spectrum: ["Spectrum", "Every colour in turn."], wave: ["Rainbow wave", "A rainbow rolling across the keys."],
                               reactive: ["Reactive", "Keys light up as you type."], pulse: ["Pulse", "Your colour, pulsing."] }
            for (const ef of d.effects || []) {
                const w = effWords[ef.id]
                if (!w || ef.colours > 1) continue      // (colour effects come through "Your colour"; two-colour ones are the styles')
                items.push({ kind: "kb", key: "kb:" + d.id + ":fx:" + ef.id, dev: d.id, name: w[0], effect: ef.id === "wave" ? "spectrum" : ef.id,
                             args: ["--mode", "manual", "--effect", ef.id, "--on", "true"], current: on && !auto && ds.effect === ef.id,
                             meta: [on && !auto && ds.effect === ef.id ? "Now" : "Its own"], desc: w[1] })
            }
            const mine = on && !auto && ds.effect === "static"
            items.push({ kind: "accent", key: "kb:" + d.id + ":colour", role: "kb:" + d.id, dev: d.id, name: "Your colour", editTitle: short + " keyboard colour",
                         hex: ds.colour || "#ff3355", current: mine, meta: [mine ? "Now" : "Its own"],
                         desc: "One colour of your own on the " + short.toLowerCase() + " keyboard, whatever the screens wear." })
            items.push({ kind: "kb", key: "kb:" + d.id + ":off", dev: d.id, name: "Off", effect: "off", args: ["--on", "false"], current: !on,
                         meta: [!on ? "Now" : ""].filter(Boolean), desc: "Dark." })
            const b = ds.brightness ?? 0
            const tools = d.ready ? [
                { id: "follow:" + d.id, kind: "button", icon: "monitor", label: "Follows " + (follow === "lead" ? "theme screen" : screenLabel(follow)),
                  tip: "Which screen's colours it wears: click for the next" },
                { id: "kbright-:" + d.id, kind: "minus", icon: "remove", tip: "Dimmer" },
                { id: "kbright:" + d.id, kind: "value", icon: "light_mode", label: b + "%" },
                { id: "kbright+:" + d.id, kind: "plus", icon: "add", tip: "Brighter" },
            ] : []
            out.push({ id: "kb-" + d.id, group: "keys", title: short + " keyboard", shape: "chip", items: d.ready ? items : [],
                       divider: -1, labeled: true, count: false, tools: tools,
                       note: d.ready ? "" : (d.connected ? "Needs a one-time setup (Fine-tune shows it)" : "Not connected") })
        }
        // the groups: a header before each (it opens and closes the group; Stage keeps which are open), a group's own
        // rows, then the groups inside it (indented: depth)
        const groupOf = { walls: "look", colours: "look", lsize: "launcher", lstyle: "launcher", backdrop: "launcher", top: "desk", tsize: "bar", bar: "bar" }
        for (const r of out) if (r.group === undefined) r.group = groupOf[r.id] || (String(r.id).startsWith("kb-") ? "keys" : "look")
        const kbOn = kbs.filter(d => d.ready && (Object.assign({}, d.settings || {}, kbDraft(d.id)).on !== false)).length
        const heads = {
            look: { title: "Look", icon: "palette", summary: (page.walls || []).length + " wallpapers · " + moodLabel(),
                    desc: "Wallpapers and colours: what every screen wears." },
            launcher: { title: "Launcher", icon: "apps", summary: (ls === "atom" ? "Atom's" : "Simplified") + " · " + sizeText(lnow) + " · " + backdropNames[bd],
                        desc: "Which launcher this is, its size and the backdrop it and the power page wear." },
            desk: { title: "Desktop", icon: "desktop_windows", summary: "Top bar " + sizeText(tnow) + " · taskbar " + sizeText(bnow),
                    desc: "The top bar on every screen, and the taskbar." },
            bar: { title: "Taskbar", icon: "dock_to_bottom", summary: (auto ? "Automatic " : "") + sizeText(bnow) + " · " + barStyleName(),
                   desc: "The taskbar's size (its popups and the desk's clocks follow it) and how its islands look." },
            keys: { title: "Keyboard lighting", icon: "keyboard", summary: kbs.length ? kbOn + " of " + kbs.length + " on" : "No keyboards",
                    desc: "Each keyboard on its own: the screen it follows, its style or its own colour and effect, its brightness." },
        }
        const grouped = out.filter(r => !r.group)
        const emit = (g, depth) => {
            const rs = out.filter(r => r.group === g)
            const kids = Object.keys(groupParent).filter(k => groupParent[k] === g)
            if (!rs.length && !kids.some(k => out.some(r => r.group === k))) return
            const h = heads[g]
            grouped.push({ id: "group:" + g, group: g, header: true, depth: depth, title: h.title, shape: "header", divider: -1, labeled: false, count: false, tools: [],
                           items: [{ kind: "group", ctl: "group", group: g, depth: depth, key: "group:" + g, name: h.title, icon: h.icon, meta: [h.summary], desc: h.desc }] })
            for (const r of rs) { r.depth = depth; grouped.push(r) }
            for (const k of kids) emit(k, depth + 1)
        }
        for (const g of ["look", "launcher", "desk", "keys"]) emit(g, 0)
        rows = grouped
        rev++
    }
    onTargetChanged: build()
    Connections { target: tm.launcher; function onHomeSizeChanged() { tm.dropDraft("slider:lsize", tm.launcher.homeSize); tm.build() } }
    Connections { target: Prefs; function onBackdropStyleChanged() { tm.build() } function onBarStyleChanged() { tm.build() } function onLauncherStyleChanged() { tm.build() } }
}
