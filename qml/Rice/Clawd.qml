import QtQuick
import QtQuick.Window
import QtCore

// Clawd, the Claude Code creature and Atom Plasma's mascot, as pixel art that lives along with you.
// It follows your usage (sleepy, tired, then exhausted as a window fills up; it slumps by the
// hourglass and dozes when one runs out), what Claude Code is doing (types at a laptop, thinks with
// the Claude spark, hammers at shell commands, reads with a magnifier, spins a globe for the web,
// juggles subagents, sweeps up a compaction), what its last answer was about (a tick when it's done, a
// wrench and a tick for a fix, a lightbulb for research, a thought bubble while background work runs,
// a sweat drop when it got stuck, a "?" when it asked you something, waving at you with the "?" when
// Claude Code waits on a permission), the time of day, the season and (on the desktop) the weather.
// Off duty it never sleeps: it gets on with a hobby (`hobby`: a book, a handheld game, music on
// headphones, painting, bubbles, a yo-yo, a plant, a block tower, a telescope at night, coffee in the
// morning), a new one every few minutes. Hover it and it greets you and follows the pointer with its
// eyes; click it for one of a dozen little acts, never the same one twice in a row (four quick clicks
// make it dizzy). A double click calls `summoned` (the widgets open Claude Code in a terminal).
//
// The art is drawn in grid cells (22 x 10; hats, bubbles and props poke out around it) and scaled by
// `px`, snapped to whole device pixels (`unit`) so every cell is the same size on fractional scales.
// Every motion is an "act": a short list of stepped poses (`acts`), played as a burst, so the panel
// only redraws for a moment every few seconds. A smooth looping animation in a panel widget keeps
// plasmashell + KWin redrawing at full refresh (~27 W on the NVIDIA), so `continuous` (the popup
// only) adds the soft idle bob.
//
// One Clawd, many views: the bars, the desktop and the popup all show the same creature, so whatever it
// does on its own comes from the wall clock and the shared inputs, never from per-view chance or timers
// started at different moments. Its acts fire on the clock's beats (`Beat`), every bit of chance is a
// hash of the beat (`chance`), and its hobby and the hobby's progress are read off the clock, so every
// view does the same thing at the same moment without talking to the others. Only a click is passed on:
// the clicked Clawd writes the act to ~/.cache/clawd/poke.json and the others play it too. A hover
// stays with the Clawd under the pointer (it's the one looking at you).
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
    property bool music: false      // something is playing: off duty, it puts its headphones on
    property bool notice: false     // an important update waits (update-check.py): a small badge
    property bool celebrate: false  // a usage window just reset
    property bool warm: false       // using the session faster than its even pace (a blush)
    property string daypart: "day"  // morning | day | evening | night
    property bool weekend: false
    property string season: ""      // "" | halloween | xmas | newyear
    property string weather: ""     // "" | rain | snow (the desk passes it)
    property real sand: 1           // limited: share of the wait still to go (hourglass)
    property bool alert: false      // Claude asked for a check-in (ask.sh): big "!" badge
    signal alertClicked()           // clicked while the "!" is up (no act: the widget shows or settles it)
    signal summoned()               // double-clicked (not part of a faster spree): open Claude Code
    property var pal: ({})
    property real px: 8
    property bool interactive: true // hover greets, a click plays an act
    property bool animate: true     // pause everything when hidden
    property bool continuous: true  // the smooth idle bob and twinkles (popup only)
    property bool hovered: false    // the pointer is over the widget around it (the eyes follow `look`)

    readonly property bool live: visible && animate
    readonly property bool looping: live && continuous

    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
    readonly property real unit: Math.max(1, Math.round(px * dpr)) / dpr
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
          ?? (weather === "rain" ? "umbrella" : idle ? (hobby === "coffee" ? "mug" : hobby) : tired >= 2 ? "mug" : "")
    // shown between bursts: the Claude spark while thinking, a "?" when it needs you, what the last
    // answer was about after it
    readonly property string restProp: ({ thinking: "spark", waiting: "ask", attention: "ask", running: "dots",
                                          done: "check", fixed: "check", found: "bulb", stuck: "sweat" })[doing] ?? ""
    readonly property string hat: held === "umbrella" ? "" : celebrate ? "party" : season === "xmas" ? "santa"
        : season === "newyear" ? "party" : season === "halloween" ? "witch" : daypart === "night" ? "nightcap" : ""
    readonly property bool shades: weekend && daypart === "day" && tired === 0 && idle
    // the night star sits where the right-hand props go
    readonly property bool star: daypart === "night" && idle && ["", "book", "game", "music", "mug"].indexOf(held) >= 0

    // ---------- the clock every view shares ----------
    // a number in [0, 1) that depends only on its (integer) arguments: the same in every view
    function chance(a, b, c) {
        let h = Math.imul((a | 0) ^ 0x9e3779b9, 0x85ebca6b) ^ Math.imul(((b | 0) + 0x632be5ab) | 0, 0xc2b2ae35)
              ^ Math.imul(((c | 0) + 0x27d4eb2f) | 0, 0x165667b1)
        h ^= h >>> 16; h = Math.imul(h, 0x7feb352d); h ^= h >>> 15; h = Math.imul(h, 0x846ca68b); h ^= h >>> 16
        return (h >>> 0) / 4294967296
    }
    function pickAt(list, a, b) { return list[Math.floor(chance(a, b, 7) * list.length)] }
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
    property int canvas: 0              // painting: dabs on the canvas (7 fill it)
    property int growth: 0              // the plant: 0 a sprout ... 3 in bloom
    property int tower: 0               // blocks: how many are stacked (4 is as high as it goes)
    property bool growNow: false        // the plant grows at this watering
    function hobbyFor(slot) {
        if (music) return "music"
        const o = tired >= 2 ? ["coffee", "coffee", "book", "music"]
                : daypart === "morning" ? ["coffee", "coffee", "plant", "plant", "book", "music", "game"]
                : daypart === "night" ? ["telescope", "telescope", "book", "book", "music", "game"]
                : ["book", "game", "music", "paint", "paint", "bubbles", "yoyo", "blocks", "blocks", "plant"]
        const h = pickAt(o, slot, 21)
        if (h !== pickAt(o, slot - 1, 21)) return h
        const others = o.filter((x, i) => x !== h && o.indexOf(x) === i)      // never the same one twice running
        return pickAt(others, slot, 22)
    }
    // the hobby at `at` (ms), and how far along it is: the beats since its slot began
    function syncHobby(at) {
        const slot = Math.floor(at / hobbySlot)
        hobby = hobbyFor(slot)
        const period = every[hobbyAct[hobby]] ?? 4000
        const k = Math.max(0, Math.floor((at - slot * hobbySlot) / period))
        canvas = k % 8                  // 7 dabs, then admired and cleared
        tower = k % 5                   // 4 blocks, then it topples
        let g = 0
        for (let j = 0; j < k && g < 3; j++) if (chance(slot, j, 13) < 0.5) g++
        growth = g
        growNow = chance(slot, k, 13) < 0.5
    }
    onIdleChanged: if (idle) syncHobby(Date.now())
    onDaypartChanged: syncHobby(Date.now())
    onMusicChanged: syncHobby(Date.now())
    onTiredChanged: syncHobby(Date.now())
    onLiveChanged: if (live) syncHobby(Date.now())
    Component.onCompleted: syncHobby(Date.now())

    readonly property color base: col("claude", "#d97757")
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
    readonly property string restEyes: alert || doing === "attention" || doing === "waiting" ? "wide" : sitting ? "sleep"
        : celebrate ? "joy" : doing === "thinking" ? "up" : doing === "stuck" ? "flat"
        : tired >= 3 ? "heavy" : tired >= 2 ? "half" : "open"
    function blinked(s) { return blinking && ["open", "wide", "half", "heavy", "up"].indexOf(s) >= 0 ? "blink" : s }
    readonly property string eyeL: fx.eyeL ?? fx.eyes ?? blinked(restEyes)
    readonly property string eyeR: fx.eyeR ?? fx.eyes ?? blinked(restEyes)
    // arms: -1 drooping, 0 resting, 1 raised, 2 up high, 3 over the eyes, 4 at the keyboard (or holding
    // something in front with both hands: the prop draws the hands)
    readonly property bool twoHands: ["laptop", "book", "game"].indexOf(held) >= 0
    readonly property int restArmL: twoHands ? 4 : tired >= 3 ? -1 : 0
    readonly property int restArmR: twoHands ? 4 : ["umbrella", "globe", "wrench", "bubbles", "yoyo", "paint"].indexOf(held) >= 0 ? 1
                                  : tired >= 3 ? -1 : 0
    readonly property int armL: fx.armL ?? restArmL
    readonly property int armR: fx.armR ?? restArmR
    readonly property string mouth: fx.mouth ?? ""
    readonly property bool blush: fx.blush ?? (warm || celebrate)
    // the prop's frame (at rest: the spark turned, the tick drawn, the bulb lit, the bubble's dots all up)
    readonly property int f: fx.f ?? ({ spark: 4, check: 2, bulb: 1, dots: 3 })[restProp] ?? 0
    readonly property int gaze: fx.glance ?? (pointed ? look : glance !== 0 ? glance
        : ["hourglass", "magnifier", "globe", "hammer", "paint", "plant", "blocks", "telescope"].indexOf(held) >= 0
          || restProp === "dots" || restProp === "bulb" ? 1 : 0)
    function has(name) { return held === name || (restProp === name && !fx.norest) || fx.prop === name || fx.prop2 === name }

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
        // slumped by the hourglass: opens one eye at you
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

        // what the last answer was about: how it comes on, then its little loop
        hail:     seq(6, 150, i => ({ armR: i % 2 ? 1 : 2, eyes: "wide", f: i % 2, dy: i % 2 ? 0 : -1 })),   // over here!
        wait:     seq(8, 260, i => ({ f: i % 4 })),                                                         // the dots come up
        proud:    [{ d: 520, eyes: "joy" }, { d: 120 }],
        fixed:    [{ d: 120, armR: 2, w: 1, norest: true }, { d: 120, armR: 1, norest: true }, { d: 120, armR: 2, w: 1, norest: true },
                   { d: 120, armR: 1, norest: true },
                   { d: 90, dy: -1, eyes: "joy", f: 0 }, { d: 90, dy: -2, eyes: "joy", f: 1 },
                   { d: 900, eyes: "joy", f: 2, blush: true }, { d: 200 }],
        tighten:  [{ d: 140, armR: 2, w: 1 }, { d: 140, armR: 1 }, { d: 140, armR: 2, w: 1 }, { d: 200, armR: 1, eyes: "joy" }],
        eureka:   [{ d: 180, eyes: "up", f: 0 }, { d: 120, eyes: "wide", f: 1, dy: -1 },
                   { d: 120, eyes: "star", f: 2, armR: 2 }, { d: 760, eyes: "star", f: 2, armR: 2 }, { d: 220, eyes: "joy" }],
        glow:     [{ d: 260, f: 2 }, { d: 220 }, { d: 260, f: 2 }, { d: 160 }],
        oops:     [{ d: 140, eyes: "wide", mouth: "o", f: 0 }, { d: 460, eyes: "wide", f: 0, armL: 1, armR: 1 },
                   { d: 560, eyes: "flat", f: 1, armL: 1, armR: 1 }, { d: 200 }],
        shrug:    [{ d: 300, armL: 1, armR: 1 }, { d: 420, armR: 2, glance: -1, f: 1 }, { d: 200 }],

        // off duty: each hobby's burst
        read:     t => chance(t, 11) < 0.35
                      ? [{ d: 160, f: 1 }, { d: 120, f: 2 }, { d: 160, f: 3 }, { d: 260, eyes: "joy" }]    // a page turns
                      : seq(4, 420, i => ({ glance: i % 2 ? 1 : -1 })),                                       // along the lines
        play:     t => seq(10, 110, i => ({ hl: i % 2, hr: 1 - i % 2, f: i }))
                        .concat(chance(t, 12) < 0.3 ? [{ d: 560, eyes: "joy", prop2: "sparkle", f: 0 }, { d: 160 }] : []),
        groove:   seq(8, 170, i => ({ dy: i % 2 ? 0 : -1, eyes: i % 4 === 2 ? "joy" : undefined, prop: "note", f: i })),
        paint:    () => root.canvas >= 7
                      ? [{ d: 320, glance: 1 }, { d: 760, eyes: "joy", glance: 1, prop2: "sparkle", f: 1 }, { d: 160, clear: true }]
                      : [{ d: 160, armR: 2 }, { d: 120, armR: 1 }, { d: 160, armR: 2 }, { d: 160, armR: 1, paint: true }, { d: 200 }],
        blow:     seq(10, 150, i => ({ mouth: i < 2 ? "o" : undefined, prop: "bubble", f: i })),
        yoyo:     seq(10, 90, i => ({ f: [0, 1, 2, 3, 4, 4, 3, 2, 1, 0][i], armR: i === 0 || i === 9 ? 2 : 1 })),
        water:    () => [{ d: 220, armR: 1, prop: "can", f: 0 }]
                        .concat(seq(6, 160, i => ({ armR: 1, prop: "can", f: 1 + i % 3 })))
                        .concat([{ d: 200, grow: root.growNow }, { d: 320, eyes: "joy" }]),
        stack:    () => root.tower >= 4
                      ? [{ d: 160, eyes: "wide" }, { d: 130, f: 1 }, { d: 130, f: 2 }, { d: 180, f: 3, eyes: "wide", mouth: "o" },
                         { d: 560, f: 3, eyes: "joy" }, { d: 80, topple: true }]                              // it all comes down
                      : [{ d: 180, armR: 1 }, { d: 160, armR: 2 }, { d: 220, armR: 1, stack: true }, { d: 240, eyes: "joy" }],
        gaze:     t => chance(t, 14) < 0.4
                      ? seq(7, 120, i => ({ eyeL: "sleep", prop: "shoot", f: i })).concat([{ d: 520, eyes: "star" }])
                      : [{ d: 1000, eyeL: "sleep" }, { d: 200 }],

        // now and then
        look:     t => [{ d: 1500, glance: chance(t, 15) < 0.5 ? -1 : 1 }],
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
    // `seed`: the beat (or the click) it's played for, so an act with chance in it goes the same way in
    // every view
    function play(name, level, seed) {
        level = level || 0
        const a = acts[name]
        if (!a || (playing && level <= prio)) return false
        frames = typeof a === "function" ? a(seed ?? Math.floor(Date.now() / 1000)) : a
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
        if (fr.paint) canvas = Math.min(7, canvas + 1)
        if (fr.clear) canvas = 0
        if (fr.grow) growth = Math.min(3, growth + 1)
        if (fr.stack) tower = Math.min(4, tower + 1)
        if (fr.topple) tower = 0
        fx = fr
        player.interval = fr.d || 120
        player.restart()
    }
    Timer { id: player; onTriggered: root.advance() }

    // ---------- what the pointer does ----------
    function lookAt(t) { look = t < 0.36 ? -1 : t > 0.64 ? 1 : 0 }
    function greet() {
        if (!live || alert) return
        if (sitting) { play("peek", 1); return }
        // with its hands full it just smiles, winks or hops
        play(pick(twoHands ? ["wink", "smile", "blep", "hop"] : ["wave", "wave", "wink", "smile", "peekaboo", "bow", "blep", "hop"]), 1)
    }
    property var clicks: []
    function poke() {
        if (alert) { alertClicked(); return }
        const t = Date.now()
        clicks = clicks.filter(c => t - c < 1600).concat([t])
        let name
        if (clicks.length >= 4) { clicks = []; name = "dizzy" }
        else if (sitting) name = pick(["sigh", "peek"])
        else if (tired >= 2 && Math.random() < 0.55) name = pick(["yawn", "chug", "nod"])
        else name = pick(["dance", "flip", "heart", "juggle", "magic", "melt", "shades", "sneeze", "flex", "surprise",
                          "giggle", "spin", "wink"])
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
        sh.exec("clawd-poke", ["sh", "-c", 'mkdir -p "${2%/*}" && printf "%s\\n" "$1" > "$2.t" && mv -f "$2.t" "$2"', "sh", event, pokeFile])
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
    // how each after-answer state comes on
    onDoingChanged: {
        if (!live) return
        const enter = ({ done: "done", fixed: "fixed", found: "eureka", stuck: "oops", attention: "hail" })[doing]
        if (enter) play(enter, 2)
        else if (doing === "chat") play("wave", 2)
    }

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
                        visible: root.weather === "snow"
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

                    // ---- off duty: its hobby ----
                    // a book held open, a page turning now and then (f 1-3)
                    Loader {
                        active: root.has("book")
                        sourceComponent: Component {
                            Item {
                                Pic {
                                    x: 4; y: 4
                                    rows: [".pppp..pppp.", "cllllssllllc", "cppppssppppc", "cccccccccccc"]
                                    inks: ({ p: root.cream, s: "#cfc6b8", l: "#a9a49c", c: root.col("primary", "#7aa2f7") })
                                }
                                Px { visible: root.f === 1; x: 11; y: 3; width: 3; color: "#ffffff" }
                                Px { visible: root.f === 2; x: 9; y: 2; height: 2; color: "#ffffff" }
                                Px { visible: root.f === 3; x: 6; y: 3; width: 3; color: "#ffffff" }
                                Px { x: 2; y: 5; width: 2; height: 2; color: root.body }
                                Px { x: 16; y: 5; width: 2; height: 2; color: root.body }
                            }
                        }
                    }
                    // a handheld game: thumbs on the buttons, a blip running round the screen
                    Loader {
                        active: root.has("game")
                        sourceComponent: Component {
                            Item {
                                Pic {
                                    x: 6; y: 4
                                    rows: [".gggggg.", "dgssssgb", "dgssssgb", ".gggggg."]
                                    inks: ({ g: "#5d6275", s: "#2f5d50", d: "#3b3f4c", b: root.col("red", "#f7768e") })
                                }
                                Px { x: 8 + root.f % 4; y: 5 + (root.f % 3 === 0 ? 1 : 0); color: "#9be7a8" }
                                Px { x: 6; y: 5 + (root.fx.hl ?? 0); color: root.hi }
                                Px { x: 13; y: 5 + (root.fx.hr ?? 0); color: root.hi }
                                Px { x: 4; y: 5; width: 2; height: 2; color: root.body }
                                Px { x: 14; y: 5; width: 2; height: 2; color: root.body }
                            }
                        }
                    }
                    // music: headphones (under a hat only the cups show)
                    Loader {
                        active: root.has("music")
                        sourceComponent: Component {
                            Item {
                                id: cans
                                readonly property color band: root.col("tertiary", "#bb9af7")
                                readonly property color cup: Qt.darker(band, 1.6)
                                Px { visible: root.hat === ""; x: 4; y: -1; width: 12; color: cans.band }
                                Px { visible: root.hat === ""; x: 3; y: 0; color: cans.band }
                                Px { visible: root.hat === ""; x: 16; y: 0; color: cans.band }
                                Px { x: 2; y: 1; width: 2; height: 3; color: cans.cup }
                                Px { x: 16; y: 1; width: 2; height: 3; color: cans.cup }
                                Px { x: 2; y: 1; width: 2; color: cans.band }
                                Px { x: 16; y: 1; width: 2; color: cans.band }
                            }
                        }
                    }
                    // painting at an easel: each dab adds a colour, a full canvas gets admired, then a fresh one
                    Loader {
                        active: root.has("paint")
                        sourceComponent: Component {
                            Item {
                                id: easel
                                readonly property var dots: [[19, 0, "primary"], [21, -1, "tertiary"], [20, 1, "red"], [19, -1, "yellow"],
                                                             [21, 1, "cyan"], [20, -1, "green"], [21, 0, "magenta"]]
                                Pic {
                                    x: 18; y: -2
                                    rows: ["wwwww", "wcccw", "wcccw", "wcccw", "wwwww", ".w.w.", ".w.w.", ".w.w.", "w...w", "w...w", "w...w", "w...w"]
                                    inks: ({ w: "#9a6b4b", c: root.cream })
                                }
                                Repeater {
                                    model: 7
                                    Px {
                                        required property int index
                                        visible: index < root.canvas
                                        x: easel.dots[index][0]; y: easel.dots[index][1]
                                        color: root.col(easel.dots[index][2], "#e0af68")
                                    }
                                }
                                // the brush, in the raised hand
                                Px { x: 18; y: root.armR === 2 ? 1 : 3; color: "#c9a27a" }
                                Px { x: 19; y: root.armR === 2 ? 0 : 2; color: root.col(easel.dots[root.canvas % 7][2], "#e0af68") }
                            }
                        }
                    }
                    // bubbles: a wand in the raised hand; blown ones float up and pop
                    Loader {
                        active: root.has("bubbles")
                        sourceComponent: Component {
                            Item {
                                id: wand
                                readonly property var path: [[19, -3], [20, -4], [19, -5], [20, -6]]
                                Pic { x: 18; y: -1; rows: ["xxx", "x.x", "xxx", ".x."]; inks: ({ x: "#c9cdd8" }) }
                                Repeater {
                                    model: 3
                                    Item {
                                        id: bubble
                                        required property int index
                                        readonly property int step: root.f - index * 2
                                        visible: root.fx.prop === "bubble" && step >= 0 && step < 4
                                        x: wand.path[Math.max(0, Math.min(3, step))][0]
                                        y: wand.path[Math.max(0, Math.min(3, step))][1]
                                        Rectangle { width: 2; height: 2; radius: 1; color: Qt.alpha("#8fd0ff", 0.6); border.width: 0.3; border.color: "#d9f1ff" }
                                        Px { color: "#ffffff"; opacity: 0.9 }
                                    }
                                }
                            }
                        }
                    }
                    // a yo-yo on its string (f: how far down)
                    Loader {
                        active: root.has("yoyo")
                        sourceComponent: Component {
                            Item {
                                Px { visible: root.f > 0; x: 17; y: 5; height: root.f; color: "#d9dce4"; opacity: 0.8 }
                                Rectangle { x: 16.5; y: 5 + root.f; width: 2; height: 2; radius: 0.8; color: root.col("red", "#f7768e") }
                                Px { x: 17; y: 5 + root.f; color: "#ffffff"; opacity: 0.5 }
                            }
                        }
                    }
                    // a potted plant that grows as it's watered (growth 0-3: a sprout ... in bloom)
                    Loader {
                        active: root.has("plant")
                        sourceComponent: Component {
                            Item {
                                id: pot
                                readonly property color leaf: root.col("green", "#9ece6a")
                                readonly property int h: [1, 2, 3, 3][root.growth]
                                Pic { x: 18; y: 7; rows: ["rrrr", ".rr.", ".rr."]; inks: ({ r: "#c8734f" }) }
                                Px { x: 18; y: 7; width: 4; color: "#e08b62" }
                                Px { x: 19; y: 7 - pot.h; height: pot.h; color: Qt.darker(pot.leaf, 1.25) }
                                Px { visible: root.growth >= 1; x: 20; y: 6; color: pot.leaf }
                                Px { visible: root.growth >= 2; x: 18; y: 5; color: pot.leaf }
                                Pic { visible: root.growth >= 3; x: 18; y: 2; rows: [".p.", "pyp", ".p."]; inks: ({ p: root.pink, y: "#ffd166" }) }
                                // the watering can (an act), pouring from its spout
                                Item {
                                    visible: root.fx.prop === "can"
                                    Pic { x: 17; y: 1; rows: ["..b..", "bbbbs", "bbb.."]; inks: ({ b: "#7d8fb3", s: "#a9b8d6" }) }
                                    Px { visible: root.f >= 1; x: 21; y: 3 + (root.f - 1); color: "#8ec5ff" }
                                    Px { visible: root.f >= 2; x: 21; y: 5 + (root.f - 2); color: "#8ec5ff"; opacity: 0.7 }
                                }
                            }
                        }
                    }
                    // a block tower, one block at a time up to four; then it topples (f 1-3)
                    Loader {
                        active: root.has("blocks")
                        sourceComponent: Component {
                            Item {
                                id: blocks
                                readonly property var tint: [root.col("primary", "#7aa2f7"), root.col("tertiary", "#bb9af7"),
                                                             root.col("yellow", "#e0af68"), root.col("cyan", "#7dcfff")]
                                readonly property var fallen: [[16, 8], [18, 8], [20, 8], [21, 6]]
                                Repeater {
                                    model: 4
                                    Rectangle {
                                        required property int index
                                        readonly property int lean: root.f > 0 && root.f < 3 ? Math.max(0, index - (root.tower - 1) + root.f) : 0
                                        visible: index < root.tower
                                        x: root.f === 3 ? blocks.fallen[index][0] : 18 + lean
                                        y: root.f === 3 ? blocks.fallen[index][1] : 8 - 2 * index
                                        width: 2; height: 2; antialiasing: false
                                        color: blocks.tint[index]
                                        Px { color: "#ffffff"; opacity: 0.3 }
                                    }
                                }
                            }
                        }
                    }
                    // at night: a little telescope, now and then a shooting star (an act)
                    Loader {
                        active: root.has("telescope")
                        sourceComponent: Component {
                            Item {
                                Pic {
                                    x: 15; y: -2
                                    rows: [".....tt", "...ttt.", ".ttt...", "tt....."]
                                    inks: ({ t: "#8b93ab" })
                                }
                                Px { x: 21; y: -2; color: "#dfe7ff" }
                                Pic { x: 16; y: 2; rows: ["..l..", "..l..", ".l.l.", ".l.l.", "l...l", "l...l", "l...l", "l...l"]; inks: ({ l: "#5d6275" }) }
                            }
                        }
                    }
                    Loader {
                        active: root.has("shoot")
                        sourceComponent: Component {
                            Item {
                                readonly property var path: [[1, -6], [4, -6], [7, -5], [10, -5], [13, -4], [16, -4], [19, -3]]
                                readonly property var at: path[Math.min(root.f, path.length - 1)]
                                Px { x: parent.at[0]; y: parent.at[1]; color: "#fff4cf" }
                                Px { x: parent.at[0] - 1; y: parent.at[1]; color: "#fff4cf"; opacity: 0.55 }
                                Px { x: parent.at[0] - 2; y: parent.at[1] - (root.f % 2); color: "#fff4cf"; opacity: 0.25 }
                            }
                        }
                    }

                    // ---- after an answer ----
                    // fixed: a wrench in the raised hand (w 1: mid-twirl)
                    Loader {
                        active: root.has("wrench")
                        sourceComponent: Component {
                            Pic {
                                x: 17; y: root.armR === 2 ? -3 : -1
                                rows: root.fx.w === 1 ? ["w.w..", "www..", "..h..", "...h."] : ["..w.w", "..www", ".h...", "h...."]
                                inks: ({ w: "#b8c0cf", h: "#8d96a8" })
                            }
                        }
                    }
                    // found: a lightbulb (f 0 off, 1 lit, 2 lit and shining)
                    Loader {
                        active: root.has("bulb")
                        sourceComponent: Component {
                            Item {
                                readonly property color glass: root.f >= 1 ? "#ffd166" : "#d9d4c7"
                                Pic {
                                    x: 16; y: -6
                                    rows: [".yyy.", "yhyyy", "yyyyy", ".yyy.", ".ggg.", "..g.."]
                                    inks: ({ y: parent.glass, h: root.f >= 1 ? "#fff4cf" : "#ece8de", g: "#9aa0ae" })
                                }
                                Px { visible: root.f === 2; x: 14; y: -5; color: "#fff4cf" }
                                Px { visible: root.f === 2; x: 22; y: -5; color: "#fff4cf" }
                                Px { visible: root.f === 2; x: 14; y: -3; color: "#fff4cf"; opacity: 0.6 }
                                Px { visible: root.f === 2; x: 22; y: -3; color: "#fff4cf"; opacity: 0.6 }
                            }
                        }
                    }
                    // stuck: a sweat drop (f 1: sliding down)
                    Loader {
                        active: root.has("sweat")
                        sourceComponent: Component {
                            Pic { x: 16; y: -1 + root.f; rows: [".d", "dd", "dd"]; inks: ({ d: "#8ec5ff" }) }
                        }
                    }
                    // background work running: a thought bubble whose dots come up one by one (f: how many)
                    Loader {
                        active: root.has("dots")
                        sourceComponent: Component {
                            Item {
                                Pic {
                                    x: 15; y: -6
                                    rows: [".wwwww.", "wwwwwww", ".wwwww.", "w......"]
                                    inks: ({ w: Qt.alpha(root.cream, 0.92) })
                                }
                                Repeater {
                                    model: 3
                                    Px {
                                        required property int index
                                        visible: index < root.f
                                        x: 16 + index * 2; y: -5
                                        color: root.col("primary", "#7aa2f7")
                                    }
                                }
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
                        visible: root.tired >= 2 && !(root.notice && !root.alert)   // the update badge takes its place
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
                    // Zzz (slumped by the hourglass)
                    Repeater {
                        model: root.sitting ? [{ x: 12, y: -3 }, { x: 15, y: -7 }] : [{ x: 16, y: 0 }, { x: 18, y: -4 }]
                        Item {
                            id: zed
                            required property var modelData
                            required property int index
                            readonly property color c: Qt.alpha(root.cream, 0.85)
                            x: modelData.x; y: modelData.y
                            visible: root.sitting && root.eyeR === "sleep" && !root.fx.prop
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
                    // an important update waits (update-check.py): a green badge with an arrow up, on the left,
                    // still (no bounce: it isn't urgent); the "!" check-in wins
                    Item {
                        id: update
                        visible: root.notice && !root.alert
                        readonly property color c: root.col("green", "#9ece6a")
                        Rectangle { x: -3.5; y: -4.4; width: 7; height: 7; radius: 1.4; color: "black"; opacity: 0.3 }
                        Rectangle { x: -4; y: -5; width: 7; height: 7; radius: 1.4; color: update.c }
                        Px { x: -3; y: -5; width: 5; color: Qt.lighter(update.c, 1.18) }
                        Pic { x: -3; y: -4; rows: ["..x..", ".xxx.", "xxxxx", ".xxx.", ".xxx."]; inks: ({ x: root.ink }) }
                    }
                }
            }
        }
    }

    // ---------- timing ----------
    // every timer that decides what Clawd does is a Beat on the shared clock, so all the views agree
    Beat {   // a blink every few seconds (now and then it skips one); slower and longer when tired
        period: root.tired >= 1 ? 3600 : 4400
        armed: root.live && ["open", "wide", "half", "heavy", "up"].indexOf(root.restEyes) >= 0 && !root.shades
        onBeat: tick => {
            if (root.chance(tick, 41) < 0.2) return
            root.blinking = true
            unblink.interval = root.tired >= 2 ? 340 : 140
            unblink.restart()
        }
    }
    Timer { id: unblink; interval: 140; onTriggered: root.blinking = false }

    // each state's own loop: a short burst every few seconds (off duty: its hobby's)
    readonly property var hobbyAct: ({ book: "read", game: "play", music: "groove", paint: "paint", bubbles: "blow",
                                       yoyo: "yoyo", plant: "water", blocks: "stack", telescope: "gaze", coffee: "sip" })
    readonly property string loopAct: sitting ? "snore" : alert ? "" : celebrate ? "cheer"
        : ({ typing: "type", thinking: "think", building: "hammer", reading: "scan", web: "surf", juggling: "juggle",
             sweeping: "sweep", waiting: "ask", attention: "hail", running: "wait", done: "proud", fixed: "tighten",
             found: "glow", stuck: "shrug" })[doing]
          ?? (weather === "rain" && !doing ? "rain" : idle ? hobbyAct[hobby] ?? "" : tired >= 3 ? "nod" : tired >= 2 ? "yawn" : "")
    readonly property var every: ({ snore: 2400, cheer: 6000, type: 3600, think: 2600, hammer: 3200, scan: 3800,
                                    surf: 3400, juggle: 3600, sweep: 3200, ask: 2400, hail: 2200, wait: 2800, proud: 9000,
                                    tighten: 8000, glow: 7000, shrug: 8000, nod: 7000, yawn: 11000, rain: 2600,
                                    read: 7000, play: 5500, groove: 4200, paint: 6500, blow: 6500, yoyo: 5000,
                                    water: 8000, stack: 6500, gaze: 7500, sip: 9000 })
    Beat {
        id: loop
        period: root.every[root.loopAct] ?? 4000
        armed: root.live && root.loopAct !== ""
        onBeat: tick => {
            if (root.idle) root.syncHobby(tick * loop.period)     // the hobby (and how far along it is) at this beat
            // a tired Clawd yawns or nods off over its work (or its hobby) now and then
            if ((root.doing || root.idle) && root.tired >= 2 && root.chance(tick, 1) < 0.18)
                root.play(root.tired >= 3 ? "nod" : "yawn", 0, tick)
            else root.play(root.loopAct, 0, tick)
        }
    }

    // off duty: the next hobby, on the five-minute mark
    Beat {
        period: root.hobbySlot
        armed: root.live && root.idle
        onBeat: tick => root.syncHobby(tick * root.hobbySlot)
    }

    // now and then, between the hobby's bursts (about every half minute, never on a regular rhythm)
    Beat {
        period: 15000
        armed: root.live && root.idle
        onBeat: tick => {
            if (root.chance(tick, 31) >= 0.45) return
            const o = ["look", "look", "hop", "smile"]
            if (!root.twoHands) o.push("wave", "stretch", "whistle")
            if (root.tired >= 1) o.push("yawn", "yawn")
            if (root.daypart === "night" && root.held !== "telescope") o.push("stargaze")
            if ((root.daypart === "morning" || root.daypart === "day") && !root.weather && root.season !== "xmas") o.push("butterfly")
            if (root.season === "halloween") o.push("bat", "bat")
            root.play(root.pickAt(o, tick, 32), 0, tick)
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

    // popup only: stars and steam twinkle, a soft idle bob
    Timer { interval: 650; running: root.looping; repeat: true; onTriggered: root.twinkle++ }
    SequentialAnimation {
        running: root.looping && !root.playing
        loops: Animation.Infinite
        onRunningChanged: if (!running) bob.y = 0
        NumberAnimation {
            target: bob; property: "y"
            to: root.sitting ? -0.25 : -0.45
            duration: root.sitting ? 1800 : root.tired >= 2 ? 1100 : 700
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: bob; property: "y"; to: 0
            duration: root.sitting ? 1800 : root.tired >= 2 ? 1100 : 700
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
