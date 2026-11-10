import QtQuick
import QtQuick.Window
import QtCore
import "ClawdArt.js" as Art
import "ClawdActs.js" as Acts

// Clawd, the Claude Code creature and Atom Plasma's mascot, as pixel art that lives along with you.
// It follows your usage (sleepy, tired, then exhausted as a window fills up; it slumps by the
// hourglass and dozes when one runs out), what Claude Code is doing (types at a laptop, thinks with
// the Claude spark, hammers at shell commands, reads with a magnifier, spins a globe for the web,
// juggles subagents or sets two little Clawds to work, sweeps up a compaction), what its last answer
// was about (a tick and confetti when it's done, a wrench and a tick for a fix, a lightbulb for
// research, a thought bubble while background work runs, a sweat drop when it got stuck, a "?" when it
// asked you something, waving at you with the "?" when Claude Code waits on a permission), the time of
// day, the season and the weather.
// Off duty it never sleeps: it gets on with a hobby (`hobby`, thirty of them in ClawdActs.js: a book of
// fables, a handheld game, painting, knitting, fishing, a kite, a ukulele, noodles, origami, a puzzle
// cube, a skateboard, a campfire, a cat, pancakes in the morning, a telescope at night, a snowman when
// it snows, a pumpkin for Halloween...), a new one every five minutes, each with a little project that
// moves on as you watch. With music playing its headphones stay on whatever it does. Hover it and it
// greets you and follows the pointer with its eyes; stroke it back and forth and it melts a little;
// click it for one of some twenty acts, never one of the last few again (four quick clicks make it
// dizzy). A double click calls `summoned` (the widgets open Claude Code in a terminal).
//
// How it's drawn: one Canvas. ClawdArt.js turns the pose into a short list of coloured cells (22 x 10
// for the figure; hats, props and visitors reach out around it), snapped to whole device pixels of
// the window it's in (`cell`) so every cell is the same size on fractional scales, and the canvas is
// only repainted when that list changes. There are no items per pixel and nothing is bound per prop: a Clawd is one item,
// a few timers and this file's bindings.
//
// How it moves: every motion is an "act" (ClawdActs.js), a short list of stepped poses played as a
// burst, with weight to it: a crouch before a jump, a stretch in the air, a squash and a puff of dust
// on landing, legs that step. Between bursts it holds still, so the panel only redraws for a moment
// every few seconds: a smooth looping animation in a panel widget keeps plasmashell + KWin redrawing at
// full refresh (~27 W on the NVIDIA). `continuous` (the popup only) adds an idle bob and twinkles, and
// those move in device-pixel steps too (a handful of redraws a second, not one per screen refresh).
//
// One Clawd, many views: the bars, the desktop and the popup all show the same creature, so whatever it
// does on its own comes from the wall clock and the shared inputs, never from per-view chance or timers
// started at different moments. Its acts fire on the clock's beats (`Beat`), every bit of chance is a
// hash of the beat (Acts.chance), and its hobby and the hobby's progress are read off the clock, so
// every view does the same thing at the same moment without talking to the others. Only a click is
// passed on: the clicked Clawd writes the act to ~/.cache/clawd/poke.json and the others play it too. A
// hover stays with the Clawd under the pointer (it's the one looking at you).
Item {
    id: root

    // ---------- the situation (set by the widget) ----------
    property string mood: "happy"   // happy | sleep (no session for a while: off duty) | limited (a window ran out)
    property real usage: -1         // the fuller usage window, %: Clawd tires as it fills
    property bool working: false    // a Claude Code session is live (the status line keeps updating)
    property string activity: ""    // what Claude Code is doing (ClaudeActivity.qml): thinking | typing |
                                    // building | reading | web | juggling | sweeping | attention | waiting |
                                    // running | fixed | done | found | stuck | chat | idle
                                    // ("" without hook data: then `working` means typing)
    property bool music: false      // something is playing: off duty, its headphones are on
    property bool notice: false     // an important update waits (update-check.py): a small badge
    property bool celebrate: false  // a usage window just reset
    property bool warm: false       // using the session faster than its even pace (a blush)
    property string daypart: "day"  // morning | day | evening | night
    property bool weekend: false
    property string season: ""      // "" | halloween | xmas | newyear
    property string weather: ""     // "" | rain | snow
    property real sand: 1           // limited: share of the wait still to go (hourglass)
    property bool alert: false      // Claude asked for a check-in (ask.sh): big "!" badge
    signal alertClicked()           // clicked while the "!" is up (no act: the widget shows or settles it)
    signal summoned()               // double-clicked (not part of a faster spree): open Claude Code
    property var pal: ({})
    property real px: 8
    property bool interactive: true // hover greets, a click plays an act
    property bool animate: true     // pause everything (hidden, or behind a fullscreen window)
    property bool continuous: true  // the idle bob and twinkles (popup only)
    property bool hovered: false    // the pointer is over the widget around it (the eyes follow `look`)

    readonly property bool live: visible && animate
    readonly property bool looping: live && continuous

    // the scale it's really drawn at: its window's. (Screen.devicePixelRatio is the output's whole-number
    // scale on Wayland, 2 for a screen at 1.15, and cells snapped to that come out uneven.)
    readonly property real dpr: {
        const w = Window.window
        return w && w.devicePixelRatio > 0 ? w.devicePixelRatio : Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
    }
    readonly property int cell: Math.max(1, Math.round(px * dpr))      // device px per cell
    readonly property real unit: cell / dpr
    implicitWidth: 22 * unit
    implicitHeight: 10 * unit

    function col(name, fallback) { return pal[name] ?? fallback }

    // ---------- the state it's in ----------
    readonly property bool sitting: mood === "limited"
    // 0 fresh, 1 sleepy (50 %), 2 tired (75 %), 3 exhausted (90 %), 4 out of energy (a window ran out)
    readonly property int tired: sitting ? 4 : usage >= 90 ? 3 : usage >= 75 ? 2 : usage >= 50 ? 1 : 0
    // busy with: what Claude Code is doing (or what its last answer was about), else typing while a
    // session is live
    readonly property string doing: alert || sitting || activity === "idle" ? ""
                                  : activity ? activity : working ? "typing" : ""
    // off duty: nothing from Claude Code to show, so it gets on with its hobby
    readonly property bool idle: !doing && !sitting && !alert && !celebrate
    // the one thing it holds or works at
    readonly property string held: alert ? "" : sitting ? "hourglass"
        : doing === "typing" || doing === "thinking" ? "laptop"
        : ({ building: "hammer", reading: "magnifier", web: "globe", juggling: "balls", sweeping: "broom", fixed: "wrench" })[doing]
          ?? (idle ? (hobby === "coffee" ? "mug" : hobby) : tired >= 2 ? "mug" : "")
    // shown between bursts: the Claude spark while thinking, a "?" when it needs you, what the last
    // answer was about after it
    readonly property string restProp: ({ thinking: "spark", waiting: "ask", attention: "ask", running: "dots",
                                          done: "check", fixed: "check", found: "bulb", stuck: "sweat" })[doing] ?? ""
    readonly property string hat: held === "umbrella" ? "" : celebrate ? "party" : season === "xmas" ? "santa"
        : season === "newyear" ? "party" : season === "halloween" ? "witch" : daypart === "night" ? "nightcap" : ""
    readonly property bool shades: weekend && daypart === "day" && tired === 0 && idle
    // headphones stay on while something plays, whatever its hobby
    readonly property bool cans: music && idle
    // the night star sits where the right-hand props go
    readonly property bool star: daypart === "night" && idle
        && ["", "book", "game", "music", "mug", "knit", "uke", "bowl", "origami", "cube", "cat", "fire", "yoga", "rope"].indexOf(held) >= 0

    // ---------- the clock every view shares ----------
    // a timer on the wall clock's beats (whole multiples of `period` ms since the epoch), so every view
    // fires at the same moment; `tick` numbers the beat
    component Beat: Timer {
        id: b
        property real period: 1000
        property bool armed: false
        property real last: -1
        property bool built: false      // (handlers that fire while it's still being made can't see the JS globals)
        signal beat(real tick)
        function aim() { interval = Math.max(1, period - Date.now() % period); restart() }
        onArmedChanged: { if (!built) return; if (armed) aim(); else stop() }
        onPeriodChanged: if (built && armed) aim()
        Component.onCompleted: { built = true; if (armed) aim() }
        onTriggered: {
            const t = Math.round(Date.now() / period)
            if (t !== last) { last = t; b.beat(t) }
            aim()
        }
    }

    // ---------- off duty: a hobby, a new one every five minutes, the same in every view ----------
    readonly property real hobbySlot: 300000
    property string hobby: ""
    property string pinned: ""          // (the sheets and tests: this hobby, whatever the clock says)
    readonly property string hobbyText: Acts.hobby(hobby)?.text ?? ""      // "Knitting a scarf."
    property int prog: 0                // how far along its little project is (Acts.stage)
    property int beatK: 0               // the hobby's bursts since its slot began
    property bool growNow: false        // the plant grows at this watering
    property real slotNo: 0
    // the hobby at `at` (ms), and how far along it is: the beats since its slot began
    function syncHobby(at) {
        const slot = Math.floor(at / hobbySlot)
        const h = pinned || Acts.hobbyFor(slot, { tired: tired, daypart: daypart, weekend: weekend, season: season, weather: weather, music: music })
        const k = Math.max(0, Math.floor((at - slot * hobbySlot) / Acts.every(Acts.hobby(h).act)))
        slotNo = slot; beatK = k
        prog = Acts.stage(h, slot, k)
        growNow = Acts.grows(slot, k)
        hobby = h
    }
    onIdleChanged: if (idle) syncHobby(Date.now())
    onDaypartChanged: syncHobby(Date.now())
    onMusicChanged: syncHobby(Date.now())
    onTiredChanged: syncHobby(Date.now())
    onWeatherChanged: syncHobby(Date.now())
    onSeasonChanged: syncHobby(Date.now())
    onWeekendChanged: syncHobby(Date.now())
    onPinnedChanged: syncHobby(Date.now())
    onLiveChanged: if (live) { syncHobby(Date.now()); redraw.restart() }
    Component.onCompleted: { syncHobby(Date.now()); heldWas = held; heldSince = Date.now(); ready = true; redraw.restart() }

    // ---------- its colours ----------
    readonly property color base: col("claude", "#d97757")
    // worn out: the colour drains a little with each step of tiredness
    readonly property color worn: Qt.tint(base, Qt.alpha("#8d919c", [0, 0.06, 0.16, 0.28, 0.38][tired]))
    // the light follows the time of day: golden morning, rosy evening, moonlit night
    readonly property color body: daypart === "night" ? Qt.tint(worn, Qt.alpha(col("blue", "#8e9cf6"), 0.18))
                                : daypart === "evening" ? Qt.tint(worn, "#1aff6f91")
                                : daypart === "morning" ? Qt.tint(worn, "#16ffd27a") : worn
    // every named ink the art uses (ClawdArt.js), as strings for the canvas
    readonly property var inks: ({
        body: String(body), hi: String(Qt.lighter(body, 1.16)), lo: String(Qt.darker(body, 1.25)),
        bags: String(Qt.tint(Qt.darker(body, 1.45), "#30443a78")), ink: "#1f1e1d", cream: "#f3ede4", pink: "#ff6f96",
        claude: String(col("claude", "#d97757")), primary: String(col("primary", "#7aa2f7")),
        secondary: String(col("secondary", "#deb58e")), tertiary: String(col("tertiary", "#bb9af7")),
        red: String(col("red", "#f7768e")), yellow: String(col("yellow", "#e0af68")), cyan: String(col("cyan", "#7dcfff")),
        green: String(col("green", "#9ece6a")), magenta: String(col("magenta", "#ca95ec")), blue: String(col("blue", "#8e9cf6")),
        blue_dim: String(col("blue_dim", "#6d78c6")), yellow_bright: String(col("yellow_bright", "#f2c285")),
        cans_cup: String(Qt.darker(col("tertiary", "#bb9af7"), 1.6)), leaf_dark: String(Qt.darker(col("green", "#9ece6a"), 1.25)),
        alert_hi: String(Qt.lighter(col("red", "#f7768e"), 1.18)), notice_hi: String(Qt.lighter(col("green", "#9ece6a"), 1.18))
    })
    onInksChanged: canvas.requestPaint()

    // ---------- the pose: the rest pose, or the current frame of an act (`fx`) ----------
    readonly property var still: ({})
    property var fx: still
    property int lid: 0                 // a blink: 1 half shut, 2 shut
    property int look: 0                // where the pointer is: -1 | 0 | 1
    readonly property bool pointed: hovered || ma.containsMouse
    // its eyes are on what it's doing, until you come by
    readonly property string restEyes: alert || doing === "attention" || doing === "waiting" ? "wide" : sitting ? "sleep"
        : celebrate ? "joy" : doing === "thinking" ? "up" : doing === "stuck" ? "flat"
        : tired >= 3 ? "heavy" : tired >= 2 ? "half"
        : !pointed && ["book", "game", "knit", "cube", "origami", "bowl", "uke"].indexOf(held) >= 0 ? "down"
        : !pointed && held === "kite" ? "up" : "open"
    function blinked(s) {
        if (!lid || ["open", "wide", "half", "heavy", "up", "down"].indexOf(s) < 0) return s
        return lid === 1 && s !== "half" && s !== "heavy" ? "half" : "blink"
    }
    readonly property string eyeL: fx.eyeL ?? fx.eyes ?? blinked(restEyes)
    readonly property string eyeR: fx.eyeR ?? fx.eyes ?? blinked(restEyes)
    // arms: -1 drooping, 0 resting, 1 raised, 6 higher, 2 up high, 3 over the eyes, 5 held out, 4 hidden
    // (holding something in front with both hands: the prop draws the hands)
    readonly property bool twoHands: ["laptop", "book", "game", "knit", "uke", "bowl", "origami", "cube"].indexOf(held) >= 0
    readonly property int restArmL: twoHands ? 4 : tired >= 3 ? -1 : 0
    readonly property int restArmR: twoHands ? 4
        : ["umbrella", "globe", "wrench", "bubbles", "yoyo", "paint", "fish", "plane", "sparkler"].indexOf(held) >= 0 ? 1
        : held === "kite" ? 2 : tired >= 3 ? -1 : 0
    readonly property int armL: fx.armL ?? restArmL
    readonly property int armR: fx.armR ?? restArmR
    readonly property string mouth: fx.mouth ?? ""
    readonly property bool blush: fx.blush ?? (warm || celebrate)
    // the props' frame: a frame's own `f` for what that frame shows; what it holds follows `f` only in
    // its state's own acts (`mine`), and otherwise rests (the spark turned, the tick drawn, the bulb
    // lit, the bubble's dots all up)
    readonly property int restF: ({ spark: 4, check: 2, bulb: 1, dots: 3 })[restProp] ?? 0
    readonly property int f: fx.f ?? 0
    readonly property int hf: mine ? (fx.f ?? restF) : restF
    readonly property int gaze: fx.glance ?? (pointed ? look
        : ["hourglass", "magnifier", "globe", "hammer", "paint", "plant", "blocks", "telescope", "fish", "kite", "fire", "snowman",
           "pumpkin", "tree", "sparkler", "pan", "plane"].indexOf(held) >= 0
          || (held === "cat" && (prog < 3 || hat !== "")) || restProp === "dots" || restProp === "bulb" ? 1 : 0)

    property int twinkle: 0             // stars, confetti, steam, the campfire
    property int zz: 0                  // Zzz
    property int typed: 0               // keystrokes (the screen's light flickers)
    property int bounce: 0              // "!" badge (1 = up)
    property bool lowOn: true           // the low battery blinks
    property int wx: 0                  // the weather moves whenever Clawd does
    property real bob: 0                // popup only: the idle bob, in cells (whole device px)

    // ---------- drawing ----------
    // everything the picture depends on; a change composes it again (once per pass of the event loop)
    // and repaints only if the cells came out different
    readonly property var scene: ({
        fx: fx, f: f, hf: hf, held: held, rest: restProp, hat: hat, shades: shades, star: star, cans: cans,
        eyeL: eyeL, eyeR: eyeR, armL: armL, armR: armR, mouth: mouth, blush: blush, gaze: gaze,
        sitting: sitting, tired: tired, weather: weather, celebrate: celebrate, alert: alert, notice: notice,
        tw: twinkle, zz: zz, typed: typed, bounce: bounce, lowOn: lowOn, sand: sand, prog: prog, wx: wx, bob: bob, slot: slotNo
    })
    onSceneChanged: redraw.restart()
    onVisibleChanged: if (visible) redraw.restart()
    Timer { id: redraw; interval: 0; onTriggered: root.refresh() }
    property var cells: []
    property string drawn: "-"
    property int paints: 0              // (how often it really repainted: the tests and the bench read it)
    property bool broken: false
    function refresh() {
        if (!visible) return
        let list
        // (a pose the art trips over keeps the last picture, and says so once)
        try { list = Art.compose(scene) } catch (e) { if (!broken) { broken = true; console.warn("Clawd: can't draw", playing, held, e) } return }
        const sig = list.join()
        if (sig === drawn) return
        drawn = sig; cells = list
        canvas.requestPaint()
    }
    // a size in logical px that holds `n` device px and is itself whole in both: a Canvas keeps a whole
    // logical size and scales its picture by the screen's factor, so only then is one cell `cell` px
    function fit(n) {
        for (let k = n; k < n + 400; k++) { const w = k / dpr; if (Math.abs(w - Math.round(w)) < 1e-6) return Math.round(w) }
        return Math.ceil(n / dpr)
    }
    Canvas {
        id: canvas
        x: Art.X0 * root.unit
        y: Art.Y0 * root.unit
        width: root.fit(Art.COLS * root.cell)
        height: root.fit(Art.ROWS * root.cell)
        smooth: false
        antialiasing: false
        onPaint: { Art.paint(getContext("2d"), root.cells, root.inks, root.unit, root.dpr, width, height); root.paints++ }
        onAvailableChanged: if (available) requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }
    onCellChanged: canvas.requestPaint()

    // ---------- acts ----------
    property string playing: ""
    property int prio: 0                // 0 loops and idle, 1 hover, 2 clicks, 3 dizzy
    property bool mine: false           // the act is the state's own (its loop, or how it came on)
    property var frames: []
    property int fi: 0
    property var recent: []
    function pick(list, keep) {         // a random one, not one of the last few
        const fresh = list.filter(n => root.recent.indexOf(n) < 0)
        const pool = fresh.length ? fresh : list
        const n = pool[Math.floor(Math.random() * pool.length)]
        recent = recent.concat([n]).slice(-(keep || 2))
        return n
    }
    // `seed`: the beat (or the click) it's played for, so an act with chance in it goes the same way in
    // every view
    function play(name, level, seed, own, extra) {
        level = level || 0
        if (playing && level <= prio) return false
        const env = { prog: prog, k: beatK, grow: growNow, hat: hat, hands: twoHands, look: look, tired: tired }
        let list
        try { list = Acts.frames(name, seed ?? Math.floor(Date.now() / 1000), extra ? Object.assign(env, extra) : env) }
        catch (e) { console.warn("Clawd: no act", name, e); return false }
        if (!list || !list.length) return false
        frames = list; playing = name; prio = level; mine = !!own; fi = 0
        advance()
        return true
    }
    function advance() {
        if (fi >= frames.length) { player.stop(); playing = ""; prio = 0; mine = false; fx = still; return }
        const fr = frames[fi++]
        if (fr.tick) typed++
        if (fr.zz) zz++
        if (fr.tw) twinkle++
        if (fr.adv) prog += fr.adv
        if (fr.set !== undefined) prog = fr.set
        wx++
        fx = fr
        player.interval = fr.d || 120
        player.restart()
    }
    Timer { id: player; onTriggered: root.advance() }

    // ---------- what the pointer does ----------
    property real strokeAt: -1
    property int strokeDir: 0
    property var strokes: []
    function lookAt(t) {
        look = t < 0.36 ? -1 : t > 0.64 ? 1 : 0
        // stroked: the pointer going back and forth over it (not over the rest of its island)
        if (t < -0.25 || t > 1.25) { strokeAt = -1; return }
        if (strokeAt < 0) { strokeAt = t; return }
        if (Math.abs(t - strokeAt) < 0.12) return
        const dir = t > strokeAt ? 1 : -1
        strokeAt = t
        if (dir === strokeDir) return
        strokeDir = dir
        const now = Date.now()
        strokes = strokes.filter(x => now - x < 1600).concat([now])
        if (strokes.length >= 4 && !alert && !sitting) { strokes = []; play("petted", 2) }
    }
    function greet() {
        if (!live || alert) return
        strokeAt = -1; strokeDir = 0
        if (sitting) { play("peek", 1); return }
        // with its hands full it just smiles, winks, leans in or hops
        const o = twoHands ? ["wink", "smile", "blep", "hop", "nuzzle", "shy"]
                           : ["wave", "wave", "wink", "smile", "peekaboo", "bow", "blep", "hop", "tada", "nuzzle", "shy", "bounce"]
        if (hat && !twoHands) o.push("doff", "doff")
        play(pick(o, 3), 1)
    }
    property var clicks: []
    function poke() {
        if (alert) { alertClicked(); return }
        const t = Date.now()
        clicks = clicks.filter(c => t - c < 1600).concat([t])
        let name
        if (clicks.length >= 4) { clicks = []; name = "dizzy" }
        else if (sitting) name = pick(["sigh", "peek", "dream"], 1)
        else if (tired >= 2 && Math.random() < 0.55) name = pick(["yawn", "chug", "nod", "rub"], 2)
        else {
            const o = ["dance", "flip", "heart", "juggle", "magic", "melt", "shades", "sneeze", "flex", "surprise", "giggle", "spin",
                       "wink", "moonwalk", "cartwheel", "gum", "levelup", "rocket"]
            if (restArmR === 0 || twoHands) o.push("balloon", "sing", "popper")     // (its right hand is free for them)
            name = pick(o, 6)
        }
        const seed = Math.floor(t / 1000)
        play(name, name === "dizzy" ? 3 : 2, seed)
        share(name, seed)
    }
    // ---- clicks reach every view: ~/.cache/clawd/poke.json, replaced atomically (WatchedJson only sees
    // a file being replaced), one tiny process per click
    readonly property string uid: Math.random().toString(36).slice(2, 10)
    readonly property string pokeFile: String(StandardPaths.writableLocation(StandardPaths.GenericCacheLocation)).replace(/^file:\/\//, "") + "/clawd/poke.json"
    RiceShell { id: sh }
    function share(name, seed) {
        const event = JSON.stringify({ act: name, seed: seed, from: uid, ts: Date.now() / 1000 })
        sh.exec("clawd-poke", ["sh", "-c", 'mkdir -p "${2%/*}" && printf "%s\\n" "$1" > "$2.$$" && mv -f "$2.$$" "$2"', "sh", event, pokeFile])
    }
    WatchedJson {
        path: root.pokeFile
        active: root.live
        onChanged: {
            const e = value
            // another view was clicked just now (an old file read at start doesn't count)
            if (e && e.from !== root.uid && Date.now() / 1000 - Number(e.ts || 0) < 3)
                root.play(String(e.act), e.act === "dizzy" ? 3 : 2, Number(e.seed || 0))
        }
    }
    function hop() { play("hop", 1) }
    // how each after-answer state comes on (not for a view made while it's already there: the others
    // played it when it happened)
    onDoingChanged: {
        if (!ready || !live) return
        const enter = ({ done: "done", fixed: "fixed", found: "eureka", stuck: "oops", attention: "hail", chat: "hello" })[doing]
        if (enter) play(enter, 2, Math.floor(Date.now() / 1000), true)
    }
    // one thing put away and the next brought out, in a little puff: only when it had the last one for
    // a while (while Claude Code works, its tools change by the second)
    property bool ready: false
    property string heldWas: ""
    property real heldSince: 0
    onHeldChanged: {
        const from = heldWas, now = Date.now(), settled = now - heldSince > 12000
        heldWas = held; heldSince = now
        if (!ready || !live || !settled || alert || sitting || from === "hourglass") return
        const zf = Acts.zoneOf(from), zt = Acts.zoneOf(held)
        if (zf || zt) play("swap", 1, Math.floor(now / 1000), false, { from: from, zoneFrom: zf, zoneTo: zt })
    }

    // ---------- timing ----------
    // every timer that decides what Clawd does is a Beat on the shared clock, so all the views agree
    Beat {   // a blink every few seconds (now and then it skips one, or blinks twice); slower and longer when tired
        period: root.tired >= 1 ? 3600 : 4400
        armed: root.live && ["open", "wide", "half", "heavy", "up", "down"].indexOf(root.restEyes) >= 0 && !root.shades
        onBeat: tick => {
            const c = Acts.chance(tick, 41)
            if (c < 0.2) return
            blink.twice = c > 0.9
            blink.go()
        }
    }
    Timer {     // the lid: straight shut on the bars (two redraws), down and up through half in the popup
        id: blink
        property bool twice: false
        property int step: 0
        function go() { step = 0; next() }
        function next() {
            const slow = root.tired >= 2, soft = root.continuous
            const seq = soft ? [[1, 50], [2, slow ? 260 : 90], [1, 60], [0, 0]] : [[2, slow ? 340 : 140], [0, 0]]
            const s = seq[step++]
            root.lid = s[0]
            if (s[1] > 0) { interval = s[1]; restart() }
            else if (twice) { twice = false; step = 0; interval = 130; restart() }
        }
        onTriggered: next()
    }

    // each state's own loop: a short burst every few seconds (off duty: its hobby's)
    readonly property string loopAct: sitting ? "snore" : alert ? "" : celebrate ? "cheer"
        : ({ typing: "type", thinking: "think", building: "hammer", reading: "scan", web: "surf", juggling: "delegate",
             sweeping: "sweep", waiting: "ask", attention: "hail", running: "wait", done: "proud", fixed: "tighten",
             found: "glow", stuck: "shrug" })[doing]
          ?? (idle ? Acts.hobby(hobby)?.act ?? "" : tired >= 3 ? "nod" : tired >= 2 ? "yawn" : "")
    Beat {
        id: loop
        period: Acts.every(root.loopAct)
        armed: root.live && root.loopAct !== ""
        onBeat: tick => {
            if (root.idle) root.syncHobby(tick * loop.period)     // the hobby (and how far along it is) at this beat
            // a tired Clawd yawns or nods off over its work (or its hobby) now and then
            if ((root.doing || root.idle) && root.tired >= 2 && Acts.chance(tick, 1) < 0.18)
                root.play(root.tired >= 3 ? "nod" : "yawn", 0, tick)
            else root.play(root.loopAct, 0, tick, true)
        }
    }

    // off duty: the next hobby, on the five-minute mark
    Beat {
        period: root.hobbySlot
        armed: root.live && root.idle
        onBeat: tick => root.syncHobby(tick * root.hobbySlot)
    }

    // now and then, between the hobby's bursts (about every half minute, never on a regular rhythm):
    // a look around, a stretch, a few steps, and whoever drops by at this time of year
    Beat {
        period: 15000
        armed: root.live && root.idle
        onBeat: tick => {
            if (Acts.chance(tick, 31) >= 0.45) return
            const o = ["look", "look", "hop", "smile", "sway", "tap"]
            if (!root.twoHands) o.push("wave", "stretch", "whistle")
            if (root.held === "" || root.twoHands || root.held === "music" || root.held === "mug") o.push("pace")
            if (root.tired >= 1) o.push("yawn", "yawn")
            const month = new Date(tick * 15000).getMonth(), night = root.daypart === "night"
            const fair = !root.weather && root.held !== "kite" && root.held !== "telescope"
            if (night && root.held !== "telescope") o.push("stargaze")
            if (!night && fair && root.season !== "xmas") o.push("butterfly", root.hat === "witch" ? "butterfly" : "bird")
            if (!night && fair && month >= 8 && month <= 10) o.push("leaf", "leaf")
            if (!night && fair && month >= 2 && month <= 4) o.push("petal", "petal")
            if (night && fair && month >= 5 && month <= 7) o.push("firefly", "firefly")
            if (root.weather === "snow" || (fair && (month === 11 || month <= 1))) o.push("flake", "flake")
            if (root.season === "halloween") o.push("bat", "bat", "ghost")
            root.play(Acts.pickAt(o, tick, 32), 0, tick)
        }
    }

    // the low battery blinks (only when nearly out): on 1.5 s, off 0.5 s
    Beat {
        period: 500
        armed: root.live && root.tired === 3
        onBeat: tick => root.lowOn = tick % 4 !== 3
    }

    // the "!" badge hops: up for a quarter second, down for three (stepped, so it's cheap in the panel)
    Beat {
        period: 250
        armed: root.live && root.alert
        onBeat: tick => root.bounce = tick % 4 === 0 ? 1 : 0
    }
    onAlertChanged: if (!alert) bounce = 0

    // popup only: stars and steam twinkle, and a soft idle bob read off the clock. The bob moves in
    // whole device pixels, so it repaints a few times a second instead of once per screen refresh
    Timer { interval: 650; running: root.looping; repeat: true; onTriggered: root.twinkle++ }
    Timer {
        interval: 80; repeat: true
        running: root.looping && root.playing === ""
        onRunningChanged: if (!running) root.bob = 0
        onTriggered: {
            const period = root.sitting ? 3600 : root.tired >= 2 ? 2200 : 1400, reach = root.sitting ? 0.25 : 0.45
            const y = -reach * (1 - Math.cos(2 * Math.PI * (Date.now() % period) / period)) / 2
            const snapped = Math.round(y * root.cell) / root.cell
            if (snapped !== root.bob) root.bob = snapped
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: root.interactive
        cursorShape: Qt.PointingHandCursor
        onEntered: root.greet()
        onPositionChanged: mouse => root.lookAt(mouse.x / width)
        onClicked: root.poke()
        // a handled double click swallows its second click, so it still counts as a poke (four quick
        // clicks stay dizzy). It summons only as a lone pair: a third click soon after cancels it
        property var taps: []
        onPressed: {
            const t = Date.now()
            taps = taps.filter(c => t - c < 700).concat([t])
            summon.stop()
        }
        onDoubleClicked: {
            root.poke()
            if (taps.length === 2) summon.restart()
        }
    }
    Timer { id: summon; interval: 320; onTriggered: root.summoned() }
}
