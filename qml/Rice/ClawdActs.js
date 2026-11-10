.pragma library

// Clawd's acts: every motion it has, as short lists of stepped poses ("frames"), and its hobbies.
// Clawd.qml plays them (one frame at a time, on a timer) and ClawdArt.js draws each frame.
//
// A frame is a plain object. What it can say:
//   d       how long it stays, ms
//   sh      the body's shape: n standing, d dipped, c crouched (squashed), f flat, s stretched, t on tiptoe
//   dx, dy  the whole figure moved (dy < 0: off the ground);  legs: tuck | dangle | a | b (a pair lifted) | r
//   lean    its upper half shifted (-1 | 1);  flip: mirrored;  spin: 90 | 180 | 270;  hide: not drawn
//   armL, armR   -1 drooping, 0 resting, 1 raised, 6 higher, 2 up high, 3 over the eyes, 4 hidden (the
//                prop draws the hands), 5 held out
//   eyes (or eyeL, eyeR), glance (-1 | 1), mouth, blush, hat (lifted by)
//   prop, prop2, prop3   things shown for this frame, `f` (and `g`) their own frame
//   hold    another thing in its hands than the state's;  bare: nothing in them;  norest: no rest prop
//   tick, zz, tw   counters to bump (keystrokes, snores, twinkles);  adv / set: the hobby's progress
//   ...and whatever a prop reads for itself (bob, haul, dive, bar, by, tale, ...)
//
// An act is a list of frames, or a function (seed, env) -> frames. `seed` is the clock beat (or the
// click) it's played for and every bit of chance in it comes from chance(seed, ...), so it goes the
// same way in every view. `env`: { prog, k, grow, hat, hands, look, tired, zoneFrom, zoneTo, from }.

// a number in [0, 1) that depends only on its (integer) arguments
function chance(a, b, c) {
    let h = Math.imul((a | 0) ^ 0x9e3779b9, 0x85ebca6b) ^ Math.imul(((b | 0) + 0x632be5ab) | 0, 0xc2b2ae35)
          ^ Math.imul(((c | 0) + 0x27d4eb2f) | 0, 0x165667b1)
    h ^= h >>> 16; h = Math.imul(h, 0x7feb352d); h ^= h >>> 15; h = Math.imul(h, 0x846ca68b); h ^= h >>> 16
    return (h >>> 0) / 4294967296
}
function pickAt(list, a, b) { return list[Math.floor(chance(a, b, 7) * list.length)] }

// ---------- building blocks ----------
function seq(n, d, fn) {
    const a = []
    for (let i = 0; i < n; i++) { const o = fn(i) || {}; if (o.d === undefined) o.d = d; a.push(o) }
    return a
}
function join() {
    let a = []
    for (let i = 0; i < arguments.length; i++) a = a.concat(arguments[i])
    return a
}
function each(frames, extra) { return frames.map(f => Object.assign({}, extra, f)) }
// a hop, the way things with weight do it: a crouch first, a stretch on the way up, a moment hanging
// at the top (`apex` goes into that frame), a squash and a puff of dust on landing
function hop(h, apex, all) {
    const a = [{ d: 90, sh: "c" }, { d: 55, sh: "s", dy: -1 }]
    if (h >= 3) a.push({ d: 60, dy: 1 - h, legs: "tuck" })
    a.push(Object.assign({ d: 110, dy: -h, legs: "tuck" }, apex || {}))
    if (h >= 3) a.push({ d: 60, dy: 1 - h, legs: "tuck" })
    a.push({ d: 55, sh: "s", dy: -1 }, { d: 90, sh: "c", dust: 1 }, { d: 70, sh: "d", dust: 2 })
    return all ? each(a, all) : a
}
// steps from `from` to `to` (cells), the legs taking turns
function walk(from, to, d, extra) {
    const a = [], dir = to > from ? 1 : -1
    for (let x = from + dir, i = 0; dir > 0 ? x <= to : x >= to; x += dir, i++)
        a.push(Object.assign({ d: d, dx: x, legs: i % 2 ? "b" : "a" }, extra || {}))
    return a
}

// ---------- hobbies ----------
// act: its burst; every: ms between bursts; text: what the widget says; stage(k): how far along its
// little project is at the k-th burst of a slot (what `prog` shows; the burst itself moves it on with
// adv/set, so the two agree); zone: where the thing is (front: in both hands)
const HOBBIES = {
    book:      { act: "read",   every: 9500,  text: "Reading a book of fables.", zone: "front" },
    game:      { act: "play",   every: 8500,  text: "Gaming on its break.", zone: "front" },
    music:     { act: "groove", every: 7000,  text: "Vibing to some music.", zone: "" },
    paint:     { act: "paint",  every: 9000,  text: "Painting a little masterpiece.", stage: k => k % 8 },
    bubbles:   { act: "blow",   every: 9000,  text: "Blowing bubbles." },
    yoyo:      { act: "yoyo",   every: 8000,  text: "Practising yo-yo tricks." },
    plant:     { act: "water",  every: 10000, text: "Watering its plant." },
    blocks:    { act: "stack",  every: 8500,  text: "Building a tower.", stage: k => k % 5 },
    telescope: { act: "gaze",   every: 9500,  text: "Stargazing." },
    coffee:    { act: "sip",    every: 10000, text: "Coffee break." },
    knit:      { act: "knit",   every: 9500,  text: "Knitting a scarf.", stage: k => k % 6, zone: "front" },
    fish:      { act: "fish",   every: 10500, text: "Gone fishing." },
    kite:      { act: "kite",   every: 8500,  text: "Flying a kite." },
    uke:       { act: "strum",  every: 8000,  text: "Strumming its ukulele.", zone: "front" },
    bowl:      { act: "slurp",  every: 9500,  text: "Slurping noodles.", zone: "front" },
    origami:   { act: "fold",   every: 9000,  text: "Folding a paper crane.", stage: k => k % 4, zone: "front" },
    cube:      { act: "twist",  every: 8500,  text: "Solving a puzzle cube.", stage: k => k, zone: "front" },
    skate:     { act: "skate",  every: 8500,  text: "Skating around.", zone: "" },
    fire:      { act: "roast",  every: 9500,  text: "Toasting marshmallows.", stage: k => k % 4 },
    yoga:      { act: "yoga",   every: 9500,  text: "Doing its morning stretches.", stage: k => k % 4, zone: "" },
    weights:   { act: "lift",   every: 9500,  text: "Lifting weights.", stage: k => k % 3, zone: "front" },
    plane:     { act: "toss",   every: 9000,  text: "Flying paper planes." },
    rope:      { act: "skip",   every: 9000,  text: "Skipping rope.", zone: "" },
    cat:       { act: "pet",    every: 9500,  text: "Hanging out with a cat.", stage: k => Math.min(3, k >> 1) },
    pan:       { act: "cook",   every: 9000,  text: "Flipping pancakes.", stage: k => k % 5 },
    snowman:   { act: "snow",   every: 9500,  text: "Building a snowman.", stage: k => Math.min(4, k % 9) },
    pumpkin:   { act: "carve",  every: 9500,  text: "Carving a pumpkin.", stage: k => Math.min(3, k % 6) },
    tree:      { act: "trim",   every: 9500,  text: "Decorating the tree.", stage: k => Math.min(5, k % 8) },
    sparkler:  { act: "fizz",   every: 7500,  text: "Lighting sparklers." },
    umbrella:  { act: "splash", every: 8000,  text: "Out in the rain." },
}
const OUTDOORS = ["fish", "kite", "skate", "plane", "rope", "bubbles", "fire", "telescope"]
const FAIR_WEATHER = ["fish", "kite", "skate", "plane", "rope", "bubbles"]

