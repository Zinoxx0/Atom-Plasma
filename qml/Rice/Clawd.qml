import QtQuick
import QtQuick.Window

// Clawd, the Claude Code creature and Atom Plasma's mascot, as pixel art that lives along with you.
// It follows your usage (sleepy, tired, then exhausted as a window fills up; it slumps by the
// hourglass and dozes when one runs out), what Claude Code is doing (types at a laptop, thinks with
// the Claude spark, hammers at shell commands, reads with a magnifier, spins a globe for the web,
// juggles subagents, sweeps up a compaction, waits for you with a "?", hops with a tick when done),
// the time of day, the season and (on the desktop) the weather. Hover it and it greets you and
// follows the pointer with its eyes; click it for one of a dozen little acts, never the same one
// twice in a row (four quick clicks make it dizzy).
//
// The art is drawn in grid cells (22 x 10; hats, bubbles and props poke out around it) and scaled by
// `px`, snapped to whole device pixels (`unit`) so every cell is the same size on fractional scales.
// Every motion is an "act": a short list of stepped poses (`acts`), played as a burst, so the panel
// only redraws for a moment every few seconds. A smooth looping animation in a panel widget keeps
// plasmashell + KWin redrawing at full refresh (~27 W on the NVIDIA), so `continuous` (the popup
// only) adds the soft idle bob and livelier timing.
Item {
    id: root

    // ---------- the situation (set by the widget) ----------
    property string mood: "happy"   // happy | sleep (no session for a while) | limited (a window ran out);
                                    // sweat / panic (older callers) read as tired / exhausted
    property real usage: -1         // the fuller usage window, %: Clawd tires as it fills
    property bool working: false    // a Claude Code session is live (the status line keeps updating)
    property string activity: ""    // what Claude Code is doing (ClaudeActivity.qml): thinking | typing |
                                    // building | reading | web | juggling | sweeping | waiting | done | idle
                                    // ("" without hook data: then `working` means typing)
    property bool celebrate: false  // a usage window just reset
    property bool warm: false       // using the session faster than its even pace (a blush)
    property string daypart: "day"  // morning | day | evening | night
    property bool weekend: false
    property string season: ""      // "" | halloween | xmas | newyear
    property string weather: ""     // "" | rain | snow (the desk passes it)
    property real sand: 1           // limited: share of the wait still to go (hourglass)
    property bool alert: false      // Claude asked for a check-in (ask.sh): big "!" badge
    property var pal: ({})
    property real px: 8
    property bool interactive: true // hover greets, a click plays an act
    property bool animate: true     // pause everything when hidden
    property bool continuous: true  // smooth idle bob and livelier timing (popup only)
    property bool hovered: false    // the pointer is over the widget around it (the eyes follow `look`)

    readonly property bool live: visible && animate
    readonly property bool looping: live && continuous

    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
    readonly property real unit: Math.max(1, Math.round(px * dpr)) / dpr
    implicitWidth: 22 * unit
    implicitHeight: 10 * unit

    function col(name, fallback) { return pal[name] ?? fallback }

    // ---------- the state it's in ----------
    readonly property bool asleep: mood === "sleep" && !celebrate && !alert
    readonly property bool sitting: mood === "limited"
    // 0 fresh, 1 sleepy (50 %), 2 tired (75 %), 3 exhausted (90 %), 4 out of energy (a window ran out)
    readonly property int tired: sitting ? 4 : usage >= 90 ? 3 : usage >= 75 ? 2 : usage >= 50 ? 1
                               : usage < 0 && mood === "panic" ? 3 : usage < 0 && mood === "sweat" ? 2 : 0
    // busy with: what Claude Code is doing, else typing while a session is live
    readonly property string doing: alert || asleep || sitting || activity === "idle" ? ""
                                  : activity ? activity : working ? "typing" : ""
    // the one thing it holds or works at
    readonly property string held: alert || asleep ? "" : sitting ? "hourglass"
        : doing === "typing" || doing === "thinking" ? "laptop"
        : ({ building: "hammer", reading: "magnifier", web: "globe", juggling: "balls", sweeping: "broom" })[doing]
          ?? (weather === "rain" ? "umbrella" : daypart === "morning" || tired >= 2 ? "mug" : "")
    // shown between bursts: the Claude spark while thinking, a "?" while waiting for you
    readonly property string restProp: doing === "thinking" ? "spark" : doing === "waiting" ? "ask" : ""
    readonly property string hat: held === "umbrella" ? "" : celebrate ? "party" : season === "xmas" ? "santa"
        : season === "newyear" ? "party" : season === "halloween" ? "witch" : daypart === "night" ? "nightcap" : ""
    readonly property bool idle: !doing && !asleep && !sitting && !alert && !celebrate
    readonly property bool shades: weekend && daypart === "day" && tired === 0 && idle && held === ""
    readonly property bool star: daypart === "night" && idle && held !== "umbrella"

    readonly property color base: asleep ? "#b98a78" : col("claude", "#d97757")
    // worn out: the colour drains a little with each step of tiredness
    readonly property color worn: Qt.tint(base, Qt.alpha("#8d919c", [0, 0.06, 0.16, 0.28, 0.38][tired]))
    // the light follows the time of day: golden morning, rosy evening, moonlit night
    readonly property color body: daypart === "night" ? Qt.tint(worn, Qt.alpha(col("blue", "#8e9cf6"), 0.18))
                                : daypart === "evening" ? Qt.tint(worn, "#1aff6f91")
                                : daypart === "morning" ? Qt.tint(worn, "#16ffd27a") : worn
    readonly property color hi: Qt.lighter(body, 1.16)
    readonly property color lo: Qt.darker(body, 1.25)
    readonly property color bags: Qt.tint(Qt.darker(body, 1.45), "#30443a78")
    readonly property color ink: "#1f1e1d"
    readonly property color cream: "#f3ede4"
    readonly property color pink: "#ff6f96"

    // ---------- the pose: the rest pose, or the current frame of an act (`fx`) ----------
    property var fx: ({})
    property bool blinking: false
    property int glance: 0              // idle look-around
    property int look: 0                // where the pointer is: -1 | 0 | 1
    readonly property bool pointed: hovered || ma.containsMouse
    readonly property string restEyes: alert ? "wide" : sitting || asleep ? "sleep" : celebrate ? "joy"
        : doing === "waiting" ? "wide" : doing === "thinking" ? "up" : tired >= 3 ? "heavy" : tired >= 2 ? "half" : "open"
    function blinked(s) { return blinking && ["open", "wide", "half", "heavy", "up"].indexOf(s) >= 0 ? "blink" : s }
    readonly property string eyeL: fx.eyeL ?? fx.eyes ?? blinked(restEyes)
    readonly property string eyeR: fx.eyeR ?? fx.eyes ?? blinked(restEyes)
    // arms: -1 drooping, 0 resting, 1 raised, 2 up high, 3 over the eyes, 4 at the keyboard
    readonly property int restArmL: held === "laptop" ? 4 : tired >= 3 ? -1 : 0
    readonly property int restArmR: held === "laptop" ? 4 : held === "umbrella" || held === "globe" ? 1 : tired >= 3 ? -1 : 0
    readonly property int armL: fx.armL ?? restArmL
    readonly property int armR: fx.armR ?? restArmR
    readonly property string mouth: fx.mouth ?? ""
    readonly property bool blush: fx.blush ?? (warm || celebrate)
    readonly property int f: fx.f ?? (restProp === "spark" ? 4 : 0)        // the prop's frame
    readonly property int gaze: fx.glance ?? (pointed ? look : glance !== 0 ? glance
        : ["hourglass", "magnifier", "globe", "hammer"].indexOf(held) >= 0 ? 1 : 0)
    function has(name) { return held === name || restProp === name || fx.prop === name || fx.prop2 === name }

    property int twinkle: 0             // stars, confetti, steam
    property int zz: 0                  // Zzz
    property int typed: 0               // keystrokes (the screen's light flickers)
    property int bounce: 0              // "!" badge (1 = up)
    property bool lowOn: true           // the low battery blinks

    // ---------- acts ----------
    function seq(n, d, fn) { const a = []; for (let i = 0; i < n; i++) a.push(Object.assign({ d: d }, fn(i))); return a }
    readonly property var acts: ({
        // hover greetings
        hop:      [{ d: 70, dy: -1 }, { d: 90, dy: -2 }, { d: 70, dy: -1 }, { d: 80 }],
        wave:     [{ d: 150, armR: 1 }, { d: 170, armR: 2, eyes: "joy" }, { d: 150, armR: 1, eyes: "joy" },
                   { d: 170, armR: 2, eyes: "joy" }, { d: 220, armR: 1 }],
        wink:     [{ d: 80, eyeR: "blink" }, { d: 560, eyeR: "joy", blush: true }, { d: 100, eyeR: "blink" }],
        smile:    [{ d: 700, eyes: "joy", blush: true, mouth: "smile" }],
        peekaboo: [{ d: 420, armL: 3, armR: 3, eyes: "hidden" }, { d: 120, armL: 1, armR: 1, eyes: "wide" },
                   { d: 560, armL: 2, armR: 2, eyes: "joy", mouth: "smile" }],
        bow:      [{ d: 150, sit: 1, eyes: "blink", armL: -1, armR: -1 }, { d: 460, sit: 1, eyes: "sleep", armL: -1, armR: -1 }, { d: 140 }],
        blep:     [{ d: 650, eyes: "joy", mouth: "tongue" }],
        // asleep or slumped: opens one eye at you
        peek:     [{ d: 1100, eyeL: "half", eyeR: "sleep" }],

        // clicks
        dance:    seq(10, 130, i => ({ dx: [0, -1, 0, 1][i % 4], armL: i % 2 ? 2 : 0, armR: i % 2 ? 0 : 2, eyes: "joy", prop: "note", f: i })),
        flip:     [{ d: 70, dy: -1 }, { d: 70, dy: -2, spin: 90 }, { d: 70, dy: -3, spin: 180, eyes: "joy" },
                   { d: 70, dy: -2, spin: 270 }, { d: 70, dy: -1 }, { d: 90 }, { d: 420, eyes: "joy", armL: 2, armR: 2 }],
        heart:    seq(7, 130, i => ({ eyes: i < 6 ? "heart" : "joy", blush: true, prop: "heart", f: i })),
        juggle:   seq(14, 110, i => ({ armL: i % 2 ? 1 : 0, armR: i % 2 ? 0 : 1, eyes: "up", prop: "balls", f: i })),
        magic:    [{ d: 180, armL: 1, armR: 1, eyes: "up" }]
                  .concat(seq(6, 110, i => ({ armL: 2, armR: 2, eyes: "up", prop: "spark", f: i })))
                  .concat([{ d: 520, armL: 2, armR: 2, eyes: "star", prop: "spark", f: 4, prop2: "sparkle" }]),
        melt:     [{ d: 140, eyes: "half" }, { d: 160, eyes: "sleep", sit: 1, armL: -1, armR: -1 },
                   { d: 650, hide: true, prop: "puddle", f: 0 }, { d: 260, hide: true, prop: "puddle", f: 1 },
                   { d: 80, dy: -2, eyes: "wide" }, { d: 80, dy: -1, eyes: "wide" }, { d: 260, eyes: "joy" }],
        shades:   [{ d: 80, prop: "drop", f: 0 }, { d: 80, prop: "drop", f: 1 }, { d: 80, prop: "drop", f: 2 },
                   { d: 1100, prop: "drop", f: 3, armR: 1 }, { d: 160, prop: "drop", f: 3 }],
        sneeze:   [{ d: 280, eyes: "half", mouth: "o" }, { d: 340, eyes: "sleep", mouth: "O", dy: -1 },
                   { d: 90, eyes: "sleep", dx: 1, prop: "puff", f: 0 }, { d: 140, prop: "puff", f: 1, eyes: "sleep" },
                   { d: 170, prop: "puff", f: 2, eyes: "blink" }, { d: 220 }],
        flex:     [{ d: 220, armL: 2, armR: 2, eyes: "joy" }, { d: 140, armL: 1, armR: 1 },
                   { d: 420, armL: 2, armR: 2, eyes: "joy", prop: "sparkle", f: 0 }, { d: 260, armL: 2, armR: 2, eyes: "joy", prop: "sparkle", f: 1 }],
        surprise: [{ d: 110, eyes: "wide", mouth: "o", prop: "bang", dy: -1 }, { d: 110, eyes: "wide", mouth: "o", prop: "bang", dy: -2 },
                   { d: 460, eyes: "wide", prop: "bang", armL: 1, armR: 1 }, { d: 150, eyes: "blink" }],
        giggle:   seq(8, 90, i => ({ dx: i % 2, eyes: "joy", blush: true, mouth: "smile" })),
        spin:     seq(8, 85, i => ({ flip: i % 2 === 1, glance: i % 2 ? -1 : 1 })).concat([{ d: 360, eyes: "joy", armL: 2, armR: 2 }]),
        dizzy:    seq(14, 95, i => ({ dx: [0, 1, 0, -1][i % 4], eyes: "dizzy", prop: "stars", f: i })).concat([{ d: 500, eyes: "dizzy", prop: "stars", f: 0 }]),
        startle:  [{ d: 120, eyes: "wide", mouth: "o", prop: "bang", dy: -2 }, { d: 120, eyes: "wide", prop: "bang", dy: -1 },
                   { d: 650, eyes: "wide" }, { d: 500, eyes: "half" }, { d: 300, eyes: "sleep" }],
        sigh:     [{ d: 520, eyes: "half", glance: 1 }, { d: 480, eyes: "sleep", mouth: "o" }, { d: 320, eyes: "half" }],

        // tired
        yawn:     [{ d: 220, eyes: "half", mouth: "o" }, { d: 760, eyes: "sleep", mouth: "O", armL: 2, armR: 2, dy: -1 },
                   { d: 220, eyes: "sleep", mouth: "o", armL: 1, armR: 1 }, { d: 260, eyes: "half" }],
        chug:     [{ d: 200, armR: 1, prop: "cup", f: 0 }, { d: 700, armR: 2, prop: "cup", f: 1, eyes: "sleep" },
                   { d: 160, armR: 1, prop: "cup", f: 0, eyes: "wide" }, { d: 420, eyes: "wide", prop: "bang", dy: -1 }],
        nod:      [{ d: 520, eyes: "sleep" }, { d: 420, eyes: "sleep", sit: 1, prop: "z", f: 0 },
                   { d: 420, eyes: "sleep", sit: 1, prop: "z", f: 1 }, { d: 90, eyes: "wide", dy: -1 },
                   { d: 340, eyes: "wide" }, { d: 220, eyes: "heavy" }],

        // working
        type:     seq(8, 120, i => ({ hl: i % 2, hr: 1 - i % 2, tick: i % 2 === 0 })),
        think:    seq(7, 120, i => ({ prop: "spark", f: [0, 1, 2, 3, 4, 5, 4][i] })),
        hammer:   [{ d: 160, armR: 1, f: 0 }, { d: 90, armR: 0, f: 1 }, { d: 160, armR: 1, f: 0 },
                   { d: 90, armR: 0, f: 1 }, { d: 200, armR: 1, f: 0 }],
        scan:     seq(8, 170, i => ({ f: [0, 1, 2, 3, 2, 1, 0, 0][i] })),
        surf:     seq(8, 150, i => ({ f: i % 4 })),
        sweep:    seq(8, 130, i => ({ f: i % 4 })),
        ask:      [{ d: 110, dy: -1, f: 1 }, { d: 110, f: 1 }, { d: 160 }],
        done:     [{ d: 90, dy: -1, eyes: "joy", prop: "check", f: 0 }, { d: 90, dy: -2, eyes: "joy", prop: "check", f: 1, armL: 2, armR: 2 },
                   { d: 90, dy: -1, eyes: "joy", prop: "check", f: 2, armL: 2, armR: 2 }, { d: 900, eyes: "joy", prop: "check", f: 2, armL: 2, armR: 2 },
                   { d: 220, eyes: "joy", blush: true }],
        cheer:    seq(4, 180, i => ({ armL: (i + 1) % 2 ? 2 : 0, armR: (i + 1) % 2 ? 2 : 0, eyes: "joy", tw: true })),
        snore:    [{ d: 10, zz: true }],
        rain:     seq(6, 120, i => ({ f: i })),
        flakes:   seq(6, 220, i => ({ f: i })),

        // now and then
        look:     () => [{ d: 1500, glance: Math.random() < 0.5 ? -1 : 1 }],
        stretch:  [{ d: 200, armL: 1, armR: 1 }, { d: 720, armL: 2, armR: 2, eyes: "sleep", dy: -1 }, { d: 200, armL: 1, armR: 1 }],
        whistle:  seq(7, 190, i => ({ mouth: "o", eyes: "joy", prop: "note", f: i })),
        sip:      [{ d: 200, armR: 1, prop: "cup", f: 0 }, { d: 760, armR: 2, prop: "cup", f: 1, eyes: "sleep" },
                   { d: 200, armR: 1, prop: "cup", f: 0 }, { d: 320, eyes: "joy" }],
        stargaze: seq(4, 420, i => ({ eyes: "up", glance: 1, tw: true })),
        butterfly: seq(12, 150, i => ({ prop: "fly", f: i, glance: i < 5 ? -1 : 1, eyes: i === 5 || i === 6 ? "joy" : undefined })),
        bat:      seq(10, 130, i => ({ prop: "bat", f: i, glance: i < 5 ? -1 : 1, eyes: i === 4 ? "wide" : undefined })),
    })

    property string playing: ""
    property int prio: 0                // 0 loops and idle, 1 hover, 2 clicks, 3 dizzy
    property var frames: []
    property int fi: 0
    property var recent: []
    function pick(list) {               // a random one, not one of the last two
        const fresh = list.filter(n => root.recent.indexOf(n) < 0)
        const pool = fresh.length ? fresh : list
        const n = pool[Math.floor(Math.random() * pool.length)]
        recent = recent.concat([n]).slice(-2)
        return n
    }
    function play(name, level) {
        level = level || 0
        const a = acts[name]
        if (!a || (playing && level <= prio)) return false
        frames = typeof a === "function" ? a() : a
        playing = name; prio = level; fi = 0
        advance()
        return true
    }
    function advance() {
        if (fi >= frames.length) { player.stop(); playing = ""; prio = 0; fx = ({}); return }
        const fr = frames[fi++]
        if (fr.tick) typed++
        if (fr.zz) zz++
        if (fr.tw) twinkle++
        fx = fr
        player.interval = fr.d || 120
        player.restart()
    }
    Timer { id: player; onTriggered: root.advance() }

    // ---------- what the pointer does ----------
    function lookAt(t) { look = t < 0.36 ? -1 : t > 0.64 ? 1 : 0 }
    function greet() {
        if (!live || alert) return
        if (asleep || sitting) { play("peek", 1); return }
        play(pick(["wave", "wave", "wink", "smile", "peekaboo", "bow", "blep", "hop"]), 1)
    }
    property var clicks: []
    function poke() {
        const t = Date.now()
        clicks = clicks.filter(c => t - c < 1600).concat([t])
        if (clicks.length >= 4) { clicks = []; play("dizzy", 3); return }
        if (asleep) { play("startle", 2); return }
        if (sitting) { play(pick(["sigh", "peek"]), 2); return }
        if (tired >= 2 && Math.random() < 0.55) { play(pick(["yawn", "chug", "nod"]), 2); return }
        play(pick(["dance", "flip", "heart", "juggle", "magic", "melt", "shades", "sneeze", "flex", "surprise",
                   "giggle", "spin", "wink"]), 2)
    }
    function hop() { play("hop", 1) }
    onDoingChanged: if (doing === "done") play("done", 2)

    // ---------- drawing ----------
    component Px: Rectangle { width: 1; height: 1; antialiasing: false }
    // a little pixel picture: rows of characters, each mapped to a colour by `inks` ("." is empty)
    component Pic: Item {
        id: pic
        property var rows: []
        property var inks: ({})
        Repeater {
            model: {
                const out = []
                pic.rows.forEach((r, y) => { for (let x = 0; x < r.length; x++) if (r[x] !== ".") out.push({ x: x, y: y, k: r[x] }) })
                return out
            }
            Rectangle {
                required property var modelData
                x: modelData.x; y: modelData.y; width: 1; height: 1; antialiasing: false
                color: pic.inks[modelData.k] ?? "magenta"
            }
        }
    }
    component Arm: Item {
        id: arm
        property int pose: 0            // as armL / armR
        property bool lhs: true
        property color c
        property color shade
        Px { visible: arm.pose >= -1 && arm.pose <= 1; x: arm.lhs ? 2 : 16; y: 4 - arm.pose; width: 2; height: 2; color: arm.c }
        // up high: reaching past the head
        Px { visible: arm.pose === 2; x: arm.lhs ? 2 : 16; y: 1; width: 2; height: 2; color: arm.c }
        Px { visible: arm.pose === 2; x: arm.lhs ? 3 : 16; y: 3; color: arm.c }
        // over the eyes
        Px { visible: arm.pose === 3; x: arm.lhs ? 5 : 12; y: 2; width: 3; height: 2; color: arm.shade }
    }
    component Eye: Item {
        id: eye
        property string s: "open"
        property int ex: 6
        property int g: ex
        property bool lhs: true
        property color ink
        property color lid
        property color bag
        readonly property bool arc: s === "joy" || s === "sleep"
        Px { visible: eye.s === "open"; x: eye.g; y: 2; height: 2; color: eye.ink }
        Px { visible: eye.s === "up"; x: eye.g; y: 1; height: 2; color: eye.ink }
        Px { visible: eye.s === "blink" || eye.s === "half" || eye.s === "heavy"; x: eye.g; y: 3; color: eye.ink }
        Px { visible: eye.s === "half"; x: eye.g; y: 2; color: eye.lid }
        // exhausted: the lid droops towards the outer corner, a bag underneath
        Px { visible: eye.s === "heavy"; x: eye.lhs ? eye.g - 1 : eye.g; y: 2; width: 2; color: eye.lid }
        Px { visible: eye.s === "heavy"; x: eye.g; y: 4; color: eye.bag }
        Px { visible: eye.s === "wide"; x: eye.lhs ? eye.ex : eye.ex - 1; y: 2; width: 2; height: 2; color: eye.ink }
        Px { visible: eye.s === "flat"; x: eye.ex - 1; y: 3; width: 3; color: eye.ink }
        // ^ ^ overjoyed, ‿ ‿ asleep
        Px { visible: eye.arc; x: eye.ex; y: eye.s === "joy" ? 2 : 3; color: eye.ink }
        Px { visible: eye.arc; x: eye.ex - 1; y: eye.s === "joy" ? 3 : 2; color: eye.ink }
        Px { visible: eye.arc; x: eye.ex + 1; y: eye.s === "joy" ? 3 : 2; color: eye.ink }
        Pic { visible: eye.s === "dizzy"; x: eye.ex - 1; y: 1; rows: ["x.x", ".x.", "x.x"]; inks: ({ x: eye.ink }) }
        Pic { visible: eye.s === "heart"; x: eye.ex - 1; y: 1; rows: ["x.x", "xxx", ".x."]; inks: ({ x: "#ff4f86" }) }
        Pic { visible: eye.s === "star"; x: eye.ex - 1; y: 1; rows: [".x.", "xxx", ".x."]; inks: ({ x: "#fff4cf" }) }
    }

    Item {
        id: art
        width: 22
        height: 10
        scale: root.unit
        transformOrigin: Item.TopLeft

        // ground shadow, fainter in the air
        Rectangle {
            x: 3.5; y: 9.75; width: 13; height: 0.6; radius: 0.3
            color: "black"
            opacity: (root.fx.hide ? 0.12 : 0.22) * (1 + Math.min(0, figure.y + bob.y) / 4)
        }

        // melted into a puddle (an act)
        Loader {
            active: root.fx.prop === "puddle"
            sourceComponent: Component {
                Item {
                    Px { x: 6; y: 6; width: 8; color: root.hi }
                    Px { x: 4; y: 7; width: 12; color: root.body }
                    Px { x: 2; y: 8; width: 16; color: root.body }
                    Px { x: 1; y: 9; width: 18; color: root.lo }
                    Px { x: 7; y: 7; color: root.ink }
                    Px { x: 12; y: 7; color: root.ink }
                    Px { visible: root.f === 1; x: 0; y: 8; color: root.hi }
                    Px { visible: root.f === 1; x: 19; y: 8; color: root.hi }
                }
            }
        }

        Item {
            id: bob                     // popup only: the soft idle bob
            Item {
                id: figure
                x: root.fx.dx ?? 0
                y: root.fx.dy ?? 0
                visible: !root.fx.hide
                transform: [
                    Rotation { origin.x: 10; origin.y: 5; angle: root.fx.spin ?? 0 },
                    Scale { origin.x: 10; xScale: root.fx.flip ? -1 : 1 }
                ]

                // legs, folded under while sitting
                Repeater {
                    model: [5, 7, 12, 14]
                    Px {
                        required property int modelData
                        x: modelData; y: root.sitting ? 9 : 8
                        height: root.sitting ? 1 : 2
                        color: root.lo
                    }
                }

                Item {
                    id: upper
                    y: (root.sitting ? 1 : 0) + (root.fx.sit ?? 0)

                    // body: top light, darker underside
                    Px { x: 4; width: 12; height: 8; color: root.body }
                    Px { x: 5; width: 10; color: root.hi }
                    Px { x: 4; y: 7; width: 12; color: root.lo }

                    // the laptop screen's light on its face
                    Px {
                        visible: root.held === "laptop"
                        x: 4; width: 12; height: 4
                        color: root.col("primary", "#e9a863")
                        opacity: 0.1 + 0.07 * (root.typed % 2)
                    }

                    // snow: a scarf
                    Item {
                        visible: root.weather === "snow" && !root.asleep
                        Px { x: 4; y: 5; width: 12; color: "#d9474f" }
                        Px { x: 6; y: 5; color: "#f08a8f" }
                        Px { x: 10; y: 5; color: "#f08a8f" }
                        Px { x: 12; y: 6; width: 2; height: 2; color: "#d9474f" }
                    }

                    Arm { pose: root.armL; lhs: true; c: root.body; shade: root.lo }
                    Arm { pose: root.armR; lhs: false; c: root.body; shade: root.lo }

                    Eye { s: root.eyeL; ex: 6; g: 6 + root.gaze; lhs: true; ink: root.ink; lid: root.lo; bag: root.bags }
                    Eye { s: root.eyeR; ex: 13; g: 13 + root.gaze; lhs: false; ink: root.ink; lid: root.lo; bag: root.bags }
                    Px { visible: root.blush; x: 5; y: 4; color: "#f58c9a"; opacity: 0.8 }
                    Px { visible: root.blush; x: 14; y: 4; color: "#f58c9a"; opacity: 0.8 }

                    // mouth, only for a moment: o surprised, O yawning, a smile, a blep
                    Px { visible: root.mouth === "o"; x: 9; y: 4; width: 2; height: 2; color: root.ink }
                    Px { visible: root.mouth === "O"; x: 9; y: 4; width: 2; height: 3; color: root.ink }
                    Px { visible: root.mouth === "O"; x: 9; y: 6; width: 2; color: "#d8566a" }
                    Pic { visible: root.mouth === "smile"; x: 8; y: 4; rows: ["x..x", ".xx."]; inks: ({ x: root.ink }) }
                    Pic { visible: root.mouth === "tongue"; x: 9; y: 4; rows: ["xx", ".p"]; inks: ({ x: root.ink, p: root.pink }) }

                    // weekend daytime: shades; and the ones that drop in (an act)
                    Item {
                        visible: root.shades || root.fx.prop === "drop"
                        y: root.fx.prop === "drop" ? [-5, -3, -1, 0][root.f] : 0
                        Px { x: 4; y: 2; width: 12; color: "#141318" }
                        Px { x: 5; y: 3; width: 3; color: "#141318" }
                        Px { x: 12; y: 3; width: 3; color: "#141318" }
                        Px { x: 5; y: 2; color: "#5d5868" }
                        Px { x: 12; y: 2; color: "#5d5868" }
                    }

                    // night cap (Santa hat in December), drooping to the left
                    Item {
                        id: cap
                        visible: root.hat === "nightcap" || root.hat === "santa"
                        readonly property color c: root.hat === "santa" ? "#d63a48" : root.col("blue_dim", "#6d78c6")
                        readonly property color trim: root.hat === "santa" ? root.cream : root.col("blue", "#8e9cf6")
                        Px { x: 5; y: -4; width: 5; color: cap.c }
                        Px { x: 3; y: -3; color: cap.c }
                        Px { x: 6; y: -3; width: 7; color: cap.c }
                        Px { x: 5; y: -2; width: 10; color: cap.c }
                        Px { x: 4; y: -1; width: 12; color: cap.trim }
                        Rectangle { x: 2; y: -2; width: 2; height: 2; radius: 0.7; color: root.cream }
                    }
                    // party hat
                    Item {
                        visible: root.hat === "party"
                        Px { x: 7; y: -1; width: 6; color: root.col("magenta", "#ca95ec") }
                        Px { x: 8; y: -2; width: 4; color: root.col("cyan", "#70d3f6") }
                        Px { x: 9; y: -3; width: 2; color: root.col("yellow", "#e2ae69") }
                        Px { x: 9; y: -4; width: 2; color: root.cream }
                    }
                    // Halloween week: a witch's hat with a bent tip
                    Pic {
                        visible: root.hat === "witch"
                        x: 3; y: -6
                        rows: ["........kk....",
                               ".......kk.....",
                               "......kkkk....",
                               ".....kkkkkk...",
                               "....oooooooo..",
                               "kkkkkkkkkkkkkk"]
                        inks: ({ k: "#3a2853", o: "#f2994a" })
                    }

                    // ---- what it holds or works at ----
                    // laptop: the lid's back to us with the Claude spark on it, hands taking turns on the keys
                    Loader {
                        active: root.has("laptop")
                        sourceComponent: Component {
                            Item {
                                Px { x: 5; y: 4; width: 10; height: 4; color: "#aeb4c3" }
                                Px { x: 5; y: 4; width: 10; color: "#dfe3ec" }
                                Px { x: 5; y: 7; width: 10; color: "#959bab" }
                                Pic { x: 8; y: 4; rows: ["..x.", "xxxx", ".x.."]; inks: ({ x: root.col("claude", "#d97757") }) }
                                Px { x: 3; y: 8; width: 14; color: "#6f7586" }
                                Px { x: 3; y: 7 + (root.fx.hl ?? 0); width: 2; color: root.body }
                                Px { x: 15; y: 7 + (root.fx.hr ?? 0); width: 2; color: root.body }
                            }
                        }
                    }
                    // coffee (morning, or keeping a tired Clawd going); lifted to sip
                    Loader {
                        active: root.has("mug") || root.has("cup")
                        sourceComponent: Component {
                            Item {
                                readonly property bool up: root.fx.prop === "cup" && root.f === 1
                                x: up ? -4 : root.fx.prop === "cup" ? -1 : 0
                                y: up ? -1 : root.fx.prop === "cup" ? -1 : 0
                                Px { x: 18; y: 3; width: 2; height: 3; color: root.cream }
                                Px { x: 18; y: 3; width: 2; color: "#6f4330" }
                                Px { x: 18; y: 5; width: 2; color: root.col("primary", "#e9a863") }
                                Px { x: 20; y: 4; color: root.cream }
                                Px { visible: !parent.up; x: 18 + root.twinkle % 2; y: 1; color: root.cream; opacity: 0.4 }
                                Px { visible: !parent.up; x: 19 - root.twinkle % 2; y: 0; color: root.cream; opacity: 0.22 }
                            }
                        }
                    }
                    // hourglass while a window is out: the top drains as the reset gets closer
                    Loader {
                        active: root.has("hourglass")
                        sourceComponent: Component {
                            Item {
                                id: glass
                                readonly property color wood: root.col("secondary", "#deb58e")
                                readonly property color pane: Qt.alpha("#ffffff", 0.16)
                                readonly property color grain: root.col("yellow", "#e2ae69")
                                Px { x: 18; y: 1; width: 3; color: glass.wood }
                                Px { x: 18; y: 2; width: 3; color: glass.pane }
                                Px { x: 19; y: 3; color: glass.pane }
                                Px { x: 18; y: 4; width: 3; color: glass.pane }
                                Px { x: 18; y: 5; width: 3; color: glass.wood }
                                Px { visible: root.sand > 0.05; x: root.sand > 0.6 ? 18 : 19; y: 2; width: root.sand > 0.6 ? 3 : 1; color: glass.grain }
                                Px { visible: root.sand > 0.02; x: 19; y: 3; color: glass.grain }
                                Px { x: root.sand > 0.4 ? 19 : 18; y: 4; width: root.sand > 0.4 ? 1 : 3; color: glass.grain }
                            }
                        }
                    }
                    // a shell command: hammering at a block, sparks on each hit
                    Loader {
                        active: root.has("hammer")
                        sourceComponent: Component {
                            Item {
                                Px { x: 18; y: 5; width: 4; height: 3; color: "#8f735f" }
                                Px { x: 18; y: 5; width: 4; color: "#b39479" }
                                Px { x: 20; y: 6; color: "#6f5847" }
                                Item {
                                    visible: root.f === 0
                                    Px { x: 18; y: 1; height: 3; color: "#8a5a3c" }
                                    Px { x: 17; y: -1; width: 3; height: 2; color: "#a3abbd" }
                                }
                                Item {
                                    visible: root.f === 1
                                    Px { x: 17; y: 4; width: 2; color: "#8a5a3c" }
                                    Px { x: 19; y: 3; width: 2; height: 2; color: "#a3abbd" }
                                    Px { x: 18; y: 2; color: "#ffd166" }
                                    Px { x: 21; y: 2; color: "#ffd166" }
                                    Px { x: 22; y: 4; color: "#ffd166"; opacity: 0.6 }
                                }
                            }
                        }
                    }
                    // reading code: a magnifier sweeps over a page
                    Loader {
                        active: root.has("magnifier")
                        sourceComponent: Component {
                            Item {
                                Px { x: 18; y: 2; width: 4; height: 6; color: "#ece6dc" }
                                Px { x: 19; y: 3; width: 2; color: "#a9a49c" }
                                Px { x: 19; y: 5; width: 2; color: "#a9a49c" }
                                Px { x: 19; y: 6; color: "#a9a49c" }
                                Item {
                                    x: [0, 1, 2, 1][root.f % 4]
                                    y: [0, 1, 0, 2][root.f % 4]
                                    Pic {
                                        x: 17; y: 1
                                        rows: [".rr.", "rgsr", "rssr", ".rr.", "h..."]
                                        inks: ({ r: "#cfd5e3", g: "#ffffff", s: Qt.alpha("#9ccfff", 0.55), h: "#8a5a3c" })
                                    }
                                }
                            }
                        }
                    }
                    // the web: a little globe spinning on its hand
                    Loader {
                        active: root.has("globe")
                        sourceComponent: Component {
                            Item {
                                id: globe
                                // land drifts across as it turns
                                function land(x, y) { const u = (x + root.f) % 4; return (u === 0 && y > 0) || (u === 1 && y === 1) || (u === 3 && y === 2) }
                                Repeater {
                                    model: [[1, 0], [2, 0], [0, 1], [1, 1], [2, 1], [3, 1], [0, 2], [1, 2], [2, 2], [3, 2], [1, 3], [2, 3]]
                                    Px {
                                        required property var modelData
                                        x: 17 + modelData[0]; y: -1 + modelData[1]
                                        color: globe.land(modelData[0], modelData[1]) ? "#6cc28a" : "#5b8ee6"
                                    }
                                }
                                Px { x: 18; y: -1; color: "#ffffff"; opacity: 0.55 }
                            }
                        }
                    }
                    // juggling (subagents, or just showing off)
                    Loader {
                        active: root.has("balls")
                        sourceComponent: Component {
                            Item {
                                id: balls
                                readonly property var arc: [[2, 1], [3, -2], [6, -4], [9, -5], [12, -4], [15, -2], [16, 1]]
                                Repeater {
                                    model: 3
                                    Px {
                                        required property int index
                                        readonly property var at: balls.arc[(root.f + index * 2) % 7]
                                        x: at[0]; y: at[1]; width: 2; height: 2
                                        color: [root.col("red", "#f7768e"), root.col("yellow", "#e0af68"), root.col("cyan", "#7dcfff")][index]
                                    }
                                }
                            }
                        }
                    }
                    // compacting: sweeping up, with a little dust
                    Loader {
                        active: root.has("broom")
                        sourceComponent: Component {
                            Item {
                                x: [0, 1, 2, 1][root.f % 4]
                                Pic {
                                    x: 16; y: 0
                                    rows: ["h....",
                                           ".h...",
                                           ".h...",
                                           "..h..",
                                           "..h..",
                                           ".bbbb",
                                           "bbbbb"]
                                    inks: ({ h: "#8a5a3c", b: "#d9b35b" })
                                }
                                Px { visible: root.f % 2 === 1; x: 21 + root.f % 3; y: 6; color: "#c9ccd6"; opacity: 0.5 }
                                Px { visible: root.f % 4 === 3; x: 22; y: 5; color: "#c9ccd6"; opacity: 0.35 }
                            }
                        }
                    }
                    // rain: an umbrella in this screen's colours
                    Loader {
                        active: root.has("umbrella")
                        sourceComponent: Component {
                            Item {
                                Repeater {
                                    model: 14
                                    Px {
                                        required property int index
                                        x: 3 + index; y: -2
                                        color: index % 4 < 2 ? root.col("primary", "#7aa2f7") : root.col("tertiary", "#bb9af7")
                                    }
                                }
                                Px { x: 5; y: -3; width: 10; color: root.col("primary", "#7aa2f7") }
                                Px { x: 8; y: -4; width: 4; color: root.col("tertiary", "#bb9af7") }
                                Px { x: 9; y: -5; color: root.cream }
                                Px { x: 16; y: -1; height: 4; color: "#3b3a44" }
                            }
                        }
                    }

                    // ---- for a moment (acts) ----
                    // the Claude spark, the way Claude Code's spinner turns: · ✢ ✳ ✶ ✻ ✽
                    Loader {
                        active: root.has("spark")
                        sourceComponent: Component {
                            Item {
                                id: spark
                                x: root.playing === "magic" ? 8 : 16
                                y: root.playing === "magic" ? -7 : -6
                                readonly property var show: [[1, 0, 0, 0, 0], [1, 1, 0, 0, 0], [1, 0, 1, 0, 0],
                                                             [1, 1, 0, 1, 0], [1, 1, 1, 1, 0], [1, 1, 1, 0, 1]]
                                Repeater {
                                    model: [[2, 2, 0], [2, 1, 1], [1, 2, 1], [3, 2, 1], [2, 3, 1],
                                            [1, 1, 2], [3, 1, 2], [1, 3, 2], [3, 3, 2],
                                            [2, 0, 3], [0, 2, 3], [4, 2, 3], [2, 4, 3],
                                            [0, 0, 4], [4, 0, 4], [0, 4, 4], [4, 4, 4]]
                                    Px {
                                        required property var modelData
                                        x: modelData[0]; y: modelData[1]
                                        visible: spark.show[root.f % 6][modelData[2]] === 1
                                        color: root.col("claude", "#d97757")
                                        opacity: modelData[2] >= 3 ? 0.75 : 1
                                    }
                                }
                            }
                        }
                    }
                    Loader {
                        active: root.has("heart")
                        sourceComponent: Component {
                            Pic {
                                x: 13; y: -3 - Math.min(root.f, 3)
                                opacity: root.f >= 5 ? 0.45 : 1
                                rows: ["xx.xx", "xxxxx", ".xxx.", "..x.."]
                                inks: ({ x: root.pink })
                            }
                        }
                    }
                    Loader {
                        active: root.has("note")
                        sourceComponent: Component {
                            Pic {
                                x: 16 + root.f % 2; y: -5 - (root.f % 3 === 1 ? 1 : 0)
                                rows: ["..xx", "..x.", "xxx.", "xx.."]
                                inks: ({ x: root.col("cyan", "#7dcfff") })
                            }
                        }
                    }
                    Loader {
                        active: root.has("bang")
                        sourceComponent: Component {
                            Pic { x: 9; y: -6; rows: ["xx", "xx", "xx", "..", "xx"]; inks: ({ x: "#ffd166" }) }
                        }
                    }
                    Loader {
                        active: root.has("ask")
                        sourceComponent: Component {
                            Pic {
                                x: 16; y: -6 - root.f
                                rows: ["xxx", "..x", ".xx", "...", ".x."]
                                inks: ({ x: root.col("yellow", "#e0af68") })
                            }
                        }
                    }
                    Loader {
                        active: root.has("check")
                        sourceComponent: Component {
                            Pic {
                                x: 13; y: -5
                                rows: root.f === 0 ? ["....", "....", "x...", ".x.."]
                                    : root.f === 1 ? ["....", "...x", "x.x.", ".x.."]
                                    : ["....x", "...x.", "x.x..", ".x..."]
                                inks: ({ x: root.col("green", "#9ece6a") })
                            }
                        }
                    }
                    Loader {
                        active: root.has("puff")
                        sourceComponent: Component {
                            Pic {
                                x: -1 - root.f; y: 3 - (root.f > 0 ? 1 : 0)
                                opacity: [0.9, 0.7, 0.35][root.f] ?? 0
                                rows: root.f === 0 ? ["..", "xx"] : [".x.", "xxx", ".x."]
                                inks: ({ x: "#dfe3ec" })
                            }
                        }
                    }
                    Loader {
                        active: root.has("stars")
                        sourceComponent: Component {
                            Item {
                                id: stars
                                readonly property var ring: [[3, -1], [6, -3], [10, -4], [14, -3], [17, -1], [10, -1]]
                                Repeater {
                                    model: 3
                                    Px {
                                        required property int index
                                        readonly property var at: stars.ring[(root.f + index * 2) % 6]
                                        x: at[0]; y: at[1]
                                        color: "#ffd166"
                                    }
                                }
                            }
                        }
                    }
                    Loader {
                        active: root.has("sparkle")
                        sourceComponent: Component {
                            Item {
                                Pic { visible: root.f !== 1; x: -1; y: -2; rows: [".x.", "xxx", ".x."]; inks: ({ x: "#fff4cf" }) }
                                Pic { visible: root.f !== 0; x: 18; y: -2; rows: [".x.", "xxx", ".x."]; inks: ({ x: "#fff4cf" }) }
                                Px { visible: root.f === 1; x: 1; y: -4; color: "#fff4cf"; opacity: 0.6 }
                            }
                        }
                    }
                    // a butterfly (or, Halloween week, a bat) drops by and perches on its head
                    Loader {
                        active: root.has("fly") || root.has("bat")
                        sourceComponent: Component {
                            Item {
                                readonly property bool bat: root.has("bat")
                                // the bat flits above the witch's hat instead of perching
                                readonly property var path: bat ? [[-3, -6], [0, -8], [3, -7], [6, -9], [9, -8], [12, -9], [15, -7],
                                                                   [18, -8], [21, -6], [24, -7]]
                                                                : [[-3, -2], [0, -4], [3, -5], [6, -4], [8, -2], [8, -2], [8, -2],
                                                                   [11, -4], [14, -6], [17, -7], [20, -8], [23, -9]]
                                readonly property var at: path[Math.min(root.f, path.length - 1)]
                                readonly property bool open: root.f % 2 === 0 || (root.f >= 4 && root.f <= 6 && !bat)
                                x: at[0]; y: at[1]
                                Pic {
                                    rows: parent.bat ? (parent.open ? ["x...x", "xxxxx", ".x.x."] : ["..x..", ".xxx.", ".x.x."])
                                                     : (parent.open ? ["x.x", "xxx", "x.x"] : [".x.", ".x.", ".x."])
                                    inks: ({ x: parent.bat ? "#7a6a99" : root.col("magenta", "#bb9af7") })
                                }
                            }
                        }
                    }
                    // nodding off: a little z
                    Loader {
                        active: root.has("z")
                        sourceComponent: Component {
                            Pic {
                                x: 15; y: -3 - root.f
                                opacity: 0.85
                                rows: ["xxx", ".x.", "xxx"]
                                inks: ({ x: root.cream })
                            }
                        }
                    }

                    // ---- around it ----
                    // tired: a battery running down (blinks when it's nearly out)
                    Pic {
                        visible: root.tired >= 2 && !root.asleep
                        x: 0; y: -2
                        opacity: root.tired >= 3 && !root.lowOn ? 0.25 : 0.9
                        rows: [".n.", "fff", "f.f", root.tired >= 4 ? "f.f" : "fcf", "fff"]
                        inks: ({ n: "#c9cdd8", f: root.tired >= 3 ? "#ff6b6b" : "#c9cdd8",
                                 c: root.tired >= 3 ? "#ff6b6b" : "#ffd166" })
                    }
                    Repeater {   // confetti
                        model: [{ x: 1, y: -3, c: "magenta" }, { x: 3, y: -1, c: "yellow" }, { x: 0, y: 0, c: "cyan" },
                                { x: 14, y: -4, c: "green" }, { x: 16, y: -2, c: "red" }]
                        Px {
                            required property var modelData
                            required property int index
                            visible: root.celebrate && (index + root.twinkle) % 4 !== 0
                            x: modelData.x; y: modelData.y
                            color: root.col(modelData.c, "#ffffff")
                        }
                    }
                    // Zzz (asleep, or slumped by the hourglass)
                    Repeater {
                        model: root.sitting ? [{ x: 12, y: -3 }, { x: 15, y: -7 }] : [{ x: 16, y: 0 }, { x: 18, y: -4 }]
                        Item {
                            id: zed
                            required property var modelData
                            required property int index
                            readonly property color c: Qt.alpha(root.cream, 0.85)
                            x: modelData.x; y: modelData.y
                            visible: (root.asleep || root.sitting) && root.eyeR === "sleep" && !root.fx.prop
                                     && (index === 0 ? root.zz % 3 !== 2 : root.zz % 3 !== 0)
                            Px { width: 4; color: zed.c }
                            Px { x: 2; y: 1; color: zed.c }
                            Px { x: 1; y: 2; color: zed.c }
                            Px { y: 3; width: 4; color: zed.c }
                        }
                    }
                    // a star out at night
                    Item {
                        id: twinkler
                        visible: root.star
                        readonly property color c: root.col("yellow_bright", "#f2c285")
                        x: 19; y: -3
                        Px { x: 1; y: 1; color: twinkler.c }
                        Px { visible: root.twinkle % 3 !== 2; x: 1; color: twinkler.c; opacity: 0.6 }
                        Px { visible: root.twinkle % 3 !== 2; y: 1; color: twinkler.c; opacity: 0.6 }
                        Px { visible: root.twinkle % 3 !== 2; x: 2; y: 1; color: twinkler.c; opacity: 0.6 }
                        Px { visible: root.twinkle % 3 !== 2; x: 1; y: 2; color: twinkler.c; opacity: 0.6 }
                    }
                    // rain and snow falling around it
                    Repeater {
                        model: root.weather === "rain" || root.weather === "snow" ? [[0, 0], [1, 5], [19, 2], [21, 7], [-1, 9]] : []
                        Px {
                            required property var modelData
                            readonly property bool snow: root.weather === "snow"
                            x: modelData[0] + (snow ? (root.f + modelData[1]) % 2 : 0)
                            y: -5 + (modelData[1] + root.f * (snow ? 1 : 2)) % 13
                            height: snow ? 1 : 2
                            color: snow ? "#ffffff" : "#8ec5ff"
                            opacity: 0.7
                        }
                    }
                    // check-in from Claude: a big "!" badge on top of everything, bouncing in steps
                    Item {
                        id: badge
                        visible: root.alert
                        y: -root.bounce
                        readonly property color c: root.col("red", "#f7768e")
                        Rectangle { x: 14.5; y: -4.4; width: 8; height: 8; radius: 1.6; color: "black"; opacity: 0.35 }
                        Rectangle { x: 14; y: -5; width: 8; height: 8; radius: 1.6; color: badge.c }
                        Px { x: 15; y: -5; width: 6; color: Qt.lighter(badge.c, 1.18) }
                        Px { x: 17; y: -4; width: 2; height: 4; color: root.cream }
                        Px { x: 17; y: 1; width: 2; color: root.cream }
                    }
                }
            }
        }
    }

    // ---------- timing ----------
    Timer {   // blink every few seconds; slower and longer when tired
        interval: 3200 + Math.random() * 2500
        running: root.live && ["open", "wide", "half", "heavy", "up"].indexOf(root.restEyes) >= 0 && !root.shades
        repeat: true
        onTriggered: {
            root.blinking = true
            unblink.interval = root.tired >= 2 ? 340 : 140
            unblink.restart()
            interval = (root.tired >= 1 ? 2400 : 3200) + Math.random() * 2500
        }
    }
    Timer { id: unblink; interval: 140; onTriggered: root.blinking = false }

    // each state's own loop: a short burst every few seconds
    readonly property string loopAct: asleep || sitting ? "snore" : alert ? "" : celebrate ? "cheer"
        : ({ typing: "type", thinking: "think", building: "hammer", reading: "scan", web: "surf",
             juggling: "juggle", sweeping: "sweep", waiting: "ask" })[doing]
          ?? (tired >= 3 ? "nod" : tired >= 2 ? "yawn" : weather === "rain" ? "rain" : weather === "snow" ? "flakes" : "")
    readonly property var every: ({ snore: 2400, cheer: 6000, type: 3600, think: 2600, hammer: 3200, scan: 3800,
                                    surf: 3400, juggle: 3600, sweep: 3200, ask: 2400, nod: 7000, yawn: 11000,
                                    rain: 2600, flakes: 3200 })
    Timer {
        interval: (root.every[root.loopAct] ?? 4000) * (root.continuous ? 0.6 : 1)
        running: root.live && root.loopAct !== ""
        repeat: true
        onTriggered: {
            // a tired Clawd yawns or nods off over its work now and then
            if (root.doing && root.tired >= 2 && Math.random() < 0.18) root.play(root.tired >= 3 ? "nod" : "yawn")
            else root.play(root.loopAct)
        }
    }

    // now and then, when there's nothing else going on
    Timer {
        interval: 20000
        running: root.live && root.idle
        repeat: true
        onTriggered: {
            interval = root.continuous ? 5000 + Math.random() * 6000 : 15000 + Math.random() * 17000
            const o = ["look", "look", "wave", "hop", "stretch", "whistle"]
            if (root.tired >= 1) o.push("yawn", "yawn")
            if (root.daypart === "night") o.push("stargaze")
            if (root.held === "mug") o.push("sip", "sip")
            if ((root.daypart === "morning" || root.daypart === "day") && !root.weather && root.season !== "xmas") o.push("butterfly")
            if (root.season === "halloween") o.push("bat", "bat")
            root.play(root.pick(o))
        }
    }

    // the low battery blinks (one redraw a second, only when nearly out)
    Timer {
        interval: root.lowOn ? 1400 : 500
        running: root.live && root.tired === 3
        repeat: true
        onTriggered: root.lowOn = !root.lowOn
    }

    // the "!" badge hops: up briefly, down longer (stepped, so it's cheap in the panel)
    Timer {
        interval: root.bounce ? 260 : 740
        running: root.live && root.alert
        repeat: true
        onTriggered: root.bounce = root.bounce ? 0 : 1
    }
    onAlertChanged: if (!alert) bounce = 0

    // popup only: stars and steam twinkle, a soft idle bob
    Timer { interval: 650; running: root.looping; repeat: true; onTriggered: root.twinkle++ }
    SequentialAnimation {
        running: root.looping && !root.playing
        loops: Animation.Infinite
        onRunningChanged: if (!running) bob.y = 0
        NumberAnimation {
            target: bob; property: "y"
            to: root.asleep || root.sitting ? -0.25 : -0.45
            duration: root.asleep || root.sitting ? 1800 : root.tired >= 2 ? 1100 : 700
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: bob; property: "y"; to: 0
            duration: root.asleep || root.sitting ? 1800 : root.tired >= 2 ? 1100 : 700
            easing.type: Easing.InOutSine
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
    }
}
