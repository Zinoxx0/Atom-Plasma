import QtQuick
import Atom
import "Rice"

// Atom Home's Theme page: what `rice.py page` says (the collection, the screens, the saved themes, the moods,
// the size settings) and `rgb.py status` (the keyboards), as rows of items, and the actions that change them
// (the same commands the Theme panels run: rice.py <image> / preset load / theme set / ui set, rgb.py set).
// Applying re-themes the desktop, and the launcher with it: its palette follows. Under the nested tests
// (Shell.debug) nothing is run: "ATOM theme run <args>" says what would have been.
// Items: { kind: look | save | wall | colours-auto | mood | accent | size | light, key, name, ... }
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
                tm.reload()
            }
            disconnectSource(source)
        }
    }
    function reload() {
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" page #tpage')
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rgb.py" status #tlights')
    }
    function riceCmd(args) { return ["python3", sh.home + "/.config/plasma-rice/rice.py"].concat(args) }
    function run(key, argv) {
        if (busy) return
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
        else if (it.kind === "size") run(it.key, riceCmd(["ui", "set"].concat(it.v === "auto" ? ["--auto", "true"] : ["--auto", "false", "--size", String(it.v)])))
        else if (it.kind === "light") run(it.key, ["python3", sh.home + "/.config/plasma-rice/rgb.py", "set", "all"].concat(it.args))
    }

    // ------------------------------------------------------------------ the rows
    function fileName(p) { return p ? String(p).split("/").pop() : "" }
    function build() {
        if (!page) return
        const out = []
        const here = screens.find(s => s.name === screenName) || screens.find(s => s.main) || screens[0] || {}
        // themes: whole looks, every screen's wallpaper and hand-picked colours
        const looks = page.presets.map(p => ({
            kind: "look", key: "look:" + p.name, name: p.name, preset: p, current: !!p.current,
            layout: (p.layout || []).map(e => ({ x: e.x, y: e.y, w: e.w, h: e.h, main: e.main, thumb: e.thumb })),
            thumb: (p.thumbs && (p.thumbs[screenName] || Object.values(p.thumbs)[0])) || "",
            image: (() => { const pl = p.plan && p.plan[screenName]; const e = (p.layout || []).find(x => pl && x.id === pl.from) || (p.layout || []).find(x => x.main) || (p.layout || [])[0]; return e ? e.image || "" : "" })(),
            meta: [(p.layout || []).length + " screens", p.current ? "On screen now" : ""].filter(Boolean),
            desc: "Every screen's wallpaper and hand-picked colours, together. Screens it doesn't know mirror the main one.",
        }))
        looks.push({ kind: "save", key: "save", name: "Save this look", meta: [], desc: "Keep every screen's wallpaper and colours under a short name, to come back to in one step (Fine-tune names it)." })
        out.push({ id: "looks", title: "Themes", shape: "look", items: looks, divider: -1, labeled: false, count: true })
        // the collection
        const on = name => screens.filter(s => fileName(s.image) === name).map(s => s.label)
        const walls = page.walls.map((w, i) => ({
            kind: "wall", key: "wall:" + w.name, name: "", file: w.name, path: page.dir + "/" + w.name, thumb: w.thumb, n: i + 1,
            onScreens: on(w.name), current: targets.some(s => fileName(s.image) === w.name),
            meta: on(w.name).length ? ["On the " + on(w.name).join(" and ")] : [], desc: w.name,
        }))
        out.push({ id: "walls", title: "Wallpapers", shape: "wall", items: walls, divider: -1, labeled: false, count: true })
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
            colours.push({ kind: "accent", key: "accent:" + r, role: r, name: r[0].toUpperCase() + r.slice(1), hex: String(tm.rice[r]),
                           current: !!ov[r], meta: [ov[r] ? "Hand-picked" : "From the wallpaper"],
                           desc: "Pick your own to mismatch on purpose; a new wallpaper on that screen brings the automatic one back." })
        out.push({ id: "colours", title: "Colours", shape: "chip", items: colours, divider: -1, labeled: true, count: false })
        // size
        const ui = page.ui || {}
        const sizes = [{ kind: "size", key: "size:auto", v: "auto", name: "Automatic", current: !!ui.auto,
                         meta: [ui.auto ? "Now" : "Each screen its standard size"], desc: "The same apparent size on every screen, whatever its resolution, size and distance." }]
        for (const v of [1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6])
            sizes.push({ kind: "size", key: "size:" + v, v: v, name: v.toFixed(1) + "×", current: !ui.auto && Math.abs((ui.size || 0) - v) < 0.001,
                         meta: [!ui.auto && Math.abs((ui.size || 0) - v) < 0.001 ? "Now" : "Overall"], desc: "Bars, the top band, popups and clocks on every screen, " + v.toFixed(1) + "× their standard size." })
        out.push({ id: "size", title: "Size", shape: "chip", items: sizes, divider: -1, labeled: true, count: false })
        // lighting: both keyboards at once (each one's own settings: Fine-tune)
        const dev = tm.lights && tm.lights.devices ? tm.lights.devices.find(d => d.ready) || tm.lights.devices[0] : null
        const st = dev ? dev.settings || {} : {}
        const L = (key, name, args, desc, cur) => ({ kind: "light", key: "light:" + key, name: name, args: args, desc: desc, current: !!cur,
                                                    effect: key, meta: [cur ? "Now" : "Laptop and Razer"] })
        const lighting = [
            L("auto", "Match wallpaper", ["--mode", "auto", "--style", "solid", "--on", "true"], "The keyboards wear the screen's accent and follow every re-theme.", st.on !== false && st.mode === "auto" && st.style === "solid"),
            L("gradient", "Gradient", ["--mode", "auto", "--style", "gradient", "--on", "true"], "The screen's two accents across the keys.", st.on !== false && st.mode === "auto" && st.style === "gradient"),
            L("breathe", "Breathing", ["--mode", "auto", "--style", "breathe", "--on", "true"], "The accents slowly brighter, then dimmer.", st.on !== false && st.mode === "auto" && st.style === "breathe"),
            L("spectrum", "Spectrum", ["--mode", "manual", "--effect", "spectrum", "--on", "true"], "Every colour in turn.", st.on !== false && st.mode === "manual" && st.effect === "spectrum"),
            L("off", "Off", ["--on", "false"], "Dark keyboards.", st.on === false),
        ]
        out.push({ id: "lighting", title: "Lighting", shape: "chip", items: lighting, divider: -1, labeled: true, count: false })
        rows = out
        rev++
    }
    onTargetChanged: build()
}