// what it might do with a free moment, given the hour, the day, the season and the sky (a name can
// be in more than once: likelier)
function pool(c) {
    let o
    const late = c.daypart === "evening" || c.daypart === "night"
    if (c.tired >= 2) o = ["coffee", "coffee", "book", "bowl", "cat", "knit", "music"].concat(late ? ["fire"] : [])
    else if (c.daypart === "morning")
        o = ["coffee", "coffee", "pan", "pan", "yoga", "yoga", "plant", "plant", "book", "cat", "origami", "game", "uke", "knit"]
    else if (c.daypart === "night")
        o = ["telescope", "telescope", "telescope", "fire", "fire", "book", "book", "bowl", "game", "cube", "knit", "cat", "music"]
    else if (c.daypart === "evening")
        o = ["fire", "fire", "bowl", "bowl", "uke", "knit", "book", "game", "fish", "cat", "cube", "paint", "origami", "yoyo", "music"]
    else
        o = ["book", "game", "paint", "paint", "bubbles", "yoyo", "blocks", "plant", "knit", "fish", "kite", "uke",
             "origami", "cube", "skate", "weights", "plane", "rope", "cat", "music"]
    if (c.weekend && c.daypart !== "night" && c.tired < 2) o = o.concat(["skate", "kite", "fish", "game", "plane"])
    if (c.season === "halloween") o = o.concat(["pumpkin", "pumpkin", "pumpkin", "pumpkin", "pumpkin"])
    if (c.season === "xmas") o = o.concat(["tree", "tree", "tree", "tree", "tree", "knit"])
    if (c.season === "newyear") o = o.concat(["sparkler", "sparkler", "sparkler", "sparkler", "sparkler"])
    if (c.weather === "snow") o = o.filter(h => FAIR_WEATHER.indexOf(h) < 0).concat(["snowman", "snowman", "snowman", "snowman"])
    if (c.weather === "rain") o = o.filter(h => OUTDOORS.indexOf(h) < 0).concat(["umbrella", "umbrella", "umbrella", "umbrella"])
    // something playing: the headphones stay on whatever it does, and it stops to listen more often
    if (c.music) o = o.concat(["music", "music", "music", "music", "music"])
    return o
}
// the hobby of a slot: the same in every view, never the same one twice running
function hobbyFor(slot, c) {
    // (worked out along the last two hours of slots, so that a slot's answer doesn't depend on who asks when)
    const o = pool(c)
    let prev = ""
    for (let i = slot - 24; i <= slot; i++) {
        let h = pickAt(o, i, 21)
        if (h === prev) {
            const others = o.filter((x, j) => x !== prev && o.indexOf(x) === j)
            if (others.length) h = pickAt(others, i, 22)
        }
        prev = h
    }
    return prev
}
// how far along the hobby is at its k-th burst (the plant grows at about every other watering)
function stage(hobby, slot, k) {
    if (hobby === "plant") { let g = 0; for (let j = 0; j < k && g < 3; j++) if (chance(slot, j, 13) < 0.5) g++; return g }
    const h = HOBBIES[hobby]
    return h && h.stage ? h.stage(k) : 0
}
function grows(slot, k) { return chance(slot, k, 13) < 0.5 }
function zoneOf(held) {
    if (!held) return ""
    const h = HOBBIES[held]
    if (h && h.zone !== undefined) return h.zone
    return held === "laptop" ? "front" : held === "music" ? "" : "right"
}

// ---------- every state's own loop: how often its burst comes ----------
const EVERY = { snore: 3000, cheer: 6000, type: 4200, think: 3200, hammer: 3800, scan: 4200, surf: 3800, delegate: 4600,
                sweep: 3800, ask: 2800, hail: 3000, wait: 4600, proud: 9000, tighten: 8000, glow: 7000, shrug: 8000,
                nod: 7000, yawn: 11000 }
function every(act) {
    if (EVERY[act]) return EVERY[act]
    for (const h in HOBBIES) if (HOBBIES[h].act === act) return HOBBIES[h].every
    return 4000
}

// ---------- the acts ----------
const ACTS = {}

// ---- hover: hello ----
ACTS.hop = () => hop(2)
ACTS.wave = [{ d: 100, armR: 1 }, { d: 90, armR: 6 }, { d: 130, armR: 2, eyes: "joy" }, { d: 110, armR: 6, eyes: "joy" },
             { d: 130, armR: 2, eyes: "joy" }, { d: 110, armR: 6, eyes: "joy" }, { d: 150, armR: 2, eyes: "joy", mouth: "smile" },
             { d: 110, armR: 1, eyes: "joy" }, { d: 90 }]
ACTS.wink = [{ d: 70, eyeR: "half" }, { d: 80, eyeR: "blink" }, { d: 520, eyeR: "joy", blush: true }, { d: 90, eyeR: "blink" }]
ACTS.smile = [{ d: 110, eyes: "joy" }, { d: 620, eyes: "joy", blush: true, mouth: "smile" }, { d: 100, eyes: "joy" }]
ACTS.peekaboo = [{ d: 110, armL: 1, armR: 1 }, { d: 420, armL: 3, armR: 3, eyes: "hidden" }, { d: 100, armL: 1, armR: 1, eyes: "wide" },
                 { d: 90, sh: "t", armL: 6, armR: 6, eyes: "joy" }, { d: 480, sh: "t", armL: 2, armR: 2, eyes: "joy", mouth: "smile" },
                 { d: 110, armL: 1, armR: 1, eyes: "joy" }]
ACTS.bow = [{ d: 120, sh: "d", eyes: "half", armL: -1, armR: -1 }, { d: 460, sh: "c", eyes: "sleep", armL: -1, armR: -1 },
            { d: 120, sh: "d", eyes: "half" }, { d: 100 }]
ACTS.blep = [{ d: 100, eyes: "joy" }, { d: 600, eyes: "joy", mouth: "tongue" }, { d: 90, eyes: "joy" }]
ACTS.tada = [{ d: 110, sh: "c" }, { d: 90, sh: "t", armL: 1, armR: 1 },
             { d: 460, sh: "t", armL: 5, armR: 5, eyes: "joy", mouth: "smile", prop: "sparkle", f: 0 },
             { d: 220, armL: 5, armR: 5, eyes: "joy", prop: "sparkle", f: 1 }, { d: 110, armL: 0, armR: 0 }]
// tips its hat
ACTS.doff = [{ d: 110, armR: 1 }, { d: 100, armR: 2, hat: -1 }, { d: 440, armR: 2, hat: -2, eyes: "joy", sh: "d" },
             { d: 100, armR: 2, hat: -1 }, { d: 110, armR: 1 }, { d: 80 }]
// leans towards the pointer
ACTS.nuzzle = (t, e) => {
    const l = e.look || 1
    return [{ d: 130, lean: l, eyes: "joy" }, { d: 520, lean: l, eyes: "joy", blush: true, mouth: "smile" }, { d: 130, eyes: "joy" }]
}
// ...or looks away, blushing
ACTS.shy = (t, e) => {
    const l = -(e.look || 1)
    return [{ d: 150, glance: l, blush: true }, { d: 520, glance: l, blush: true, eyes: "half", lean: l }, { d: 260, blush: true, eyes: "joy" }]
}
ACTS.bounce = () => join(hop(1), hop(1, { eyes: "joy" }))
// slumped by the hourglass: opens one eye at you
ACTS.peek = [{ d: 1100, eyeL: "half", eyeR: "sleep" }]
// stroked back and forth
ACTS.petted = seq(8, 150, i => ({ eyes: "joy", blush: true, mouth: i > 2 ? "smile" : undefined, prop: "hearts", f: i, lean: [0, 1, 0, -1][i % 4],
                                 sh: i % 4 === 1 ? "d" : undefined }))

// ---- clicks ----
ACTS.dance = () => join(
    seq(12, 125, i => ({ dx: [0, -1, -1, 0, 1, 1][i % 6], lean: [0, -1, 0, 0, 1, 0][i % 6], legs: i % 2 ? "a" : "b",
                         armL: i % 2 ? 2 : 0, armR: i % 2 ? 0 : 2, eyes: "joy", prop: "note", duet: i > 5, f: i })),
    [{ d: 110, sh: "c", eyes: "joy" }, { d: 420, sh: "t", armL: 5, armR: 5, eyes: "joy", mouth: "smile", prop: "sparkle", f: 0 }, { d: 140, eyes: "joy" }])
ACTS.flip = [{ d: 110, sh: "c" }, { d: 60, sh: "s", dy: -1 }, { d: 65, dy: -3, legs: "tuck" }, { d: 65, dy: -5, spin: 90, legs: "tuck" },
             { d: 70, dy: -6, spin: 180, legs: "tuck", eyes: "joy" }, { d: 65, dy: -5, spin: 270, legs: "tuck", eyes: "joy" },
             { d: 60, dy: -3, legs: "tuck" }, { d: 55, sh: "s", dy: -1 }, { d: 100, sh: "c", dust: 1 }, { d: 80, sh: "d", dust: 2 },
             { d: 420, eyes: "joy", armL: 2, armR: 2, mouth: "smile" }, { d: 100, armL: 1, armR: 1 }]
ACTS.heart = seq(8, 130, i => ({ eyes: i < 6 ? "heart" : "joy", blush: true, prop: "heart", f: i, sh: i === 1 ? "d" : undefined, lean: i === 3 ? 1 : i === 5 ? -1 : 0 }))
ACTS.juggle = () => join(seq(14, 105, i => ({ armL: i % 2 ? 1 : 0, armR: i % 2 ? 0 : 1, eyes: "up", prop: "balls", f: i })),
                         [{ d: 300, armL: 2, armR: 2, eyes: "joy" }])
ACTS.magic = join([{ d: 180, armL: 1, armR: 1, eyes: "up" }],
                  seq(6, 110, i => ({ armL: 2, armR: 2, eyes: "up", prop: "spark", magic: true, f: i })),
                  [{ d: 520, armL: 2, armR: 2, eyes: "star", prop: "spark", magic: true, f: 4, prop2: "sparkle" }, { d: 140, armL: 1, armR: 1, eyes: "joy" }])
ACTS.melt = [{ d: 140, eyes: "half" }, { d: 130, sh: "d", eyes: "sleep", armL: -1, armR: -1 }, { d: 120, sh: "c", eyes: "sleep", armL: -1, armR: -1 },
             { d: 120, sh: "f", eyes: "sleep", armL: 4, armR: 4 }, { d: 650, hide: true, prop: "puddle", f: 0 }, { d: 260, hide: true, prop: "puddle", f: 1 },
             { d: 90, sh: "f", eyes: "wide", armL: 4, armR: 4 }, { d: 80, sh: "s", dy: -2, eyes: "wide" }, { d: 80, sh: "s", dy: -1, eyes: "wide" },
             { d: 90, sh: "c", dust: 1 }, { d: 260, eyes: "joy" }]
ACTS.shades = [{ d: 80, prop: "drop", f: 0 }, { d: 80, prop: "drop", f: 1 }, { d: 80, prop: "drop", f: 2 }, { d: 90, prop: "drop", f: 3, sh: "d" },
               { d: 420, prop: "drop", f: 3, armR: 1 }, { d: 150, prop: "drop", f: 3, armR: 1, glint: true },
               { d: 520, prop: "drop", f: 3, armR: 1, lean: -1 }, { d: 150, prop: "drop", f: 3 }]
ACTS.sneeze = [{ d: 260, eyes: "half", mouth: "o", lean: -1 }, { d: 300, sh: "t", eyes: "sleep", mouth: "O", lean: -1 },
               { d: 90, sh: "c", eyes: "squint", dx: 1, prop: "puff", f: 0 }, { d: 130, sh: "c", eyes: "squint", prop: "puff", f: 1 },
               { d: 160, eyes: "blink", prop: "puff", f: 2 }, { d: 300, eyes: "half" }]
ACTS.flex = [{ d: 200, armL: 2, armR: 2, eyes: "squint" }, { d: 130, armL: 6, armR: 6 },
             { d: 380, sh: "t", armL: 2, armR: 2, eyes: "joy", prop: "sparkle", f: 0 }, { d: 130, armL: 6, armR: 6 },
             { d: 380, sh: "t", armL: 2, armR: 2, eyes: "joy", prop: "sparkle", f: 1 }, { d: 130, armL: 1, armR: 1 }]
ACTS.surprise = [{ d: 90, sh: "c" }, { d: 100, sh: "s", dy: -2, eyes: "wide", mouth: "o", prop: "bang" },
                 { d: 120, dy: -3, eyes: "wide", mouth: "o", prop: "bang", legs: "tuck", armL: 5, armR: 5 }, { d: 90, sh: "s", dy: -1, eyes: "wide", prop: "bang" },
                 { d: 110, sh: "c", eyes: "wide", dust: 1 }, { d: 420, eyes: "wide", armL: 1, armR: 1 }, { d: 140, eyes: "blink" }]
ACTS.giggle = seq(8, 90, i => ({ dx: i % 2, sh: i % 2 ? "d" : "n", eyes: "joy", blush: true, mouth: "smile" }))
ACTS.spin = join(seq(8, 90, i => ({ flip: i % 2 === 1, glance: i % 2 ? -1 : 1, lean: i % 2 ? -1 : 1 })),
                 [{ d: 110, sh: "c", dust: 1 }, { d: 360, sh: "t", eyes: "joy", armL: 2, armR: 2 }, { d: 100 }])
ACTS.dizzy = join(seq(14, 95, i => ({ dx: [0, 1, 0, -1][i % 4], lean: [1, 0, -1, 0][i % 4], eyes: "dizzy", prop: "stars", f: i })),
                  [{ d: 500, sh: "d", eyes: "dizzy", prop: "stars", f: 0 }])
ACTS.sigh = [{ d: 520, eyes: "half", glance: 1 }, { d: 480, eyes: "sleep", mouth: "o" }, { d: 320, eyes: "half" }]
// slides off backwards, in shades
ACTS.moonwalk = join([{ d: 110, prop: "drop", f: 1 }, { d: 110, prop: "drop", f: 3 }],
                     walk(0, -4, 150, { prop: "drop", f: 3, lean: 1 }), [{ d: 260, dx: -4, prop: "drop", f: 3, armR: 1, glint: true }],
                     walk(-4, 0, 150, { prop: "drop", f: 3, lean: -1 }), [{ d: 320, prop: "drop", f: 3, armL: 5, armR: 5 }, { d: 110, prop: "drop", f: 2 }])
ACTS.cartwheel = [{ d: 110, sh: "c" }, { d: 90, dx: 1, dy: -2, spin: 90, legs: "tuck" }, { d: 90, dx: 2, dy: -3, spin: 180, legs: "tuck" },
                  { d: 90, dx: 3, dy: -2, spin: 270, legs: "tuck" }, { d: 110, dx: 4, sh: "c", dust: 1 }, { d: 220, dx: 4, eyes: "joy", armL: 2, armR: 2 },
                  { d: 90, dx: 3, dy: -2, spin: 270, legs: "tuck" }, { d: 90, dx: 2, dy: -3, spin: 180, legs: "tuck" },
                  { d: 90, dx: 1, dy: -2, spin: 90, legs: "tuck" }, { d: 110, sh: "c", dust: 1 }, { d: 300, eyes: "joy", armL: 5, armR: 5, mouth: "smile" }]
// bubblegum: a bubble as big as its face, then pop
ACTS.gum = [{ d: 200, mouth: "chew" }, { d: 150, mouth: "line" }, { d: 200, mouth: "chew" }, { d: 150, mouth: "line" },
            { d: 240, prop: "gum", g: 1, eyes: "half" }, { d: 260, prop: "gum", g: 2, eyes: "half" }, { d: 420, prop: "gum", g: 3, eyes: "hidden" },
            { d: 110, sh: "c", prop: "gum", g: 4, eyes: "wide" }, { d: 380, prop: "gum", g: 5, eyes: "wide" }, { d: 150, prop: "gum", g: 5, eyes: "blink" },
            { d: 300, mouth: "tongue", eyes: "joy" }]
// carried off by a balloon, until it pops
ACTS.balloon = join([{ d: 200, armR: 1, prop: "balloon" }, { d: 200, armR: 2, prop: "balloon", eyes: "up" }],
                    seq(4, 170, i => ({ dy: -[1, 2, 3, 3][i], dx: [0, 0, 1, 2][i], armR: 2, prop: "balloon", legs: "dangle", eyes: i < 2 ? "wide" : "joy" })),
                    [{ d: 520, dy: -3, dx: 1, armR: 2, prop: "balloon", legs: "dangle", eyes: "joy" },
                     { d: 90, dy: -3, dx: 1, armR: 2, prop: "balloon", g: 9, prop2: "bang", legs: "dangle", eyes: "wide" },
                     { d: 70, dy: -2, dx: 1, sh: "s", eyes: "wide" }, { d: 60, dy: -1, sh: "s", eyes: "wide" }, { d: 140, sh: "f", dust: 1, eyes: "squint", armL: 4, armR: 4 },
                     { d: 120, sh: "c", dust: 2, eyes: "dizzy" }, { d: 320, eyes: "dizzy", prop: "stars", f: 0 }, { d: 220, eyes: "dizzy", prop: "stars", f: 2 }])
// a level gained
ACTS.levelup = [{ d: 140, sh: "c" }, { d: 120, sh: "c", prop: "levelup", f: 0 }, { d: 120, prop: "levelup", f: 1, eyes: "up" },
                { d: 150, sh: "t", prop: "levelup", f: 2, eyes: "shine", armL: 6, armR: 6 }, { d: 160, sh: "t", prop: "levelup", f: 3, eyes: "shine", armL: 2, armR: 2 },
                { d: 160, sh: "t", prop: "levelup", f: 4, eyes: "shine", armL: 2, armR: 2, prop2: "sparkle" },
                { d: 160, sh: "t", prop: "levelup", f: 5, eyes: "star", armL: 2, armR: 2 },
                { d: 160, sh: "t", prop: "levelup", f: 6, eyes: "star", armL: 2, armR: 2, prop2: "sparkle" },
                { d: 180, prop: "levelup", f: 7, eyes: "star", armL: 2, armR: 2 }, { d: 300, eyes: "joy", armL: 1, armR: 1, mouth: "smile" }]
// lift-off, and back down under a parachute
ACTS.rocket = [{ d: 100, sh: "c", dx: 1 }, { d: 90, sh: "c", dx: -1, prop: "jet", f: 0 }, { d: 90, sh: "c", dx: 1, prop: "jet", f: 1, eyes: "squint" },
               { d: 90, sh: "c", prop: "jet", f: 0, eyes: "squint" }, { d: 70, sh: "s", dy: -2, prop: "jet", f: 1, dust: 1 },
               { d: 70, sh: "s", dy: -6, prop: "jet", f: 0, dust: 2 }, { d: 70, sh: "s", dy: -11, prop: "jet", f: 1 }, { d: 90, sh: "s", dy: -17, prop: "jet", f: 0 },
               { d: 700, hide: true }, { d: 200, dy: -13, prop: "chute", legs: "dangle", eyes: "wide" },
               { d: 200, dy: -10, dx: 1, prop: "chute", legs: "dangle", eyes: "wide" }, { d: 200, dy: -7, prop: "chute", legs: "dangle", eyes: "joy" },
               { d: 200, dy: -5, dx: -1, prop: "chute", legs: "dangle", eyes: "joy" }, { d: 200, dy: -3, prop: "chute", legs: "dangle", eyes: "joy" },
               { d: 200, dy: -1, dx: 1, prop: "chute", legs: "dangle", eyes: "joy" }, { d: 140, sh: "c", dust: 1 },
               { d: 400, eyes: "joy", armL: 2, armR: 2, mouth: "smile" }]
ACTS.sing = join([{ d: 160, armR: 1, prop: "mic" }],
                 seq(8, 160, i => ({ armR: 1, prop: "mic", mouth: i % 2 ? "O" : "o", eyes: "joy", prop2: "note", duet: true, f: i, lean: [0, 1, 0, -1][i % 4] })),
                 [{ d: 300, armR: 2, prop: "mic", eyes: "joy", mouth: "smile" }])
ACTS.popper = t => join([{ d: 200, armR: 1, prop: "popper" }, { d: 240, armR: 2, prop: "popper", eyes: "squint" },
                         { d: 80, sh: "c", armR: 2, prop: "popper", prop2: "bang", eyes: "wide" }],
                        seq(8, 110, i => ({ armR: 2, prop: "popper", prop2: "burst", hue: t, f: i + 1, eyes: i < 2 ? "wide" : "joy" })), [{ d: 200, eyes: "joy" }])

// ---- tired ----
ACTS.yawn = [{ d: 220, eyes: "half", mouth: "o" }, { d: 200, sh: "t", eyes: "sleep", mouth: "O", armL: 6, armR: 6 },
             { d: 600, sh: "t", eyes: "sleep", mouth: "O", armL: 2, armR: 2 }, { d: 220, eyes: "sleep", mouth: "o", armL: 1, armR: 1 }, { d: 260, eyes: "half" }]
ACTS.chug = [{ d: 200, armR: 1, prop: "cup", f: 0 }, { d: 700, armR: 2, prop: "cup", f: 1, eyes: "sleep" },
             { d: 160, armR: 1, prop: "cup", f: 0, eyes: "wide" }, { d: 90, sh: "s", dy: -1, eyes: "wide", prop: "bang" },
             { d: 330, eyes: "wide", prop: "bang" }, { d: 200, eyes: "half" }]
ACTS.nod = [{ d: 520, eyes: "sleep" }, { d: 300, sh: "d", eyes: "sleep", prop: "z", f: 0, lean: 1 }, { d: 420, sh: "c", eyes: "sleep", prop: "z", f: 1, lean: 1 },
            { d: 90, sh: "s", dy: -1, eyes: "wide" }, { d: 340, eyes: "wide" }, { d: 220, eyes: "heavy" }]
ACTS.rub = [{ d: 200, armL: 3, eyeL: "hidden", eyeR: "half" }, { d: 200, armL: 3, eyeL: "hidden", eyeR: "sleep" },
            { d: 200, armL: 3, eyeL: "hidden", eyeR: "half" }, { d: 200, armL: 3, eyeL: "hidden", eyeR: "sleep" }, { d: 300, eyes: "half" }]
// out of energy: what it dreams of
ACTS.dream = join(seq(5, 420, i => ({ prop: "dream", f: i, eyes: "sleep" })), [{ d: 600, prop: "dream", f: 4, eyes: "sleep", mouth: "smile" }])

// ---- at work ----
ACTS.type = t => {
    const v = chance(t, 51)
    if (v < 0.5) return seq(8, 120, i => ({ hl: i % 2, hr: 1 - i % 2, tick: i % 2 === 0 }))
    if (v < 0.72)       // a fast run, the lines flying off
        return seq(10, 85, i => ({ hl: i % 2, hr: 1 - i % 2, tick: true, prop: "code", f: i, lean: i > 2 && i < 8 ? 1 : 0 }))
    if (v < 0.88)       // a pause to think, then on
        return join([{ d: 460, eyes: "up", glance: -1 }, { d: 300, eyes: "up", glance: 1 }], seq(6, 115, i => ({ hl: i % 2, hr: 1 - i % 2, tick: i % 2 === 0 })))
    // the last line, and Enter
    return join(seq(4, 110, i => ({ hl: i % 2, hr: 1 - i % 2, tick: true })),
                [{ d: 220, hl: -1, hr: -1, sh: "t" }, { d: 110, hl: 1, hr: 1, sh: "d", tick: true, prop: "code", f: 1 },
                 { d: 110, prop: "code", f: 3, eyes: "joy" }, { d: 320, prop: "code", f: 5, eyes: "joy" }])
}
ACTS.think = t => {
    const v = chance(t, 52)
    if (v < 0.6) return seq(7, 120, i => ({ prop: "spark", f: [0, 1, 2, 3, 4, 5, 4][i] }))
    if (v < 0.82)       // turning it over
        return [{ d: 400, prop: "spark", f: 2, eyes: "up", glance: -1 }, { d: 300, prop: "spark", f: 3, eyes: "up", glance: -1, lean: -1 },
                { d: 400, prop: "spark", f: 4, eyes: "up", glance: 1 }, { d: 300, prop: "spark", f: 5, eyes: "up", glance: 1, lean: 1 }, { d: 200, prop: "spark", f: 4 }]
    return [{ d: 300, prop: "spark", f: 5, eyes: "sleep", lean: -1 }, { d: 300, prop: "spark", f: 4, eyes: "sleep", lean: -1 },
            { d: 300, prop: "spark", f: 5, eyes: "sleep" }, { d: 140, prop: "spark", f: 4, eyes: "wide", sh: "t" }, { d: 260, prop: "spark", f: 5, eyes: "shine" }]
}
ACTS.hammer = t => {
    const v = chance(t, 53), hit = [{ d: 130, armR: 2, f: 2 }, { d: 80, armR: 0, f: 1, sh: "d" }, { d: 110, armR: 1, f: 0 }]
    if (v < 0.6) return join(hit, hit, [{ d: 130, armR: 2, f: 2 }, { d: 90, armR: 0, f: 1, sh: "d" }, { d: 180, armR: 1, f: 0 }])
    if (v < 0.85)       // two hits and a wipe of the brow
        return join(hit, hit, [{ d: 260, armR: 1, f: 0, armL: 3, eyeL: "hidden", eyeR: "half" }, { d: 300, armR: 1, f: 0, eyes: "half", mouth: "o" }])
    return [{ d: 160, armR: 1, f: 0 }, { d: 320, sh: "t", armR: 2, f: 2, eyes: "squint" }, { d: 90, sh: "c", armR: 0, f: 3, dx: 1, dust: 1 },
            { d: 130, armR: 0, f: 3 }, { d: 160, armR: 1, f: 0, eyes: "joy" }, { d: 300, armR: 1, f: 0, eyes: "joy" }]
}
ACTS.scan = t => {
    const v = chance(t, 54)
    if (v < 0.6) return seq(8, 170, i => ({ f: [0, 1, 2, 3, 2, 1, 0, 0][i] }))
    if (v < 0.85)       // on to the next page
        return [{ d: 170, f: 1 }, { d: 170, f: 3 }, { d: 140, f: 3, page: 1, armL: 5 }, { d: 140, f: 0, page: 2 }, { d: 170, f: 0 }, { d: 170, f: 1 }, { d: 170, f: 2 }]
    return [{ d: 170, f: 1 }, { d: 170, f: 2 }, { d: 420, f: 2, eyes: "wide", sh: "t" }, { d: 300, f: 2, eyes: "shine", prop: "bang" }, { d: 170, f: 1 }, { d: 170, f: 0 }]
}
ACTS.surf = t => {
    const v = chance(t, 55)
    if (v < 0.6) return seq(8, 150, i => ({ f: i % 4 }))
    if (v < 0.85) return seq(9, 110, i => ({ f: i, ping: true, eyes: i > 5 ? "up" : undefined, glance: 1 }))
    return join(seq(6, 100, i => ({ f: i, toss: [1, 3, 4, 4, 3, 1][i], armR: i < 1 || i > 4 ? 2 : 1, eyes: "up", glance: 1 })), [{ d: 260, f: 2, eyes: "joy" }])
}
// subagents: balls in the air, or the little ones themselves
ACTS.delegate = t => {
    if (chance(t, 56) < 0.55) return seq(14, 105, i => ({ armL: i % 2 ? 1 : 0, armR: i % 2 ? 0 : 1, eyes: "up", f: i }))
    return join([{ d: 110, bare: true, prop: "mini", pop: 1 }, { d: 110, bare: true, prop: "mini", pop: 2 }],
                seq(9, 130, i => ({ bare: true, prop: "mini", f: i, armL: i % 4 === 1 ? 2 : 1, armR: i % 4 === 3 ? 2 : 1,
                                    glance: i % 7 < 4 ? -1 : 1, eyes: i === 8 ? "joy" : undefined })),
                [{ d: 110, bare: true, prop: "mini", pop: 2 }, { d: 110, bare: true, prop: "mini", pop: 1 }])
}
ACTS.sweep = t => {
    if (chance(t, 57) < 0.7) return seq(8, 130, i => ({ f: i % 4 }))
    return join(seq(6, 130, i => ({ f: i % 4, pile: i >> 1 })), [{ d: 140, f: 0, pile: 3 }, { d: 420, f: 0, pile: 3, eyes: "joy", prop: "sparkle" }])
}
ACTS.ask = [{ d: 110, sh: "t", f: 1 }, { d: 110, f: 1 }, { d: 160 }]
ACTS.hail = join([{ d: 100, sh: "c" }], seq(6, 150, i => ({ armR: i % 2 ? 6 : 2, armL: i % 2 ? 2 : 6, eyes: "wide", f: i % 2, sh: i % 2 ? "n" : "t" })))    // over here!
ACTS.wait = t => chance(t, 58) < 0.7 ? seq(8, 260, i => ({ f: i % 4 }))
                                     : join(seq(4, 260, i => ({ f: i })), seq(6, 170, i => ({ f: 3, legs: i % 2 ? "r" : undefined, glance: 1, eyes: i > 3 ? "up" : undefined })))
ACTS.done = join([{ d: 90, sh: "c", prop: "check", f: 0, eyes: "joy" }, { d: 60, sh: "s", dy: -1, prop: "check", f: 0, eyes: "joy" },
                  { d: 110, dy: -3, legs: "tuck", prop: "check", f: 1, eyes: "joy", armL: 2, armR: 2 }, { d: 60, sh: "s", dy: -1, prop: "check", f: 2, eyes: "joy", armL: 2, armR: 2 },
                  { d: 100, sh: "c", prop: "check", f: 2, eyes: "joy", armL: 2, armR: 2, dust: 1 }],
                 seq(5, 150, i => ({ prop: "check", f: 2, eyes: "joy", armL: 2, armR: 2, prop2: "burst", hue: 3, b: i + 1, cx: 10, cy: -3 })),
                 [{ d: 240, eyes: "joy", blush: true, mouth: "smile" }])
ACTS.cheer = t => chance(t, 59) < 0.6 ? seq(4, 180, i => ({ armL: (i + 1) % 2 ? 2 : 0, armR: (i + 1) % 2 ? 2 : 0, eyes: "joy", tw: true, sh: i % 2 ? "n" : "t" }))
                                      : join(hop(2, { eyes: "joy", armL: 2, armR: 2 }), [{ d: 300, eyes: "joy", armL: 5, armR: 5, tw: true }])
ACTS.snore = [{ d: 10, zz: true }]
// what the last answer was about: how it comes on, then its little loop
ACTS.proud = [{ d: 520, eyes: "joy" }, { d: 120 }]
ACTS.fixed = [{ d: 120, armR: 2, w: 1, norest: true }, { d: 120, armR: 1, norest: true }, { d: 120, armR: 2, w: 1, norest: true },
              { d: 120, armR: 1, norest: true }, { d: 90, sh: "c", eyes: "joy", f: 0 }, { d: 110, sh: "s", dy: -2, eyes: "joy", f: 1, legs: "tuck" },
              { d: 100, sh: "c", eyes: "joy", f: 2, dust: 1 }, { d: 800, eyes: "joy", f: 2, blush: true }, { d: 200 }]
ACTS.tighten = [{ d: 140, armR: 2, w: 1 }, { d: 140, armR: 1 }, { d: 140, armR: 2, w: 1 }, { d: 200, armR: 1, eyes: "joy" }]
ACTS.eureka = [{ d: 180, eyes: "up", f: 0 }, { d: 110, sh: "c", eyes: "wide", f: 1 }, { d: 110, sh: "s", dy: -1, eyes: "star", f: 2, armR: 2 },
               { d: 700, eyes: "star", f: 2, armR: 2 }, { d: 220, eyes: "joy" }]
ACTS.glow = [{ d: 260, f: 2 }, { d: 220 }, { d: 260, f: 2 }, { d: 160 }]
ACTS.oops = [{ d: 140, eyes: "wide", mouth: "o", f: 0 }, { d: 420, eyes: "wide", f: 0, armL: 1, armR: 1, prop2: "scribble" },
             { d: 300, eyes: "flat", f: 1, armL: 1, armR: 1, prop2: "scribble", lean: -1 }, { d: 300, eyes: "flat", f: 1, prop2: "scribble" }, { d: 200 }]
ACTS.shrug = [{ d: 300, armL: 1, armR: 1 }, { d: 420, armL: 6, armR: 6, glance: -1, f: 1, sh: "d" }, { d: 200 }]
ACTS.hello = seq(6, 170, i => ({ armR: i % 2 ? 6 : 2, eyes: "joy", prop: "speech", f: i > 2 ? 1 : 0, norest: true }))

// ---- off duty: each hobby's burst ----
ACTS.read = t => {
    const v = chance(t, 11)
    if (v < 0.3)        // a page turns
        return [{ d: 150, f: 1, eyes: "down", glance: 1 }, { d: 110, f: 2, eyes: "down" }, { d: 150, f: 3, eyes: "down", glance: -1 }, { d: 300, eyes: "joy" }]
    if (v < 0.52) {     // the story comes off the page
        const n = Math.floor(chance(t, 16) * 6)
        return [{ d: 170, prop: "tale", tale: n, g: 0, eyes: "wide" }, { d: 190, prop: "tale", tale: n, g: 1, eyes: "up", glance: 1 },
                { d: 460, prop: "tale", tale: n, g: 2, f: 0, eyes: "shine" }, { d: 420, prop: "tale", tale: n, g: 2, f: 1, eyes: "shine" },
                { d: 190, prop: "tale", tale: n, g: 1, eyes: "joy" }, { d: 140, eyes: "joy" }]
    }
    return seq(6, 400, i => ({ eyes: "down", glance: [-1, 0, 1][i % 3], lean: i === 5 ? 1 : 0 }))      // along the lines
}
ACTS.play = t => {
    const v = chance(t, 12)
    const run = seq(10, 110, i => ({ hl: i % 2, hr: 1 - i % 2, f: i, eyes: "down", lean: i === 4 || i === 5 ? -1 : i === 7 || i === 8 ? 1 : 0 }))
    if (v < 0.3) return join(run, [{ d: 480, eyes: "joy", won: true, prop: "sparkle", f: 0 }, { d: 200, eyes: "joy", won: true, prop: "sparkle", f: 1 }])
    if (v < 0.45) return join(run, [{ d: 520, eyes: "flat", lost: true }, { d: 300, eyes: "half", lost: true, mouth: "line" }])
    return run
}
ACTS.groove = t => {
    const v = chance(t, 19)
    if (v < 0.45) return seq(8, 170, i => ({ sh: i % 2 ? "n" : "d", eyes: i % 4 === 2 ? "joy" : undefined, prop: "note", f: i }))
    if (v < 0.8) return seq(8, 190, i => ({ lean: [-1, 0, 1, 0][i % 4], legs: i % 2 ? "r" : undefined, eyes: "joy", prop: "note", duet: i > 3, f: i }))
    return join(seq(6, 140, i => ({ sh: i % 2 ? "n" : "c", eyes: "joy", prop: "note", duet: true, f: i })),      // the good part
                [{ d: 300, sh: "t", armL: 2, armR: 2, eyes: "joy", prop: "note", duet: true, f: 2 }])
}
ACTS.paint = (t, e) => e.prog >= 7
    ? [{ d: 300, glance: 1, lean: -1 }, { d: 600, eyes: "shine", lean: -1, prop: "sparkle", f: 1 }, { d: 300, eyes: "joy", armL: 2 },
       { d: 200, eyes: "joy" }, { d: 140, set: 0 }]                                                    // admired, then a fresh canvas
    : [{ d: 150, armR: 2, glance: 1 }, { d: 120, armR: 1, glance: 1 }, { d: 150, armR: 2, glance: 1, mouth: "tongue" },
       { d: 160, armR: 1, glance: 1, adv: 1, mouth: "tongue" }, { d: 260, glance: 1, lean: -1 }]
ACTS.blow = t => chance(t, 20) < 0.72
    ? join([{ d: 200, sh: "t", eyes: "half" }], seq(10, 150, i => ({ mouth: i < 3 ? "o" : undefined, prop: "bubble", f: i, eyes: i > 4 ? "up" : undefined, glance: 1 })))
    : join([{ d: 260, sh: "t", eyes: "half" }], seq(9, 170, i => ({ mouth: i < 4 ? "o" : undefined, prop: "bubble", big: true, f: i,
                                                                    eyes: i < 2 ? undefined : i < 7 ? "wide" : "blink", glance: 1 })))
ACTS.yoyo = t => {
    const v = chance(t, 22)
    if (v < 0.55) return seq(10, 90, i => ({ f: [0, 1, 2, 3, 4, 4, 3, 2, 1, 0][i], armR: i === 0 || i === 9 ? 2 : 1 }))
    if (v < 0.8)        // walking the dog
        return join(seq(4, 90, i => ({ f: i + 1 })), seq(5, 120, i => ({ dog: [0, 2, 4, 2, 0][i], glance: 1 })), seq(3, 90, i => ({ f: 3 - i })), [{ d: 260, eyes: "joy" }])
    return join(seq(9, 85, i => ({ orbit: i, armR: 2, eyes: "up" })), [{ d: 300, eyes: "joy", armR: 2 }])      // around the world
}
ACTS.water = (t, e) => e.prog >= 3
    ? [{ d: 300, glance: 1, lean: 1 }, { d: 600, glance: 1, lean: 1, eyes: "joy", blush: true }, { d: 300, eyes: "joy", prop: "heart", f: 1 }, { d: 200, eyes: "joy" }]
    : join([{ d: 220, armR: 1, prop: "can", f: 0 }], seq(6, 160, i => ({ armR: 1, prop: "can", f: 1 + i % 3, glance: 1 })),
           [{ d: 220, adv: e.grow ? 1 : 0, glance: 1, eyes: e.grow ? "wide" : undefined }, { d: 320, eyes: "joy" }])
ACTS.stack = (t, e) => e.prog >= 4
    ? [{ d: 200, eyes: "wide", glance: 1 }, { d: 120, f: 1, eyes: "wide" }, { d: 120, f: 2, eyes: "wide" }, { d: 100, f: 3, sh: "s", dy: -1, eyes: "wide", mouth: "o" },
       { d: 110, f: 3, sh: "c", eyes: "wide", dust: 1 }, { d: 480, f: 3, eyes: "joy" }, { d: 110, f: 3, set: 0 }]      // it all comes down
    : [{ d: 180, armR: 1 }, { d: 170, armR: 2, sh: e.prog >= 2 ? "t" : "n", mouth: "tongue" }, { d: 220, armR: 1, adv: 1, mouth: "tongue" }, { d: 240, eyes: "joy" }]
ACTS.gaze = t => {
    const v = chance(t, 14)
    if (v < 0.3) return join(seq(7, 120, i => ({ eyeL: "sleep", prop: "shoot", f: i })), [{ d: 520, eyes: "star" }])
    if (v < 0.55) return join(seq(9, 190, i => ({ eyeL: "sleep", prop: "constel", sky: t % 3, f: i })), [{ d: 500, eyes: "shine", prop: "constel", sky: t % 3, f: 9 }])
    if (v < 0.68) return join(seq(10, 140, i => ({ eyeL: "sleep", prop: "ufo", sky: t % 2, f: i })), [{ d: 500, eyes: "wide" }])
    return [{ d: 1000, eyeL: "sleep" }, { d: 300, eyeL: "sleep", lean: 1 }, { d: 200 }]
}
ACTS.sip = t => {
    const v = chance(t, 23)
    const sip = [{ d: 200, armR: 1, prop: "cup", f: 0 }, { d: 700, armR: 2, prop: "cup", f: 1, eyes: "sleep" }, { d: 200, armR: 1, prop: "cup", f: 0 }, { d: 320, eyes: "joy" }]
    if (v < 0.55) return sip
    if (v < 0.8) return join([{ d: 220, mouth: "o", glance: 1 }, { d: 180, mouth: "o", glance: 1, blow: 1 }, { d: 180, mouth: "o", glance: 1, blow: 2 }, { d: 200, glance: 1 }], sip)
    return [{ d: 260, cookie: true, glance: 1 }, { d: 240, cookie: true, armR: 1, glance: 1 }, { d: 260, mouth: "chew", eyes: "joy" }, { d: 180, mouth: "line", eyes: "joy" },
            { d: 260, mouth: "chew", eyes: "joy" }, { d: 260, eyes: "joy", blush: true }]
}
ACTS.knit = (t, e) => e.prog >= 5
    ? [{ d: 300, eyes: "shine" }, { d: 200, bare: true, scarf: true, armL: 6, armR: 6, eyes: "joy" },
       { d: 600, bare: true, scarf: true, armL: 2, armR: 2, eyes: "joy", prop: "sparkle", f: 0 },
       { d: 300, bare: true, scarf: true, armL: 1, armR: 1, eyes: "joy", prop: "sparkle", f: 1 }, { d: 140, set: 0 }]      // tries it on
    : join(seq(8, 130, i => ({ f: i % 2, eyes: "down" })), [{ d: 200, f: 0, adv: 1, eyes: "down" }, { d: 300, eyes: "joy" }])
ACTS.fish = t => {
    const v = chance(t, 17)
    if (v < 0.4) return [{ d: 500, bob: 1, glance: 1 }, { d: 500, glance: 1 }, { d: 500, bob: 1, glance: 1, ripple: 1 }, { d: 300, glance: 1 }]
    if (v < 0.6)        // a nibble, and nothing
        return [{ d: 200, bob: 1, ripple: 1, eyes: "wide", glance: 1 }, { d: 160, eyes: "wide", glance: 1 }, { d: 200, bob: 1, ripple: 2, eyes: "wide", glance: 1 },
                { d: 500, eyes: "wide", glance: 1 }, { d: 400, eyes: "flat" }, { d: 200 }]
    const w = chance(t, 18), haul = w < 0.6 ? "fish" : w < 0.86 ? "boot" : "star"
    const look = haul === "boot" ? "flat" : haul === "star" ? "star" : "joy"
    return [{ d: 180, bob: 1, ripple: 1, eyes: "wide", glance: 1 }, { d: 120, bob: 1, ripple: 2, pull: 1, eyes: "wide", glance: 1 },
            { d: 110, sh: "t", pull: 1, land: 6, haul: haul, armR: 2, ripple: 2, eyes: "wide" }, { d: 110, pull: 1, land: 3, haul: haul, armR: 2, eyes: "wide" },
            { d: 480, land: 2, haul: haul, armR: 2, eyes: look }, { d: 300, land: 2, haul: haul, armR: 2, eyes: look, mouth: haul === "boot" ? "line" : "smile" },
            { d: 140, land: 5, haul: haul }, { d: 160, ripple: 1 }, { d: 160, ripple: 2 }]
}
ACTS.kite = t => chance(t, 24) < 0.72
    ? seq(8, 180, i => ({ f: i, armR: i % 2 ? 2 : 6, eyes: "up", glance: 1 }))
    : [{ d: 180, f: 0, eyes: "up", glance: 1 }, { d: 160, f: 1, dive: 1, eyes: "wide", glance: 1 }, { d: 160, f: 2, dive: 2, eyes: "wide", glance: 1, armR: 6 },
       { d: 140, f: 2, dive: 3, eyes: "wide", glance: 1, armR: 1, lean: -1 }, { d: 160, f: 3, dive: 1, armR: 2, glance: 1 }, { d: 180, f: 4, eyes: "up", glance: 1 },
       { d: 320, f: 5, eyes: "joy" }]
ACTS.strum = t => join(seq(8, 150, i => ({ hr: i % 2, prop: "note", f: i, legs: i % 2 ? "r" : undefined, eyes: i % 4 === 2 ? "joy" : "down" })),
                       chance(t, 25) < 0.35 ? [{ d: 160, hr: 1, lean: -1 }, { d: 480, eyes: "joy", lean: -1, prop: "note", duet: true, f: 2 }] : [])
ACTS.slurp = t => chance(t, 26) < 0.72
    ? [{ d: 220, f: 1, mouth: "o" }, { d: 170, f: 2, mouth: "o", eyes: "joy" }, { d: 200, mouth: "chew", eyes: "joy" }, { d: 160, mouth: "line", eyes: "joy" },
       { d: 200, mouth: "chew", eyes: "joy" }, { d: 260, eyes: "joy", blush: true }]
    : [{ d: 200, eyes: "down" }, { d: 700, drink: true, eyes: "hidden", armL: 4, armR: 4, lean: -1 }, { d: 160, eyes: "blink" },
       { d: 420, eyes: "joy", blush: true, mouth: "smile" }]                                            // the broth, straight from the bowl
ACTS.fold = (t, e) => e.prog >= 3
    ? join([{ d: 400, eyes: "shine" }], seq(7, 130, i => ({ gone: true, prop: "crane", f: i, eyes: "up", glance: 1, armR: i > 2 ? 2 : 1 })),
           [{ d: 300, gone: true, armR: 6, eyes: "joy" }, { d: 140, set: 0 }])                           // and off it flies
    : [{ d: 160, hl: 1, crease: true, eyes: "down" }, { d: 140, hr: 1, eyes: "down" }, { d: 160, hl: 1, eyes: "down" }, { d: 200, adv: 1, eyes: "wide" }, { d: 260, eyes: "joy" }]
ACTS.twist = t => join(seq(6, 140, i => ({ f: i + 1, hl: i % 2, hr: 1 - i % 2, eyes: "down" })),
                       chance(t, 27) < 0.22 ? [{ d: 160, solved: true, eyes: "wide" }, { d: 560, solved: true, eyes: "star", prop: "sparkle", f: 0 },
                                               { d: 260, solved: true, eyes: "joy", prop: "sparkle", f: 1, adv: 1 }]
                                            : [{ d: 420, f: 6, eyes: "half", lean: 1 }, { d: 120, adv: 1 }])
ACTS.skate = t => {
    const v = chance(t, 28)
    if (v < 0.5)        // a roll out and back
        return [0, 1, 2, 3, 3, 2, 1, 0, -1, -2, -2, -1, 0].map((x, i, p) => {
            const dir = i ? Math.sign(x - p[i - 1]) : 1
            return { d: 120, dx: x, lean: dir, speed: dir, armL: 5, armR: 5 }
        })
    if (v < 0.82)       // an ollie
        return [{ d: 120, sh: "c" }, { d: 70, sh: "s", dy: -1 }, { d: 80, dy: -3, by: 2, legs: "tuck" }, { d: 140, dy: -4, by: 3, legs: "tuck", eyes: "joy", armL: 5, armR: 5 },
                { d: 80, dy: -3, by: 2, legs: "tuck" }, { d: 70, sh: "s", dy: -1 }, { d: 110, sh: "c", dust: 1 }, { d: 240, eyes: "joy" }]
    return join(seq(6, 130, i => ({ lean: i % 2 ? 1 : -1, dx: i % 2 ? 1 : -1, eyes: "wide", armL: i % 2 ? 2 : 5, armR: i % 2 ? 5 : 2 })),      // a wobble
                [{ d: 300, eyes: "half", mouth: "o" }, { d: 200 }])
}
ACTS.roast = (t, e) => e.prog >= 3
    ? [{ d: 240, bite: 1, mouth: "o" }, { d: 240, bite: 2, mouth: "chew", eyes: "joy" }, { d: 180, bite: 2, mouth: "line", eyes: "joy" },
       { d: 240, bite: 2, mouth: "chew", eyes: "joy" }, { d: 300, eyes: "joy", blush: true, set: 0 }]
    : e.prog === 2 && chance(t, 29) < 0.3
    ? [{ d: 200, f: 1, burnt: true, eyes: "wide" }, { d: 170, burnt: true, mouth: "o", eyes: "wide" }, { d: 170, f: 1, mouth: "o" }, { d: 300, eyes: "flat", adv: 1 }]
    : [{ d: 220, f: 1, glance: 1 }, { d: 220, f: 0, glance: 1 }, { d: 220, f: 1, glance: 1 }, { d: 220, f: 0, glance: 1 }, { d: 240, f: 1, adv: 1, eyes: "joy" }]
ACTS.yoga = (t, e) => [
    [{ d: 260, armL: 1, armR: 1 }, { d: 240, sh: "t", armL: 6, armR: 6 }, { d: 900, sh: "t", armL: 2, armR: 2, eyes: "joy" }, { d: 260, armL: 1, armR: 1, adv: 1 }],
    [{ d: 260, armR: 2 }, { d: 900, armR: 2, lean: -1, eyes: "joy" }, { d: 260, armL: 2 }, { d: 900, armL: 2, lean: 1, eyes: "joy" }, { d: 240, adv: 1 }],
    [{ d: 300, sh: "d", armL: 5, armR: 5 }, { d: 800, sh: "c", armL: 5, armR: 5, eyes: "joy" }, { d: 300, sh: "d", armL: 5, armR: 5 }, { d: 240, adv: 1 }],
    [{ d: 400, sh: "t", armL: 5, armR: 5, eyes: "joy" }, { d: 500, armL: 5, armR: 5, eyes: "joy", mouth: "o" }, { d: 400, sh: "t", armL: 5, armR: 5, eyes: "joy" },
     { d: 500, eyes: "joy", mouth: "o" }, { d: 200, set: 0 }]][e.prog % 4]
ACTS.lift = (t, e) => join(
    [{ d: 200, sh: "c", armL: -1, armR: -1 }, { d: 160, bar: 1, armL: 4, armR: 4, eyes: "squint" },
     { d: 320, bar: 1, armL: 4, armR: 4, eyes: "squint", mouth: "line", blush: true }, { d: 140, sh: "t", bar: 2, armL: 2, armR: 2, eyes: "squint" },
     { d: 700, sh: "t", bar: 2, armL: 2, armR: 2, eyes: "joy", prop: "sparkle", f: 0 }, { d: 150, bar: 1, armL: 4, armR: 4 },
     { d: 140, sh: "c", dust: 1, set: (e.prog + 1) % 3 }],
    e.prog % 3 === 2 ? [{ d: 160, armL: 6, armR: 6 }, { d: 500, sh: "t", armL: 2, armR: 2, eyes: "joy", prop: "sparkle", f: 1 }, { d: 160 }]
                     : [{ d: 320, eyes: "half", mouth: "o" }])
ACTS.toss = t => {
    const wind = [{ d: 220, armR: -1, lean: -1 }, { d: 110, armR: 2, lean: 1, thrown: true, prop: "glide", f: 0 }]
    const look = [1, 1, 1, 1, 0, 0, -1, -1, -1, -1, 0]
    if (chance(t, 30) < 0.72)
        return join(wind, seq(11, 110, i => ({ thrown: true, prop: "glide", f: i + 1, glance: look[i], eyes: i > 1 && i < 8 ? "up" : undefined, armR: i > 8 ? 1 : 0 })),
                    [{ d: 300, eyes: "joy" }])
    return join(wind, seq(6, 110, i => ({ thrown: true, prop: "glide", f: i + 1, glance: look[i], eyes: i > 1 ? "up" : undefined })),      // it comes down on its head
                [{ d: 110, thrown: true, prop: "glide", bonk: 1, eyes: "up" }, { d: 110, sh: "d", thrown: true, prop: "glide", bonk: 2, eyes: "squint" },
                 { d: 420, thrown: true, prop: "glide", bonk: 2, eyes: "flat" }, { d: 200, armR: 2, eyes: "half" }])
}
ACTS.skip = t => {
    const jump = [{ d: 90, f: 1, sh: "d" }, { d: 80, f: 2, sh: "s", dy: -1 }, { d: 110, f: 3, dy: -2, legs: "tuck" }, { d: 90, f: 4, sh: "c" }]
    if (chance(t, 31) < 0.8) return join(jump, jump, jump, [{ d: 260, f: 1, eyes: "joy" }])
    return join(jump, [{ d: 90, f: 1, sh: "d" }, { d: 80, f: 2, sh: "s", dy: -1 }, { d: 120, tangle: true, sh: "c", eyes: "wide" },      // caught in it
                       { d: 520, tangle: true, eyes: "flat" }, { d: 140, tangle: true, dx: 1 }, { d: 140, tangle: true, dx: -1 }, { d: 200, f: 0 }])
}
ACTS.pet = (t, e) => {
    if (e.prog >= 3 && !e.hat) return chance(t, 32) < 0.5      // the cat's asleep on its head
        ? [{ d: 500, eyes: "up" }, { d: 600, eyes: "joy", blush: true }, { d: 200 }]
        : [{ d: 300, eyes: "up" }, { d: 300, eyes: "up", armL: 2 }, { d: 500, eyes: "joy", armL: 2, prop: "heart", f: 1 }, { d: 200, armL: 1 }]
    const up = e.k % 2 === 1 && e.prog < 3
    return join([{ d: 220, armR: 5, glance: 1 }, { d: 220, armR: 5, purr: true, glance: 1, eyes: "joy" }, { d: 220, armR: 1, purr: true, glance: 1, eyes: "joy" },
                 { d: 220, armR: 5, purr: true, glance: 1, eyes: "joy", prop: "heart", f: 1 }, { d: 260, purr: true, eyes: "joy", prop: "heart", f: 3 }],
                up && e.prog === 2 && !e.hat ? [{ d: 110, catUp: 2, eyes: "wide", glance: 1 }, { d: 110, catUp: 5, eyes: "up" }, { d: 300, eyes: "up", adv: 1 }]
                                             : [{ d: 120, adv: up ? 1 : 0 }])
}
ACTS.cook = (t, e) => {
    if (e.prog >= 4) return join(seq(4, 300, i => ({ nocake: true, eaten: i + 1, mouth: i % 2 ? "line" : "chew", eyes: "joy", glance: -1 })),
                                 [{ d: 300, nocake: true, eaten: 4, eyes: "joy", blush: true, set: 0 }])
    const up = seq(5, 100, i => ({ f: i + 1, eyes: i > 1 ? "up" : undefined, glance: 1, armR: i === 0 ? 1 : 0 }))
    if (chance(t, 33) < 0.2)        // lands on its head
        return join(up, [{ d: 140, nocake: true, onHead: true, sh: "d", eyes: "up" }, { d: 520, nocake: true, onHead: true, eyes: "flat" },
                         { d: 200, nocake: true, onHead: true, armL: 2, eyes: "flat" }, { d: 200, nocake: true, adv: 1, armL: 1, glance: -1 }])
    return join(up, [{ d: 100, f: 6, glance: 1 }, { d: 110, f: 7, sh: "d", glance: 1 }, { d: 200, nocake: true, adv: 1, glance: -1 }, { d: 280, eyes: "joy" }])
}
ACTS.snow = (t, e) => e.prog >= 4
    ? e.k % 9 === 8 ? [{ d: 300, glance: 1 }, { d: 500, glance: 1, eyes: "joy", armR: 2, hello: 1 }, { d: 200, prop: "poof", g: 1 }, { d: 140, prop: "poof", g: 2, set: 0 }]
                    : [{ d: 300, glance: 1 }, { d: 300, glance: 1, hello: 1, armR: 2, eyes: "joy" }, { d: 300, glance: 1, armR: 6, eyes: "joy" },
                       { d: 300, glance: 1, hello: 1, armR: 2, eyes: "joy" }, { d: 200 }]
    : [{ d: 200, armR: 1, roll: 1, glance: 1 }, { d: 200, armR: 0, glance: 1 }, { d: 200, armR: 1, roll: 1, glance: 1 }, { d: 220, adv: 1, glance: 1 }, { d: 300, eyes: "joy" }]
ACTS.carve = (t, e) => e.prog >= 3
    ? e.k % 6 === 5 ? [{ d: 400, glance: 1, eyes: "shine" }, { d: 200, prop: "poof", g: 1 }, { d: 140, prop: "poof", g: 2, set: 0 }]
                    : join(seq(8, 140, i => ({ prop: "bat", f: i + 1, glance: i < 4 ? -1 : 1, eyes: i === 3 ? "wide" : undefined })), [{ d: 300, glance: 1, eyes: "joy" }])
    : [{ d: 160, armR: 1, glance: 1 }, { d: 140, armR: 0, glance: 1 }, { d: 160, armR: 1, glance: 1, mouth: "tongue" }, { d: 200, adv: 1, glance: 1 },
       { d: 320, eyes: e.prog === 2 ? "star" : "joy" }]
ACTS.trim = (t, e) => e.prog >= 5
    ? e.k % 8 === 7 ? [{ d: 500, glance: 1, eyes: "shine", tw: true }, { d: 200, prop: "poof", g: 1 }, { d: 140, prop: "poof", g: 2, set: 0 }]
                    : seq(5, 300, i => ({ glance: 1, eyes: i % 2 ? "shine" : "joy", tw: true }))
    : e.prog === 4 ? [{ d: 200, armR: 1, glance: 1 }, { d: 200, sh: "t", armR: 2, glance: 1, eyes: "up" }, { d: 220, sh: "t", armR: 2, adv: 1, eyes: "up" },
                      { d: 500, eyes: "star", prop: "sparkle", f: 1 }]
                   : [{ d: 180, armR: 1, glance: 1 }, { d: 180, armR: e.prog < 2 ? 6 : 1, glance: 1, mouth: "tongue" }, { d: 220, armR: 1, adv: 1, glance: 1 }, { d: 280, eyes: "joy" }]
ACTS.fizz = t => chance(t, 34) < 0.55
    ? seq(8, 140, i => ({ f: i, eyes: i % 3 === 1 ? "shine" : undefined, glance: 1, armR: i % 4 === 2 ? 6 : 1 }))
    : join(seq(7, 130, i => ({ f: i, prop: "firework", hue: t, glance: i < 3 ? -1 : 0, eyes: i > 2 ? "up" : undefined })), [{ d: 320, eyes: "star" }])
ACTS.splash = t => {
    const v = chance(t, 35)
    if (v < 0.4) return seq(6, 130, i => ({ eyes: i > 1 && i < 5 ? "up" : undefined }))             // watching it come down
    if (v < 0.7) return seq(8, 110, i => ({ twirl: i + 1, lean: [0, 1, 0, -1][i % 4], eyes: "joy" }))
    return join(walk(0, -3, 130, {}), [{ d: 90, dx: -3, sh: "c" }, { d: 70, dx: -3, sh: "s", dy: -1 }, { d: 120, dx: -3, dy: -3, legs: "tuck", eyes: "joy" },
                                       { d: 70, dx: -3, sh: "s", dy: -1 }, { d: 110, dx: -3, sh: "c", splash: 1, eyes: "joy" }, { d: 140, dx: -3, splash: 2, eyes: "joy" }],
                walk(-3, 0, 130, {}))
}

// ---- now and then ----
ACTS.look = t => { const g = chance(t, 15) < 0.5 ? -1 : 1; return [{ d: 260, glance: g }, { d: 1100, glance: g, lean: g }, { d: 220, glance: g }] }
ACTS.stretch = [{ d: 200, armL: 1, armR: 1 }, { d: 180, sh: "t", armL: 6, armR: 6, eyes: "half" }, { d: 700, sh: "t", armL: 2, armR: 2, eyes: "joy" },
                { d: 180, armL: 6, armR: 6 }, { d: 160, armL: 1, armR: 1 }]
ACTS.whistle = seq(7, 190, i => ({ mouth: "o", eyes: "joy", prop: "note", f: i, lean: [0, 0, 1, 1, 0, 0, -1][i] }))
ACTS.stargaze = seq(4, 420, i => ({ eyes: "up", glance: 1, tw: true }))
ACTS.butterfly = seq(12, 150, i => ({ prop: "fly", f: i, glance: i < 4 ? -1 : i > 7 ? 1 : 0, eyes: i >= 4 && i <= 6 ? "up" : i === 7 ? "joy" : undefined }))
ACTS.bat = seq(10, 130, i => ({ prop: "bat", f: i, glance: i < 5 ? -1 : 1, eyes: i === 4 ? "wide" : undefined }))
ACTS.tap = seq(8, 150, i => ({ legs: i % 2 ? "r" : undefined, glance: 1 }))
ACTS.sway = [{ d: 300, lean: -1 }, { d: 300 }, { d: 300, lean: 1 }, { d: 300 }, { d: 300, lean: -1, eyes: "joy" }, { d: 300, eyes: "joy" }, { d: 300, lean: 1, eyes: "joy" }, { d: 200 }]
ACTS.pace = () => join(walk(0, -3, 140, { glance: -1 }), [{ d: 520, dx: -3, glance: -1, eyes: "up" }], walk(-3, 0, 140, { glance: 1 }))
ACTS.bird = seq(13, 150, i => ({ prop: "bird", f: i, glance: i < 4 ? -1 : i > 9 ? 1 : 0, eyes: i >= 4 && i <= 8 ? "up" : undefined, prop2: i === 7 || i === 8 ? "note" : undefined }))
ACTS.leaf = seq(13, 150, i => ({ prop: "leaf", f: i, eyes: i < 6 ? "up" : i < 9 ? "up" : undefined, glance: i < 6 ? 1 : 0, dx: i === 8 ? 1 : i === 9 ? -1 : 0 }))
ACTS.petal = seq(10, 170, i => ({ prop: "petal", f: i, glance: i < 5 ? 1 : -1, eyes: i > 6 ? "joy" : undefined }))
ACTS.firefly = seq(10, 170, i => ({ prop: "firefly", f: i, glance: i < 4 ? 1 : i < 7 ? 0 : -1, eyes: i > 2 && i < 7 ? "up" : undefined }))
ACTS.flake = join(seq(7, 170, i => ({ prop: "flake", f: i, eyes: "up", mouth: i >= 3 ? "tongue" : undefined })),
                  [{ d: 400, eyes: "joy", mouth: "tongue" }, { d: 200, eyes: "joy" }])
ACTS.ghost = [{ d: 200, prop: "ghost", g: 0 }, { d: 200, prop: "ghost", g: 1 }, { d: 220, prop: "ghost", g: 2, glance: 1, eyes: "wide" },
              { d: 100, sh: "s", dy: -2, prop: "ghost", g: 3, eyes: "wide", mouth: "o", legs: "tuck" }, { d: 110, sh: "c", prop: "ghost", g: 3, eyes: "wide", dust: 1 },
              { d: 400, prop: "ghost", g: 2, eyes: "wide", glance: 1 }, { d: 300, prop: "ghost", g: 4, eyes: "flat", glance: 1 }, { d: 300, eyes: "flat" }]

// ---- one thing put away, the next brought out ----
ACTS.swap = (t, e) => {
    const out = [], hands = z => z === "front" ? { armL: 4, armR: 4 } : {}
    if (e.zoneFrom) out.push(Object.assign({ d: 80, hold: e.from, prop: "poof", g: 0, zone: e.zoneFrom }, hands(e.zoneFrom)),
                             { d: 90, bare: true, armL: 0, armR: 0, prop: "poof", g: 1, zone: e.zoneFrom })
    else out.push({ d: 90, bare: true, armL: 0, armR: 0 })
    if (e.zoneTo) out.push({ d: 90, bare: true, armL: 0, armR: 0, prop: "poof", g: 1, zone: e.zoneTo }, { d: 100, prop: "poof", g: 2, zone: e.zoneTo })
    out.push({ d: 160, eyes: "joy" })
    return out
}

// the frames of an act, for the beat (or the click) it's played on
function frames(name, seed, env) {
    const a = ACTS[name]
    if (!a) return null
    return typeof a === "function" ? a(seed | 0, env || {}) : a
}
function names() { return Object.keys(ACTS) }
function hobbies() { return Object.keys(HOBBIES) }
function hobby(name) { return HOBBIES[name] || null }
