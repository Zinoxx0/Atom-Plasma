.pragma library

// Clawd's art: every picture of it, as data and drawing code. Clawd.qml holds the creature's state and
// timing and hands a "scene" (its pose and everything around it) to compose(), which answers with a
// flat list of coloured cells; paint() puts that list on a Canvas. One list per frame, one item on
// screen: the art costs no QML objects, however many props there are.
//
// Everything is drawn in grid cells. The figure's box is 22 x 10 (the body at x 4..15, y 0..7, its
// feet on y 9); the canvas reaches X0..X0+COLS, Y0..Y0+ROWS around it for hats, props and visitors.
// On a bar there is room for about y -7..11 and x -6..25: anything meant to be seen there stays inside.
//
// Colours are named ("body", "hi", "ink", a palette key like "primary") and looked up in the view's
// inks at paint time, or literal ("#rrggbb"); an ink in a sprite can also be [colour, alpha].
//
// Four layers, drawn in this order (a prop can have a part in several):
//   BACK   stands on the ground behind Clawd and stays put when it hops (an easel, a campfire)
//   HELD   in its hands or on it: moves, flips and spins with the figure
//   OVER   floats over its head and follows it (a spark, a heart, a "?")
//   FRONT  stands or flies in front, on its own path (a butterfly, a paper plane, the dust of a landing)

var X0 = -8
var Y0 = -11
var COLS = 39
var ROWS = 23

// ---------- helpers ----------
// a number in [0, 1) from integers: the same in every view (as Acts.chance)
function rnd(a, b, c) {
    let h = Math.imul((a | 0) ^ 0x9e3779b9, 0x85ebca6b) ^ Math.imul(((b | 0) + 0x632be5ab) | 0, 0xc2b2ae35)
          ^ Math.imul(((c | 0) + 0x27d4eb2f) | 0, 0x165667b1)
    h ^= h >>> 16; h = Math.imul(h, 0x7feb352d); h ^= h >>> 15; h = Math.imul(h, 0x846ca68b); h ^= h >>> 16
    return (h >>> 0) / 4294967296
}
function at(list, i) { return list[Math.max(0, Math.min(list.length - 1, i))] }

// rows of characters -> runs [x, y, width, character, ...]
function sprite(rows) {
    const runs = []
    for (let y = 0; y < rows.length; y++) {
        const r = rows[y]
        let x = 0
        while (x < r.length) {
            const ch = r[x]
            if (ch === ".") { x++; continue }
            let w = 1
            while (x + w < r.length && r[x + w] === ch) w++
            runs.push(x, y, w, ch)
            x += w
        }
    }
    return runs
}

// the display list being made: [x, y, w, h, colour, alpha, ...], with the figure's transform
function Out() {
    this.l = []
    this.dx = 0; this.dy = 0        // moved by
    this.mir = false                // mirrored (about x 10)
    this.rot = 0                    // quarter turns clockwise (about 10, 5)
}
Out.prototype.r = function (x, y, w, h, c, a) {
    if (this.mir) x = 20 - x - w
    if (this.rot === 1) { const nx = 15 - y - h, ny = x - 5; x = nx; y = ny; const t = w; w = h; h = t }
    else if (this.rot === 2) { x = 20 - x - w; y = 10 - y - h }
    else if (this.rot === 3) { const nx = 5 + y, ny = 15 - x - w; x = nx; y = ny; const t = w; w = h; h = t }
    this.l.push(x + this.dx, y + this.dy, w, h, c, a === undefined ? 1 : a)
}
Out.prototype.p = function (x, y, c, a) { this.r(x, y, 1, 1, c, a) }
Out.prototype.pic = function (sp, x, y, inks, a) {
    for (let i = 0; i < sp.length; i += 4) {
        const k = inks[sp[i + 3]]
        if (k === undefined) continue
        if (typeof k === "string") this.r(x + sp[i], y + sp[i + 1], sp[i + 2], 1, k, a)
        else this.r(x + sp[i], y + sp[i + 1], sp[i + 2], 1, k[0], k[1] * (a === undefined ? 1 : a))
    }
}
Out.prototype.line = function (x0, y0, x1, y1, c, a) {
    const dx = Math.abs(x1 - x0), dy = Math.abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
    let e = dx - dy
    for (let n = 0; n < 96; n++) {          // (never longer than the canvas, whatever it's handed)
        this.r(x0, y0, 1, 1, c, a)
        if (x0 === x1 && y0 === y1) break
        const e2 = 2 * e
        if (e2 > -dy) { e -= dy; x0 += sx }
        if (e2 < dx) { e += dx; y0 += sy }
    }
}
Out.prototype.still = function () { this.dx = 0; this.dy = 0; this.mir = false; this.rot = 0 }

const STEEL = "#a3abbd", WOOD = "#8a5a3c", PAPER = "#ece6dc", GOLD = "#ffd166", GLOW = "#fff4cf"
const WATER = "#8ec5ff", SNOW = "#f4f7fb", FLAME = "#ff8a3d", GREY = "#5d6275"

// ---------- sprites ----------
const S = {
    mark: sprite(["..x.", "xxxx", ".x.."]),
    dizzy: sprite(["x.x", ".x.", "x.x"]),
    heartEye: sprite(["x.x", "xxx", ".x."]),
    plus: sprite([".x.", "xxx", ".x."]),
    smile: sprite(["x..x", ".xx."]),
    frown: sprite([".xx.", "x..x"]),
    tongue: sprite(["xx", ".p"]),
    witch: sprite(["........kk....", ".......kk.....", "......kkkk....", ".....kkkkkk...", "....oooooooo..", "kkkkkkkkkkkkkk"]),
    lens: sprite([".rr.", "rgsr", "rssr", ".rr.", "h..."]),
    broom: sprite(["h....", ".h...", ".h...", "..h..", "..h..", ".bbbb", "bbbbb"]),
    book: sprite([".pppp..pppp.", "cllllssllllc", "cppppssppppc", "cccccccccccc"]),
    game: sprite([".gggggg.", "dgssssgb", "dgssssgb", ".gggggg."]),
    easel: sprite(["wwwwwww", "wcccccw", "wcccccw", "wcccccw", "wcccccw", "wwwwwww", "..w.w..", "..w.w..", "..w.w..",
                   ".w...w.", ".w...w.", ".w...w.", ".w...w."]),
    wand: sprite(["xxx", "x.x", "xxx", ".x."]),
    ringBig: sprite([".xx.", "x..x", "x..x", ".xx."]),
    pot: sprite(["hhhh", ".rr.", ".rr."]),
    bloom: sprite([".p.", "pyp", ".p."]),
    can: sprite(["..b..", "bbbbs", "bbb.."]),
    scope: sprite([".....tt", "...ttt.", ".ttt...", "tt....."]),
    tripod: sprite(["..l..", "..l..", ".l.l.", ".l.l.", "l...l", "l...l", "l...l", "l...l"]),
    wrenchA: sprite(["..w.w", "..www", ".h...", "h...."]),
    wrenchB: sprite(["w.w..", "www..", "..h..", "...h."]),
    bulb: sprite([".yyy.", "yhyyy", "yyyyy", ".yyy.", ".ggg.", "..g.."]),
    drop: sprite([".d", "dd", "dd"]),
    cloud: sprite([".wwwww.", "wwwwwww", ".wwwww.", "w......"]),
    heart: sprite(["xx.xx", "xxxxx", ".xxx.", "..x.."]),
    heartS: sprite(["x.x", "xxx", ".x."]),
    note: sprite(["..xx", "..x.", "xxx.", "xx.."]),
    note2: sprite([".xxx", ".x.x", "xx.x", "xx.."]),
    bang: sprite(["xx", "xx", "xx", "..", "xx"]),
    ask: sprite(["xxx", "..x", ".xx", "...", ".x."]),
    check0: sprite(["....", "....", "x...", ".x.."]),
    check1: sprite(["....", "...x", "x.x.", ".x.."]),
    check2: sprite(["....x", "...x.", "x.x..", ".x..."]),
    puff0: sprite(["..", "xx"]),
    flyOpen: sprite(["x.x", "xxx", "x.x"]),
    flyShut: sprite([".x.", ".x.", ".x."]),
    batOpen: sprite(["x...x", "xxxxx", ".x.x."]),
    batShut: sprite(["..x..", ".xxx.", ".x.x."]),
    zed: sprite(["xxx", ".x.", "xxx"]),
    battery: sprite([".n.", "fff", "f.f", "fcf", "fff"]),
    batteryOut: sprite([".n.", "fff", "f.f", "f.f", "fff"]),
    arrow: sprite(["..x..", ".xxx.", "xxxxx", ".xxx.", ".xxx."]),
    // new this round
    yarn: sprite([".yy.", "yhyy", "yyyy", ".yy."]),
    fish: sprite(["x.xx.", "xxxex", "x.xx."]),
    boot: sprite(["xx.", "xx.", "xxx", "sss"]),
    kite: sprite(["..p..", ".ppt.", "ppctt", ".ptt.", "..t.."]),
    uke: sprite(["h......bbb.", "hnnnnnbbobb", ".......bbb."]),
    tri: sprite(["....x", "...xs", "..xss", ".xsss", "xxxxx"]),
    diamond: sprite([".x.", "xsx", "xsx", ".s."]),
    crane: sprite(["x.....x", "xx...xs", ".xxxss.", "..xss.."]),
    craneUp: sprite(["x.x...x", "xxx..xs", ".xxxss.", "..xss.."]),
    craneDown: sprite(["x......", "xx....x", ".xxxss.", "xxxsss."]),
    flameA: sprite([".y..", ".oy.", "yooy", "oyyo"]),
    flameB: sprite(["..y.", ".yo.", "yoyo", "oyyo"]),
    flameC: sprite([".y..", "yoo.", "oyoy", "oyyo"]),
    dart: sprite(["xx..", "sxxx"]),
    dartL: sprite(["..xx", "xxxs"]),
    dartUp: sprite([".x", "xx", "xs"]),
    dartDown: sprite(["xs", "xx", ".x"]),
    cat: sprite(["x.x...", "xxx...", "exe..t", "xxxx.t", "xxxxxt", "x.xx.."]),
    catPurr: sprite(["x.x...", "xxx...", "sxs...", "xxxx..", "xxxxtt", "x.xx.."]),
    catLoaf: sprite(["x.x...", "xxxx..", "exexxx", "xxxxxx"]),
    snowBase: sprite([".xxx.", "xxxxx", "sssss"]),
    pumpkin: sprite(["..gg..", ".oooo.", "ododoo", "oodooo", "ododoo", ".oooo."]),
    fir: sprite(["..g..", ".ggg.", ".ggg.", "ggggg", ".ggg.", "ggggg", "ggggg", "..t.."]),
    bird: sprite([".xx.", "xxxy", "xx.."]),
    birdUp: sprite(["x...", "xxx.", ".xxy"]),
    ghost: sprite([".xx.", "xxxx", "xexe", "xxxx", "x.xx"]),
    balloon: sprite([".xxxx.", "xxhxxx", "xhxxxx", "xxxxxx", ".xxxx.", "..xx.."]),
    chute: sprite(["..aabbaabb..", ".aabbaabbaa.", "aabbaabbaabb", "l....l.....l"]),
    jet: sprite([".yy.", "yooy", ".oo."]),
    jetB: sprite(["yooy", ".oy.", "..y."]),
    mic: sprite(["xxx", "xxx", ".h.", ".h."]),
    cone: sprite(["..x", ".xx", "xxy"]),
    scribbleA: sprite(["x.xx.", ".x..x", "xx.x."]),
    scribbleB: sprite([".xx.x", "x..x.", ".x.xx"]),
    L: sprite(["x..", "x..", "x..", "x..", "xxx"]),
    V: sprite(["x.x", "x.x", "x.x", "x.x", ".x."]),
    U: sprite(["x.x", "x.x", "x.x", "x.x", "xxx"]),
    P: sprite(["xxx", "x.x", "xxx", "x..", "x.."]),
    up: sprite([".x.", "xxx"]),
    castle: sprite(["x.x.x", "xxxxx", "xx.xx", "xx.xx"]),
    ship: sprite(["..s..", ".ss..", "xxxxx", ".xxx."]),
    fox: sprite(["o...o", "oo.oo", "oxoxo", ".owo."]),
    crown: sprite(["y.y.y", "yyryy", "yyyyy"]),
    moon: sprite([".yy", "y..", "y..", ".yy"]),
    ufo: sprite([".cc.", "xxxx", ".y.y"]),
    planet: sprite([".pp..", "rpprr", ".pp.."]),
    mini: sprite(["bbbbb", "bxbxb", "bbbbb", ".l.l."]),
    poofA: sprite([".xx.", "xxxx"]),
    poofB: sprite([".xxx.", "xxxxx", "xxxxx", ".xxx."]),
    poofC: sprite(["x..x.", ".....", "..x..", "x...x"]),
}
const I_X_INK = { x: "ink" }, I_X_CREAM = { x: "cream" }, I_X_GLOW = { x: GLOW }, I_X_GOLD = { x: GOLD }

// what Clawd paints (5 x 4, a dab at a time), one per hobby slot
const PAINTINGS = [
    { rows: ["mmmmm", "ooyoo", "oyyyo", "ccccc"], inks: { m: "magenta", o: "#ff9e64", y: GOLD, c: "cyan" } },      // a sunset
    { rows: ["ppppp", "pooop", "pxoxp", "popop"], inks: { p: "primary", o: "claude", x: "ink" } },                  // a self-portrait
    { rows: [".ryr.", ".rrr.", "..g..", ".gg.."], inks: { r: "pink", y: GOLD, g: "green" } },                       // a flower
    { rows: ["ccwcc", "cmmmc", "mmmmm", "ggggg"], inks: { c: "cyan", w: "#ffffff", m: "#8b93ab", g: "green" } },    // a mountain
    { rows: [".r.r.", "rrrrr", ".rrr.", "..r.."], inks: { r: "pink" } },                                            // a heart
    { rows: ["nnnyn", "nynnn", "nnnnn", "tttnt"], inks: { n: "blue_dim", y: GLOW, t: "tertiary" } },                // a night sky
]
// the order its cells go on, so the picture comes together in seven dabs
function paintCells(n, slot) {
    const p = PAINTINGS[Math.floor(rnd(slot, 61, 3) * PAINTINGS.length)]
    const cells = []
    for (let y = 0; y < 4; y++) for (let x = 0; x < 5; x++) if (p.rows[y][x] !== ".") cells.push([x, y, p.inks[p.rows[y][x]], rnd(slot, x * 7 + y, 62)])
    cells.sort((a, b) => a[3] - b[3])
    return { cells: cells, shown: Math.ceil(cells.length * Math.min(7, n) / 7) }
}
// what rises out of the storybook
const TALES = [
    { sp: "castle", inks: { x: "#b7bdd0" } }, { sp: "plus", inks: { x: GOLD }, w: 3 },
    { sp: "ship", inks: { x: WOOD, s: "cream" } }, { sp: "fox", inks: { o: "#ff9e64", x: "ink", w: "#ffffff" } },
    { sp: "crown", inks: { y: GOLD, r: "red" } }, { sp: "moon", inks: { y: GLOW }, w: 3 },
]

// ---------- the figure ----------
// its body's shapes: [x, y, width, height, leg length] (the feet stay on y 9)
const SHAPES = {
    n: [4, 0, 12, 8, 2],        // standing
    d: [4, 1, 12, 8, 1],        // dipped: sitting down, a bow
    c: [3, 2, 14, 7, 1],        // crouched, squashed wide: before a jump, after a landing
    f: [2, 4, 16, 5, 1],        // flat: a heavy landing, halfway to a puddle
    s: [5, -2, 10, 10, 2],      // stretched tall: taking off, falling
    t: [4, -1, 12, 8, 3],       // on tiptoe
}

function eye(o, st, ex, ey, g, lhs) {
    switch (st) {
    case "open": o.r(g, ey, 1, 2, "ink"); break
    case "up": o.r(g, ey - 1, 1, 2, "ink"); break
    case "down": o.r(g, ey + 1, 1, 2, "ink"); break
    case "blink": o.p(g, ey + 1, "ink"); break
    case "half": o.p(g, ey + 1, "ink"); o.p(g, ey, "lo"); break
    case "heavy": o.p(g, ey + 1, "ink"); o.r(lhs ? g - 1 : g, ey, 2, 1, "lo"); o.p(g, ey + 2, "bags"); break
    case "wide": o.r(lhs ? ex : ex - 1, ey, 2, 2, "ink"); break
    case "shine": o.r(lhs ? ex : ex - 1, ey, 2, 2, "ink"); o.p(lhs ? ex : ex - 1, ey, "#ffffff"); break
    case "flat": o.r(ex - 1, ey + 1, 3, 1, "ink"); break
    case "joy": o.p(ex, ey, "ink"); o.p(ex - 1, ey + 1, "ink"); o.p(ex + 1, ey + 1, "ink"); break
    case "sleep": o.p(ex, ey + 1, "ink"); o.p(ex - 1, ey, "ink"); o.p(ex + 1, ey, "ink"); break
    case "squint":      // > <
        o.p(lhs ? ex - 1 : ex + 1, ey - 1, "ink"); o.p(ex, ey, "ink"); o.p(lhs ? ex - 1 : ex + 1, ey + 1, "ink"); break
    case "dizzy": o.pic(S.dizzy, ex - 1, ey - 1, I_X_INK); break
    case "heart": o.pic(S.heartEye, ex - 1, ey - 1, { x: "#ff4f86" }); break
    case "star": o.pic(S.plus, ex - 1, ey - 1, I_X_GLOW); break
    }
}

function arm(o, pose, lhs, B) {
    const x = lhs ? B.x - 2 : B.x + B.w, y = B.y + 4
    if (pose >= -1 && pose <= 1) o.r(x, y - pose, 2, 2, "body")
    else if (pose === 2) { o.r(x, y - 3, 2, 2, "body"); o.p(lhs ? x + 1 : x, y - 1, "body") }      // up high, past the head
    else if (pose === 3) o.r(lhs ? B.x + 1 : B.x + B.w - 4, B.y + 2, 3, 2, "lo")                    // over the eyes
    else if (pose === 5) o.r(lhs ? x - 1 : x, y, 3, 2, "body")                                      // held out sideways
    else if (pose === 6) o.r(x, y - 2, 2, 2, "body")                                                // between raised and high
}

function hatOn(o, s, B, lean, lift) {
    const hx = B.x - 4 + ((B.w - 12) >> 1) + lean, hy = B.y + lift
    if (s.hat === "nightcap" || s.hat === "santa") {
        const c = s.hat === "santa" ? "#d63a48" : "blue_dim", trim = s.hat === "santa" ? "cream" : "blue"
        o.r(hx + 5, hy - 4, 5, 1, c); o.p(hx + 3, hy - 3, c); o.r(hx + 6, hy - 3, 7, 1, c)
        o.r(hx + 5, hy - 2, 10, 1, c); o.r(hx + 4, hy - 1, 12, 1, trim); o.r(hx + 2, hy - 2, 2, 2, "cream")
    } else if (s.hat === "party") {
        o.r(hx + 7, hy - 1, 6, 1, "magenta"); o.r(hx + 8, hy - 2, 4, 1, "cyan")
        o.r(hx + 9, hy - 3, 2, 1, "yellow"); o.r(hx + 9, hy - 4, 2, 1, "cream")
    } else if (s.hat === "witch") o.pic(S.witch, hx + 3, hy - 6, { k: "#3a2853", o: "#f2994a" })
}

function figure(o, s, B, legLen, held) {
    const fx = s.fx, lean = fx.lean || 0
    // legs: tucked in the air, a pair lifted mid-step
    const lx = [B.x + 1, B.x + 3, B.x + B.w - 4, B.x + B.w - 2], top = B.y + B.h
    for (let i = 0; i < 4; i++) {
        let n = legLen
        if (fx.legs === "tuck") n = 1
        else if (fx.legs === "dangle") n = legLen + 1
        else if ((fx.legs === "a" && i % 2 === 0) || (fx.legs === "b" && i % 2 === 1)) n = legLen - 1
        if (n > 0) o.r(lx[i], top, 1, n, "lo")
    }
    // body: top light, darker underside; leaning shifts its upper half
    if (lean) {
        const half = B.h >> 1
        o.r(B.x + lean, B.y, B.w, half, "body"); o.r(B.x, B.y + half, B.w, B.h - half, "body")
    } else o.r(B.x, B.y, B.w, B.h, "body")
    o.r(B.x + 1 + lean, B.y, B.w - 2, 1, "hi")
    o.r(B.x, B.y + B.h - 1, B.w, 1, "lo")
    // the laptop screen's light on its face, the campfire's on its side
    if (held === "laptop") o.r(B.x, B.y, B.w, 4, "primary", 0.1 + 0.07 * (s.typed % 2))
    if (held === "fire") o.r(B.x + B.w - 2, B.y + 1, 2, B.h - 2, "#ffb347", 0.16 + 0.06 * (s.tw % 2))
    // snow: a scarf
    if (s.weather === "snow" || fx.scarf) {
        const c = fx.scarf ? "primary" : "#d9474f", k = fx.scarf ? "tertiary" : "#f08a8f"
        o.r(B.x, B.y + 5, B.w, 1, c); o.p(B.x + 2, B.y + 5, k); o.p(B.x + 6, B.y + 5, k); o.p(B.x + 10, B.y + 5, k)
        o.r(B.x + 8, B.y + 6, 2, 2, c)
    }
    arm(o, s.armL, true, B)
    arm(o, s.armR, false, B)
    const exL = B.x + 2 + lean, exR = B.x + B.w - 3 + lean, ey = B.y + 2
    eye(o, s.eyeL, exL, ey, exL + s.gaze, true)
    eye(o, s.eyeR, exR, ey, exR + s.gaze, false)
    if (s.blush) { o.p(B.x + 1, B.y + 4, "#f58c9a", 0.8); o.p(B.x + B.w - 2, B.y + 4, "#f58c9a", 0.8) }
    // mouth, only for a moment
    const mx = B.x + (B.w >> 1) - 1, my = B.y + 4
    switch (s.mouth) {
    case "o": o.r(mx, my, 2, 2, "ink"); break
    case "O": o.r(mx, my, 2, 3, "ink"); o.r(mx, my + 2, 2, 1, "#d8566a"); break
    case "smile": o.pic(S.smile, mx - 1, my, I_X_INK); break
    case "frown": o.pic(S.frown, mx - 1, my, I_X_INK); break
    case "tongue": o.pic(S.tongue, mx, my, { x: "ink", p: "pink" }); break
    case "line": o.r(mx, my + 1, 2, 1, "ink"); break
    case "chew": o.r(mx, my, 2, 1, "ink"); break
    }
    // weekend daytime: shades; and the ones that drop in (an act)
    if (s.shades || fx.prop === "drop") {
        const y = ey + (fx.prop === "drop" ? at([-5, -3, -1, 0], s.f) : 0)
        o.r(B.x + lean, y, B.w, 1, "#141318"); o.r(B.x + 1 + lean, y + 1, 3, 1, "#141318"); o.r(B.x + B.w - 4 + lean, y + 1, 3, 1, "#141318")
        o.p(B.x + 1 + lean, y, fx.glint ? "#ffffff" : "#5d5868"); o.p(B.x + B.w - 4 + lean, y, "#5d5868")
    }
    hatOn(o, s, B, lean, fx.hat || 0)
    // music: headphones (under a hat only the cups show)
    if (held === "music" || s.cans) {
        const cup = "cans_cup"
        if (!s.hat) { o.r(B.x + lean, B.y - 1, B.w, 1, "tertiary"); o.p(B.x - 1, B.y, "tertiary"); o.p(B.x + B.w, B.y, "tertiary") }
        o.r(B.x - 2, B.y + 1, 2, 3, cup); o.r(B.x + B.w, B.y + 1, 2, 3, cup)
        o.r(B.x - 2, B.y + 1, 2, 1, "tertiary"); o.r(B.x + B.w, B.y + 1, 2, 1, "tertiary")
    }
}

// ---------- props ----------
const BACK = {}, HELD = {}, OVER = {}, FRONT = {}
const ALIAS = { cup: "mug" }

// ---- at work ----
// laptop: the lid's back to us with the Claude spark on it, hands taking turns on the keys
HELD.laptop = function (o, s) {
    o.r(5, 4, 10, 4, "#aeb4c3"); o.r(5, 4, 10, 1, "#dfe3ec"); o.r(5, 7, 10, 1, "#959bab")
    o.pic(S.mark, 8, 4, { x: "claude" })
    o.r(3, 8, 14, 1, "#6f7586")
    o.r(3, 7 + (s.fx.hl || 0), 2, 1, "body"); o.r(15, 7 + (s.fx.hr || 0), 2, 1, "body")
}
// lines of code drifting off the keys
OVER.code = function (o, s) {
    const f = s.pf, cols = ["primary", "green", "yellow", "tertiary"]
    for (let i = 0; i < 3; i++) {
        const age = f - i * 2
        if (age < 0 || age > 5) continue
        o.r(17 + i + (age >> 1), 4 - age - i, 1 + (i + f) % 3, 1, cols[(i + (f >> 2)) % 4], age > 3 ? 0.4 : 0.9)
    }
}
// coffee (morning, or keeping a tired Clawd going); lifted to sip
HELD.mug = function (o, s) {
    const cup = s.fx.prop === "cup", up = cup && s.pf === 1
    const x = up ? -4 : cup ? -1 : 0, y = cup ? -1 : 0
    o.r(18 + x, 3 + y, 2, 3, "cream"); o.r(18 + x, 3 + y, 2, 1, "#6f4330"); o.r(18 + x, 5 + y, 2, 1, "primary"); o.p(20 + x, 4 + y, "cream")
    if (s.fx.cookie) o.r(16 + x, 2 + y, 2, 2, "#c98a4b")
    if (!up) { o.p(18 + x + s.tw % 2, 1 + y, "cream", 0.4); o.p(19 + x - s.tw % 2, y, "cream", 0.22) }
    if (s.fx.blow) { o.p(21 + s.fx.blow, 1, "cream", 0.5); o.p(22 + s.fx.blow, 0, "cream", 0.3) }
}
// hourglass while a window is out: the top drains as the reset gets closer, a grain falling
BACK.hourglass = function (o, s) {
    const wood = "secondary", pane = "#ffffff", grain = "yellow", sand = s.sand
    o.r(18, 3, 5, 1, wood); o.r(18, 9, 5, 1, wood)
    o.p(18, 4, pane, 0.3); o.p(22, 4, pane, 0.3); o.p(19, 5, pane, 0.3); o.p(21, 5, pane, 0.3)
    o.p(19, 7, pane, 0.3); o.p(21, 7, pane, 0.3); o.p(18, 8, pane, 0.3); o.p(22, 8, pane, 0.3)
    o.r(19, 4, 3, 1, pane, 0.1); o.r(19, 8, 3, 1, pane, 0.1)
    if (sand > 0.66) o.r(19, 4, 3, 1, grain); else if (sand > 0.33) o.p(20, 4, grain)
    if (sand > 0.05) o.p(20, 5, grain)
    if (sand > 0.02 && s.zz % 2 === 0) o.p(20, 6, grain)
    if (sand < 0.34) { o.r(19, 8, 3, 1, grain); o.p(20, 7, grain) } else if (sand < 0.67) o.r(19, 8, 3, 1, grain); else o.p(20, 8, grain)
}
// a shell command: hammering at a block, sparks on each hit (hf 0 raised, 1 the hit, 2 wound up, 3 a big one)
BACK.hammer = function (o, s) {
    o.r(18, 6, 5, 4, "#8f735f"); o.r(18, 6, 5, 1, "#b39479"); o.p(21, 8, "#6f5847"); o.p(19, 7, "#7d6452")
    if (s.pf === 3) { o.p(20, 6, "#6f5847"); o.p(20, 7, "#6f5847") }
}
HELD.hammer = function (o, s) {
    const f = s.pf
    if (f === 0) { o.r(18, 0, 1, 3, WOOD); o.r(17, -2, 3, 2, STEEL) }
    else if (f === 2) { o.r(17, -2, 1, 3, WOOD); o.r(15, -4, 3, 2, STEEL) }
    else {
        o.r(18, 4, 1, 1, WOOD); o.r(19, 3, 3, 3, STEEL); o.r(19, 3, 3, 1, "#c9cfdd")
        o.p(18, 2, GOLD); o.p(22, 2, GOLD); o.p(23, 4, GOLD, 0.6)
        if (f === 3) { o.p(17, 1, GOLD); o.p(24, 1, GOLD); o.p(25, 5, GOLD, 0.6); o.p(23, 0, GLOW) }
    }
}
// reading code: a magnifier sweeps over a page
BACK.magnifier = function (o, s) {
    const flip = s.fx.page || 0
    o.r(18, 3, 5, 7, PAPER)
    if (flip === 1) { o.r(18, 3, 3, 7, "#d6cfc3"); o.r(21, 3, 2, 7, "#ffffff") }
    else if (flip === 2) o.r(18, 3, 1, 7, "#d6cfc3")
    else { o.r(19, 4, 3, 1, "#a9a49c"); o.r(19, 6, 2, 1, "#a9a49c"); o.r(19, 7, 3, 1, "#a9a49c"); o.p(19, 8, "#a9a49c") }
}
HELD.magnifier = function (o, s) {
    const f = s.pf % 4
    o.pic(S.lens, 17 + [0, 1, 2, 1][f], 2 + [0, 1, 0, 2][f], { r: "#cfd5e3", g: "#ffffff", s: ["#9ccfff", 0.55], h: WOOD })
}
// the web: a little globe spinning on its hand, land drifting across as it turns; tossed, a ping circling
HELD.globe = function (o, s) {
    const f = s.pf, up = s.fx.toss || 0
    const cells = [[1, 0], [2, 0], [0, 1], [1, 1], [2, 1], [3, 1], [0, 2], [1, 2], [2, 2], [3, 2], [1, 3], [2, 3]]
    for (let i = 0; i < cells.length; i++) {
        const x = cells[i][0], y = cells[i][1], u = (x + f) % 4
        const land = (u === 0 && y > 0) || (u === 1 && y === 1) || (u === 3 && y === 2)
        o.p(17 + x, -1 + y - up, land ? "#6cc28a" : "#5b8ee6")
    }
    o.p(18, -1 - up, "#ffffff", 0.55)
    if (s.fx.ping) {
        const orbit = [[16, -2], [19, -3], [22, -1], [21, 2], [18, 3], [16, 1]], q = orbit[f % 6]
        o.p(q[0], q[1], GLOW); o.p(q[0] + (f % 2 ? 1 : -1), q[1], GLOW, 0.4)
    }
}
// juggling (subagents, or just showing off)
HELD.balls = function (o, s) {
    const arc = [[2, 1], [3, -2], [6, -4], [9, -5], [12, -4], [15, -2], [16, 1]], cols = ["red", "yellow", "cyan"]
    for (let i = 0; i < 3; i++) { const q = arc[(s.pf + i * 2) % 7]; o.r(q[0], q[1], 2, 2, cols[i]) }
}
// subagents: two little Clawds at its sides, taking turns
FRONT.mini = function (o, s) {
    const f = s.pf, up = s.fx.pop === undefined ? 3 : s.fx.pop
    const inks = { b: "body", x: "ink", l: "lo" }
    const yl = 9 - up - (up === 3 && f % 4 === 1 ? 1 : 0), yr = 9 - up - (up === 3 && f % 4 === 3 ? 1 : 0)
    o.pic(S.mini, -6, yl, inks); o.pic(S.mini, 20, yr, inks)
    if (up === 3) {
        // a spark passed over its head from one to the other
        const path = [[-4, 3], [0, -1], [5, -3], [10, -4], [15, -3], [20, -1], [22, 3]]
        const q = path[f % 7 < 4 ? (f % 7) * 2 : 12 - (f % 7) * 2]
        if (q) { o.p(q[0], q[1], "claude"); o.p(q[0] + 1, q[1], "claude", 0.5); o.p(q[0], q[1] - 1, "claude", 0.5) }
    }
}
// compacting: sweeping up, with a little dust
HELD.broom = function (o, s) {
    const f = s.pf
    o.pic(S.broom, 16 + [0, 1, 2, 1][f % 4], 0, { h: WOOD, b: "#d9b35b" })
    if (f % 2 === 1) o.p(21 + f % 3 + [0, 1, 2, 1][f % 4], 6, "#c9ccd6", 0.5)
    if (f % 4 === 3) o.p(23, 5, "#c9ccd6", 0.35)
}
BACK.broom = function (o, s) {
    // the pile it is sweeping away
    const left = Math.max(0, 3 - (s.fx.pile || 0))
    for (let i = 0; i < left; i++) o.r(23 - i, 9 - (i === 1 ? 1 : 0), 2, 1 + (i === 1 ? 1 : 0), "#c9ccd6", 0.55)
}
// rain: an umbrella in this screen's colours (twirled: the stripes move round)
HELD.umbrella = function (o, s) {
    const turn = s.fx.twirl || 0
    for (let i = 0; i < 14; i++) o.p(3 + i, -2, (i + turn) % 4 < 2 ? "primary" : "tertiary")
    o.r(5, -3, 10, 1, turn % 2 ? "tertiary" : "primary"); o.r(8, -4, 4, 1, turn % 2 ? "primary" : "tertiary"); o.p(9, -5, "cream")
    o.r(16, -1, 1, 4, "#3b3a44")
}
BACK.umbrella = function (o, s) {
    // the puddle it likes to jump in
    o.r(-4, 9, 6, 1, "#5b8ee6", 0.7); o.p(-2, 9, "#b9d8ff", 0.8)
    if (s.fx.splash) {
        const k = s.fx.splash
        o.p(-5 - k, 9 - k, WATER); o.p(3 + k, 9 - k, WATER); o.p(-2, 8 - k, WATER, 0.7); o.p(0, 9 - 2 * k, WATER, 0.5)
    }
}

// ---- off duty: its hobbies ----
// a book of fables held open, a page turning now and then (hf 1-3)
HELD.book = function (o, s) {
    const f = s.pf
    o.pic(S.book, 4, 4, { p: "cream", s: "#cfc6b8", l: "#a9a49c", c: "primary" })
    if (f === 1) o.r(11, 3, 3, 1, "#ffffff"); else if (f === 2) o.r(9, 2, 1, 2, "#ffffff"); else if (f === 3) o.r(6, 3, 3, 1, "#ffffff")
    o.r(2, 5, 2, 2, "body"); o.r(16, 5, 2, 2, "body")
}
// ...and what rises out of its pages (g: 0 a glimmer, 1 taking shape, 2 there)
OVER.tale = function (o, s) {
    const t = TALES[(s.fx.tale || 0) % TALES.length], g = s.fx.g || 0
    if (g === 0) { o.p(14, 2, GLOW); o.p(16, 0, GLOW, 0.6); o.p(13, 0, GLOW, 0.4); return }
    const x = 16 + (t.w === 3 ? 1 : 0), y = g === 1 ? -5 : -6
    o.pic(S[t.sp], x, y, t.inks, g === 1 ? 0.5 : 1)
    if (g >= 2) { o.p(15, -7 + s.pf % 2, GLOW); o.p(22, -4 - s.pf % 2, GLOW, 0.7); o.p(16, -1, GLOW, 0.4) }
}
// a handheld game: thumbs on the buttons, a blip running round the screen
HELD.game = function (o, s) {
    const f = s.pf, fx = s.fx
    o.pic(S.game, 6, 4, { g: GREY, s: fx.lost ? "#5d2f3a" : "#2f5d50", d: "#3b3f4c", b: "red" })
    if (fx.won) { o.p(8, 5, GOLD); o.p(10, 6, GOLD); o.p(11, 5, GOLD) }
    else if (!fx.lost) o.p(8 + f % 4, 5 + (f % 3 === 0 ? 1 : 0), "#9be7a8")
    o.p(6, 5 + (fx.hl || 0), "hi"); o.p(13, 5 + (fx.hr || 0), "hi")
    o.r(4, 5, 2, 2, "body"); o.r(14, 5, 2, 2, "body")
}
// painting at an easel: each dab adds to the picture, a finished one gets admired, then a fresh canvas
BACK.paint = function (o, s) {
    o.pic(S.easel, 17, -3, { w: "#9a6b4b", c: "cream" })
    const p = paintCells(s.prog, s.slot)
    for (let i = 0; i < p.shown; i++) o.p(18 + p.cells[i][0], -2 + p.cells[i][1], p.cells[i][2])
}
HELD.paint = function (o, s) {
    const p = paintCells(s.prog, s.slot), next = p.cells[Math.min(p.shown, p.cells.length - 1)]
    const y = s.armR === 2 ? 1 : 3
    o.p(18, y, "#c9a27a"); o.p(19, y - 1, next ? next[2] : "cream")
}
// bubbles: a wand in the raised hand; blown ones float up and pop
HELD.bubbles = function (o) { o.pic(S.wand, 18, -1, { x: "#c9cdd8" }) }
FRONT.bubble = function (o, s) {
    const f = s.pf, big = s.fx.big
    if (big) {              // one great wobbling bubble
        const q = at([[19, -3], [20, -5], [21, -7], [21, -8]], f - 2)
        if (f >= 2 && f < 7) { o.pic(S.ringBig, q[0] + (f % 2), q[1], { x: ["#d9f1ff", 0.9] }); o.p(q[0] + 1 + (f % 2), q[1] + 1, "#ffffff") }
        else if (f >= 7 && f < 9) { o.p(20, -9, "#d9f1ff"); o.p(24, -7, "#d9f1ff"); o.p(22, -5, "#d9f1ff", 0.6); o.p(25, -9, "#d9f1ff", 0.6) }
        return
    }
    const paths = [[[19, -3], [20, -4], [19, -5], [20, -6], [21, -7]], [[20, -2], [22, -3], [23, -4], [22, -6], [23, -7]],
                   [[19, -3], [18, -5], [17, -6], [18, -7], [17, -8]]]
    for (let i = 0; i < 3; i++) {
        const step = f - i * 2
        if (step < 0 || step > 5) continue
        if (step === 5) { const q = paths[i][4]; o.p(q[0] - 1, q[1], "#d9f1ff", 0.7); o.p(q[0] + 2, q[1] + 1, "#d9f1ff", 0.7); o.p(q[0] + 1, q[1] - 1, "#d9f1ff", 0.5); continue }
        const q = paths[i][step]
        o.r(q[0], q[1], 2, 2, "#8fd0ff", 0.6); o.p(q[0], q[1], "#ffffff", 0.9)
    }
}
// a yo-yo on its string (hf: how far down), walked along the ground, swung right round
HELD.yoyo = function (o, s) {
    const f = s.pf, fx = s.fx
    if (fx.dog !== undefined) {         // walking the dog
        o.line(18, 5, 18 + fx.dog, 8, "#d9dce4", 0.8)
        o.r(18 + fx.dog, 8, 2, 2, "red"); o.p(19 + fx.dog, 8, "#ffffff", 0.5)
    } else if (fx.orbit !== undefined) {    // around the world
        const q = [[18, 8], [22, 6], [23, 2], [21, -1], [17, -2], [21, -1], [23, 2], [22, 6]][fx.orbit % 8]
        o.line(18, 4, q[0], q[1], "#d9dce4", 0.6); o.r(q[0], q[1], 2, 2, "red"); o.p(q[0] + 1, q[1], "#ffffff", 0.5)
    } else {
        o.r(18, 4, 1, 1 + f, "#d9dce4", 0.8)
        o.r(18, 5 + f, 2, 2, "red"); o.p(19, 5 + f, "#ffffff", 0.5); o.p(18, 6 + f, "#b8485c")
    }
}
// a potted plant that grows as it's watered (prog 0-3: a sprout ... in bloom)
BACK.plant = function (o, s) {
    const g = Math.min(3, s.prog), h = [1, 2, 3, 3][g]
    o.pic(S.pot, 18, 7, { h: "#e08b62", r: "#c8734f" })
    o.r(19, 7 - h, 1, h, "leaf_dark")
    if (g >= 1) o.p(20, 6, "green")
    if (g >= 2) o.p(18, 5, "green")
    if (g >= 3) o.pic(S.bloom, 18, 2, { p: "pink", y: GOLD })
}
// the watering can (an act), pouring from its spout
HELD.can = function (o, s) {
    const f = s.pf
    o.pic(S.can, 17, 1, { b: "#7d8fb3", s: "#a9b8d6" })
    if (f >= 1) o.p(21, 3 + (f - 1), WATER)
    if (f >= 2) o.p(21, 5 + (f - 2), WATER, 0.7)
}
// a block tower, one block at a time up to four; then it topples (hf 1-3)
BACK.blocks = function (o, s) {
    const f = s.pf, n = Math.min(4, s.prog)
    const tint = ["primary", "tertiary", "yellow", "cyan"], fallen = [[16, 8], [19, 8], [22, 8], [24, 6]]
    for (let i = 0; i < n; i++) {
        const lean = f > 0 && f < 3 ? Math.max(0, i - (n - 1) + f) : 0
        const x = f === 3 ? fallen[i][0] : 18 + lean, y = f === 3 ? fallen[i][1] : 8 - 2 * i
        o.r(x, y, 2, 2, tint[i]); o.p(x, y, "#ffffff", 0.3)
    }
}
// at night: a little telescope
BACK.telescope = function (o) {
    o.pic(S.scope, 15, -2, { t: "#8b93ab" }); o.p(21, -2, "#dfe7ff")
    o.pic(S.tripod, 16, 2, { l: GREY })
}
// ...and what it finds: a shooting star, a constellation coming together, a visitor
FRONT.shoot = function (o, s) {
    const q = at([[1, -6], [4, -6], [7, -5], [10, -5], [13, -4], [16, -4], [19, -3]], s.pf)
    o.p(q[0], q[1], GLOW); o.p(q[0] - 1, q[1], GLOW, 0.55); o.p(q[0] - 2, q[1] - (s.pf % 2), GLOW, 0.25)
}
FRONT.constel = function (o, s) {
    const shapes = [[[19, -3], [21, -5], [23, -4], [24, -6], [22, -7]], [[20, -7], [22, -6], [24, -7], [23, -4], [21, -3]],
                    [[19, -6], [21, -7], [23, -6], [22, -4], [24, -3]]]
    const pts = shapes[(s.fx.sky || 0) % 3], n = Math.min(pts.length, s.pf + 1)
    for (let i = 1; i < n; i++) if (s.pf >= pts.length + i - 1) o.line(pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1], "blue", 0.35)
    for (let i = 0; i < n; i++) o.p(pts[i][0], pts[i][1], i === n - 1 && s.pf < pts.length ? "#ffffff" : GLOW)
}
FRONT.ufo = function (o, s) {
    const x = 26 - s.pf * 3
    if (s.fx.sky === 1) o.pic(S.planet, x, -7, { p: "#f2994a", r: "#ffd9a8" })
    else { o.pic(S.ufo, x, -7 + (s.pf % 2), { c: "cyan", x: STEEL, y: GOLD }); if (s.pf % 2) o.r(x + 1, -4, 2, 2, GOLD, 0.25) }
}
// knitting: needles clicking, the scarf a row longer each time (prog rows)
BACK.knit = function (o) {
    o.pic(S.yarn, 19, 6, { y: "tertiary", h: "#ffffff" })
    o.p(18, 9, "tertiary", 0.8); o.p(17, 8, "tertiary", 0.8)
}
HELD.knit = function (o, s) {
    const a = s.pf % 2, rows = Math.min(5, s.prog)
    for (let i = 0; i < rows; i++) o.r(8, 5 + i, 4, 1, i % 2 ? "tertiary" : "primary")
    o.line(4, 7 - a, 10, 3 + a, "#dfe3ec"); o.line(15, 6 + a, 9, 4 - a, "#dfe3ec")
    o.r(2, 6 - a, 2, 2, "body"); o.r(16, 5 + a, 2, 2, "body")
}
// fishing: a rod over a little pond, the float bobbing; now and then something bites
BACK.fish = function (o, s) {
    o.r(18, 9, 8, 1, "#4f86d9"); o.p(20, 9, "#9cc4ff"); o.p(24, 9, "#9cc4ff", 0.7)
    if (s.fx.ripple) { o.p(21 - s.fx.ripple, 8, WATER, 0.6); o.p(24 + s.fx.ripple, 8, WATER, 0.6) }
}
HELD.fish = function (o, s) {
    const fx = s.fx, pull = fx.pull || 0
    // the rod, bent when something's on it
    if (pull) { o.line(17, 3, 20, -1, WOOD); o.line(20, -1, 22, 0, WOOD) } else o.line(17, 3, 22, -2, WOOD)
    const top = pull ? 1 : -1, end = fx.land !== undefined ? fx.land : 8 + (fx.bob || 0)
    if (end > top) o.r(22, top, 1, end - top, "#e8ecf4", 0.45)
    if (fx.land === undefined) { o.p(22, 7 + (fx.bob || 0), "red"); o.p(22, 8 + (fx.bob || 0), "#ffffff") }
    else if (fx.haul === "fish") o.pic(S.fish, 20, end, { x: "#7fd4c1", e: "ink" })
    else if (fx.haul === "boot") o.pic(S.boot, 21, end, { x: "#7a5a44", s: "#4f3a2c" })
    else if (fx.haul === "star") { o.pic(S.plus, 21, end, I_X_GOLD); o.p(22, end + 1, "#ffffff") }
}
// a kite on its string, swaying
FRONT.kite = function (o, s) {
    const q = [[20, -7], [21, -7], [21, -6], [20, -6], [19, -7], [20, -7], [21, -7], [20, -6]][s.pf % 8]
    const x = q[0] - (s.fx.dive ? 1 : 0), y = q[1] + (s.fx.dive ? 2 * s.fx.dive : 0), w = s.pf % 2
    o.line(17, 1, x + 2, y + 4, "cream", 0.55)
    o.pic(S.kite, x, y, { p: "primary", t: "tertiary", c: "cream" })
    o.p(x + 2 + (w ? 1 : -1), y + 5, "red"); o.p(x + 2 + (w ? 2 : -2), y + 6, "yellow"); o.p(x + 2 + (w ? 1 : -1), y + 7, "red", 0.7)
}
// a ukulele across its lap
HELD.uke = function (o, s) {
    o.pic(S.uke, 2, 5, { h: "#5a3a22", n: WOOD, b: "#e0aa63", o: "#5a3a22" })
    o.r(4, 7, 2, 1, "body"); o.r(10, 4 + (s.fx.hr || 0), 2, 1, "body"); o.r(10, 5 + (s.fx.hr || 0), 2, 1, "lo")
}
// a bowl of noodles: lifted, slurped (hf 1-3), the broth drunk from the bowl
HELD.bowl = function (o, s) {
    const f = s.pf, noodle = "#f2d16b"
    const rim = "#9db8ee", bowl = "#4f6fb8", foot = "#3d5796", stick = "#d9b48a"
    if (s.fx.drink) {           // the bowl tipped up over its face
        o.r(6, 1, 8, 1, foot); o.r(5, 2, 10, 2, bowl); o.r(4, 4, 12, 1, rim); o.p(7, 2, "#ffffff", 0.6); o.p(11, 3, "#ffffff", 0.6)
        o.r(2, 3, 2, 2, "body"); o.r(16, 3, 2, 2, "body")
        return
    }
    o.r(7, 5, 6, 1, noodle); o.r(8, 4, 4, 1, noodle); o.p(11, 5, "#ffffff"); o.p(8, 5, "#ff8fa8"); o.p(10, 4, "#e8b84a")
    o.r(6, 6, 8, 1, rim); o.r(6, 7, 8, 1, bowl); o.r(7, 8, 6, 1, bowl); o.r(8, 9, 4, 1, foot); o.p(8, 7, "#ffffff", 0.6); o.p(12, 8, "#ffffff", 0.35)
    if (f === 1) { o.r(9, 2, 2, 3, noodle); o.line(17, 0, 11, 2, stick); o.r(16, 0, 2, 2, "body") }
    else if (f === 2) { o.r(9, 3, 1, 2, noodle); o.p(10, 4, noodle); o.line(17, 0, 11, 2, stick); o.r(16, 0, 2, 2, "body") }
    else { o.line(17, 2, 14, 5, stick); o.line(18, 2, 15, 5, stick); o.r(16, 3, 2, 2, "body") }
    o.p(4, 3 - s.tw % 2, "cream", 0.3); o.p(15, 1 + s.tw % 2, "cream", 0.22)
    o.r(4, 7, 2, 1, "body")
}
// origami: a sheet, folded and folded again into a crane (prog 0-3)
HELD.origami = function (o, s) {
    const g = s.prog, inks = { x: "#f6f1e8", s: "#cfc6b8" }, a = s.fx.hl || 0
    if (g <= 0) { o.r(8, 4, 5, 4, "#f6f1e8"); o.r(8, 7, 5, 1, "#cfc6b8"); if (s.fx.crease) o.line(8, 7, 12, 4, "#cfc6b8") }
    else if (g === 1) o.pic(S.tri, 8, 3, inks)
    else if (g === 2) o.pic(S.diamond, 9, 4, inks)
    else if (!s.fx.gone) o.pic(S.crane, 7, 4, inks)
    o.p(6, 6 - a, "hi"); o.p(13, 6 - (s.fx.hr || 0), "hi")
}
FRONT.crane = function (o, s) {
    const q = at([[8, 3], [10, 1], [13, -1], [16, -3], [19, -5], [22, -7], [26, -9]], s.pf)
    o.pic(s.pf % 2 ? S.craneDown : S.craneUp, q[0], q[1], { x: "#f6f1e8", s: "#cfc6b8" })
}
// a puzzle cube: every twist shuffles its face; now and then it comes out solved
HELD.cube = function (o, s) {
    const cols = ["red", "yellow", "cyan", "green", "primary", "cream"], fx = s.fx
    const seed = (s.prog | 0) * 16 + (s.pf | 0)
    o.r(8, 3, 4, 4, "#2a2c38")
    for (let i = 0; i < 9; i++)
        o.p(8 + i % 3, 3 + Math.floor(i / 3), fx.solved ? "yellow" : cols[Math.floor(rnd(seed, i, 71) * 6)])
    o.r(7, 4 + (fx.hl || 0), 1, 2, "hi"); o.r(12, 4 + (fx.hr || 0), 1, 2, "hi")
}
// a skateboard under its feet (by: the board off the ground, in an ollie)
FRONT.skate = function (o, s) {
    const fx = s.fx, x = fx.dx || 0, y = -(fx.by || 0)
    o.r(3 + x, 8 + y, 14, 1, "red"); o.p(2 + x, 7 + y, "red"); o.p(17 + x, 7 + y, "red"); o.r(5 + x, 8 + y, 10, 1, "#ff9aa8", 0.5)
    o.p(5 + x, 9 + y, "#e8ecf4"); o.p(14 + x, 9 + y, "#e8ecf4")
    if (fx.speed) { o.r(fx.speed > 0 ? x - 1 : 19 + x, 8, 2, 1, "#ffffff", 0.35); o.p(fx.speed > 0 ? x - 3 : 22 + x, 9, "#ffffff", 0.25) }
}
// a campfire, a marshmallow on a stick turning golden over it (prog 0-2)
BACK.fire = function (o, s) {
    const f = s.pf + s.tw
    o.pic([S.flameA, S.flameB, S.flameC][f % 3], 19, 5, { o: FLAME, y: GOLD })
    o.r(18, 9, 6, 1, "#6b4a36"); o.p(19, 8, WOOD); o.p(22, 8, WOOD); o.p(20, 8, GLOW)
    o.p(20 + f % 3, 3 - f % 2, GOLD, 0.7); if (f % 3 === 1) o.p(23, 2, FLAME, 0.5)
}
HELD.fire = function (o, s) {
    const fx = s.fx, col = at(["#ffffff", "#f6e3c5", "#dba765", "#dba765"], s.prog)
    if (fx.bite) { o.r(11, 4, 2 - (fx.bite > 1 ? 1 : 0), 2, col); o.r(13, 4, 4, 1, WOOD); return }      // brought up to eat
    o.r(18, 4, 3, 1, WOOD); o.r(21, 3 - (s.pf % 2 ? 1 : 0), 2, 2, col)
    if (fx.burnt) { o.p(21, 2, FLAME); o.p(22, 1, GOLD) }
}
// morning stretches, on a mat
BACK.yoga = function (o) { o.r(0, 10, 20, 1, "tertiary", 0.85); o.r(0, 10, 2, 1, "#ffffff", 0.25) }
// a barbell: on the ground, at its chest, over its head (bar 0-2)
FRONT.weights = function (o, s) {
    const lvl = s.fx.bar || 0, y = [8, 5, -3][lvl]
    o.r(1, y, 18, 1, "#c9cfdd"); o.r(0, y - 1, 2, 3, "#4b5063"); o.r(18, y - 1, 2, 3, "#4b5063")
    o.p(0, y - 1, "#6d7389"); o.p(18, y - 1, "#6d7389")
    if (lvl === 1) { o.r(2, 5, 2, 1, "body"); o.r(16, 5, 2, 1, "body") }
}
// a paper plane: in its hand, then out on a loop
HELD.plane = function (o, s) { if (!s.fx.thrown) o.pic(S.dart, 17, 1, { x: "#f6f1e8", s: "#cfc6b8" }) }
FRONT.glide = function (o, s) {
    const path = [[19, 0, 0], [22, -2, 0], [24, -5, 2], [22, -7, 1], [18, -8, 1], [14, -7, 1], [10, -6, 1], [6, -7, 1],
                  [2, -6, 1], [-2, -4, 3], [-3, -1, 3], [0, 1, 0]]
    const q = at(path, s.pf), inks = { x: "#f6f1e8", s: "#cfc6b8" }
    if (s.fx.bonk) { o.pic(S.dartDown, 9, -3 + s.fx.bonk, inks); return }
    o.pic([S.dart, S.dartL, S.dartUp, S.dartDown][q[2]], q[0], q[1], inks)
}
// a jump rope (hf: 0 hanging loose, 1 over its head, 2 coming down in front, 3 under its feet, 4 behind)
HELD.rope = function (o, s) {
    const f = s.pf % 5, c = "tertiary"
    const side = f === 1 ? [[1, 3], [1, 2], [1, 1], [2, 0], [2, -1], [3, -2], [4, -3]]
               : f === 3 || f === 0 ? [[1, 5], [1, 6], [2, 7], [2, 8], [3, 9]] : [[1, 4]]
    if (!s.fx.tangle) for (let i = 0; i < side.length; i++) { o.p(side[i][0], side[i][1], c); o.p(19 - side[i][0], side[i][1], c) }
    if (f === 1) o.r(5, -4, 10, 1, c)
    else if (f === 2) o.r(2, 6, 16, 1, c, 0.35)
    o.p(2, 4, "cream"); o.p(17, 4, "cream")
}
FRONT.rope = function (o, s) {
    // under its feet: on the ground, whatever height it's at
    const f = s.pf % 5
    if (s.fx.tangle) { o.line(2, 6, 8, 9, "tertiary"); o.line(8, 9, 13, 5, "tertiary"); o.line(13, 5, 17, 8, "tertiary") }
    else if (f === 3 || f === 0) o.r(4, 10, 12, 1, "tertiary")
}
// a cat keeping it company (prog 3+: asleep on its head)
BACK.cat = function (o, s) {
    if (s.prog >= 3 && !s.hat) return
    const fx = s.fx, inks = { x: PAPER, e: "#3b3f51", t: "#cfc6b8", s: "#b9b2a6" }
    const hop = fx.catUp || 0
    o.pic(fx.purr ? S.catPurr : S.cat, 18, 4 - hop, inks)
    if (!fx.purr && s.tw % 2) o.p(22, 5 - hop, "#cfc6b8")       // the tail flicks
}
OVER.cat = function (o, s) {
    if (!(s.prog >= 3 && !s.hat)) return
    o.pic(S.catLoaf, 7, -4, { x: PAPER, e: s.tw % 4 === 3 ? PAPER : "#3b3f51" })
    o.p(13, -1 + (s.tw % 2), "#cfc6b8")
}
// pancakes: one in the pan, tossed (hf), the finished ones stacking up on a plate (prog)
BACK.pan = function (o, s) {
    const n = Math.min(4, s.prog), bites = s.fx.eaten || 0
    o.r(-6, 9, 7, 1, "#dfe3ec")
    for (let i = 0; i < n - bites; i++) o.r(-5, 8 - i, 5, 1, i % 2 ? "#d9a05b" : "#e8b96a")
    if (n >= 4 && !bites) o.p(-3, 4, GOLD)
}
HELD.pan = function (o, s) {
    const f = s.pf, tilt = f === 1 ? -1 : 0, fx = s.fx
    o.r(18, 4 + tilt, 2, 1, GREY); o.r(20, 4 + tilt, 5, 1, "#3b3f4c"); o.p(20, 3 + tilt, "#3b3f4c"); o.p(24, 3 + tilt, "#3b3f4c")
    if (fx.onHead || fx.nocake) return
    const q = at([[21, 3, 0], [21, 1, 0], [22, -2, 1], [22, -5, 0], [22, -6, 1], [22, -3, 0], [21, 0, 1], [21, 3, 0]], f)
    if (q[2]) o.r(q[0] + 1, q[1] - 1, 1, 3, "#e8b96a"); else o.r(q[0], q[1], 3, 1, "#e8b96a")
}
OVER.pan = function (o, s) { if (s.fx.onHead) { o.r(7, -1, 6, 1, "#e8b96a"); o.p(6, 0, "#e8b96a"); o.p(13, 0, "#d9a05b") } }
// a snowman, a ball at a time (prog 0-4)
BACK.snowman = function (o, s) {
    const g = s.prog, inks = { x: SNOW, s: "#cdd6e6" }
    if (g <= 0) { o.r(19 + (s.fx.roll || 0), 8, 2, 2, SNOW); return }
    o.pic(S.snowBase, 18, 7, inks)
    if (g >= 2) o.r(19, 5, 3, 2, SNOW)
    if (g >= 3) { o.r(19, 3, 3, 2, SNOW); o.p(19, 3, "ink"); o.p(21, 3, "ink") }
    if (g >= 4) {
        o.p(20, 4, FLAME); o.r(19, 2, 3, 1, "#3b3f51"); o.p(20, 1, "#3b3f51"); o.r(19, 5, 3, 1, "red")
        o.p(17, 5 - (s.fx.hello || 0), WOOD); o.p(18, 6, WOOD); o.p(22, 6, WOOD); o.p(23, 5, WOOD)
    }
}
// Halloween: a pumpkin, carved a cut at a time, then lit (prog 0-3)
BACK.pumpkin = function (o, s) {
    const g = s.prog, lit = g >= 3
    o.pic(S.pumpkin, 18, 4, { g: "#6cc28a", o: "#f2994a", d: "#e08530" })
    const face = lit ? (s.tw % 3 === 2 ? "#ffb347" : GOLD) : "#3a2110"
    if (g >= 1) { o.p(19, 6, face); o.p(22, 6, face) }
    if (g >= 2) { o.r(19, 8, 4, 1, face); o.p(20, 8, "#f2994a") }
    if (lit) { o.p(20, 7, GOLD, 0.6); o.p(17, 9, GOLD, 0.35); o.p(24, 9, GOLD, 0.35) }
}
// December: a little tree, a bauble at a time, a star on top (prog 0-5), its lights taking turns
BACK.tree = function (o, s) {
    const g = s.prog
    o.pic(S.fir, 18, 2, { g: "#3f9d6b", t: WOOD })
    o.p(19, 4, "#57b784"); o.p(21, 7, "#57b784")
    const spots = [[20, 4], [19, 6], [21, 5], [22, 8], [18, 7]], cols = ["red", "yellow", "cyan", "magenta", "#ffffff"]
    for (let i = 0; i < Math.min(4, g); i++) o.p(spots[i][0], spots[i][1], cols[(i + (g >= 5 ? s.tw : 0)) % 5])
    if (g >= 5) { o.pic(S.plus, 19, 0, I_X_GOLD); o.p(20, 1, "#ffffff"); if (s.tw % 2) { o.p(18, 0, GLOW, 0.6); o.p(22, 2, GLOW, 0.6) } }
    else if (g >= 4) o.p(20, 1, GOLD)
}
// New Year: a sparkler, and fireworks going up beside it
HELD.sparkler = function (o, s) {
    const f = s.pf + s.tw
    o.line(18, 2, 20, 0, "#8b93ab")
    if (f % 3 === 0) { o.pic(S.plus, 20, -3, I_X_GOLD); o.p(21, -2, "#ffffff") }
    else if (f % 3 === 1) { o.pic(S.dizzy, 20, -3, I_X_GOLD); o.p(21, -2, "#ffffff"); o.p(23, -2, GLOW, 0.7); o.p(19, -2, GLOW, 0.7) }
    else { o.p(21, -2, "#ffffff"); o.p(21, -4, GOLD); o.p(23, -3, GOLD); o.p(19, -1, GOLD); o.p(23, -1, GLOW, 0.6); o.p(19, -4, GLOW, 0.6) }
    o.p(22, 0 + f % 2, GOLD, 0.6); o.p(20, 2 - f % 2, GOLD, 0.4)
}
FRONT.firework = function (o, s) {
    const f = s.pf, c = ["red", "cyan", "yellow", "magenta", "green"][(s.fx.hue || 0) % 5], cx = -3, cy = -5
    if (f < 3) { o.r(cx, 6 - f * 4, 1, 3, GLOW, 0.8); o.p(cx, 9 - f * 4, GOLD, 0.4); return }
    const k = f - 3, r = k === 0 ? 1 : k === 1 ? 2 : 3, a = k < 2 ? 1 : k === 2 ? 0.7 : 0.35
    const dirs = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, 1], [1, -1], [-1, -1]]
    for (let i = 0; i < 8; i++) {
        const d = dirs[i], m = i < 4 ? r : Math.max(1, r - 1)
        o.p(cx + d[0] * m, cy + d[1] * m + (k > 2 ? k - 2 : 0), i % 2 ? c : GLOW, a)
    }
    if (k === 0) o.p(cx, cy, "#ffffff")
}

// ---- after an answer, and while it thinks ----
// fixed: a wrench in the raised hand (w 1: mid-twirl)
HELD.wrench = function (o, s) {
    o.pic(s.fx.w === 1 ? S.wrenchB : S.wrenchA, 17, s.armR === 2 ? -3 : -1, { w: "#b8c0cf", h: "#8d96a8" })
}
// found: a lightbulb (hf 0 off, 1 lit, 2 lit and shining)
OVER.bulb = function (o, s) {
    const f = s.pf
    o.pic(S.bulb, 16, -6, { y: f >= 1 ? GOLD : "#d9d4c7", h: f >= 1 ? GLOW : "#ece8de", g: "#9aa0ae" })
    if (f === 2) { o.p(14, -5, GLOW); o.p(22, -5, GLOW); o.p(14, -3, GLOW, 0.6); o.p(22, -3, GLOW, 0.6); o.p(18, -8, GLOW, 0.6) }
}
// stuck: a sweat drop (hf 1: sliding down), a tangle over its head
OVER.sweat = function (o, s) { o.pic(S.drop, 16, -1 + s.pf, { d: WATER }) }
OVER.scribble = function (o, s) { o.pic(s.pf % 2 ? S.scribbleB : S.scribbleA, 7, -5, { x: "#8b93ab" }) }
// background work running: a thought bubble whose dots come up one by one (hf: how many)
OVER.dots = function (o, s) {
    o.pic(S.cloud, 15, -6, { w: ["cream", 0.92] })
    for (let i = 0; i < Math.min(3, s.pf); i++) o.p(16 + i * 2, -5, "primary")
}
// chatting: a speech bubble with a little heart
OVER.speech = function (o, s) {
    o.pic(S.cloud, 15, -6, { w: ["cream", 0.95] })
    if (s.pf % 2) o.pic(S.heartS, 17, -6, { x: "pink" }); else { o.p(16, -5, "ink", 0.6); o.p(18, -5, "ink", 0.6); o.p(20, -5, "ink", 0.6) }
}
// the Claude spark, the way Claude Code's spinner turns: · ✢ ✳ ✶ ✻ ✽
OVER.spark = function (o, s) {
    const x = s.fx.magic ? 8 : 16, y = s.fx.magic ? -7 : -6
    const show = [[1, 0, 0, 0, 0], [1, 1, 0, 0, 0], [1, 0, 1, 0, 0], [1, 1, 0, 1, 0], [1, 1, 1, 1, 0], [1, 1, 1, 0, 1]][s.pf % 6]
    const dots = [[2, 2, 0], [2, 1, 1], [1, 2, 1], [3, 2, 1], [2, 3, 1], [1, 1, 2], [3, 1, 2], [1, 3, 2], [3, 3, 2],
                  [2, 0, 3], [0, 2, 3], [4, 2, 3], [2, 4, 3], [0, 0, 4], [4, 0, 4], [0, 4, 4], [4, 4, 4]]
    for (let i = 0; i < dots.length; i++) if (show[dots[i][2]]) o.p(x + dots[i][0], y + dots[i][1], "claude", dots[i][2] >= 3 ? 0.75 : 1)
}
OVER.ask = function (o, s) { o.pic(S.ask, 16, -6 - s.pf, { x: "yellow" }) }
OVER.check = function (o, s) { o.pic(s.pf === 0 ? S.check0 : s.pf === 1 ? S.check1 : S.check2, 13, -5, { x: "green" }) }

// ---- for a moment (acts) ----
OVER.heart = function (o, s) {
    const f = s.pf
    if (f >= 5) { o.pic(S.heartS, 11, -7, { x: "pink" }, 0.8); o.pic(S.heartS, 17, -6, { x: "pink" }, 0.6); return }
    o.pic(S.heart, 13, -3 - Math.min(f, 3), { x: "pink" })
}
OVER.hearts = function (o, s) {             // being petted: little ones drifting up
    for (let i = 0; i < 3; i++) {
        const age = s.pf - i * 2
        if (age >= 0 && age < 5) o.pic(S.heartS, [3, 15, 9][i] + (age % 2), -2 - age, { x: "pink" }, age > 3 ? 0.5 : 1)
    }
}
OVER.note = function (o, s) {
    o.pic(S.note, 16 + s.pf % 2, -5 - (s.pf % 3 === 1 ? 1 : 0), { x: "cyan" })
    if (s.fx.duet) o.pic(S.note2, -1 - s.pf % 2, -4 - (s.pf % 3 === 2 ? 1 : 0), { x: "magenta" })
}
OVER.bang = function (o) { o.pic(S.bang, 9, -6, I_X_GOLD) }
OVER.puff = function (o, s) {
    const f = s.pf
    o.pic(f === 0 ? S.puff0 : S.plus, -1 - f, 3 - (f > 0 ? 1 : 0), { x: "#dfe3ec" }, [0.9, 0.7, 0.35][f] || 0)
}
OVER.stars = function (o, s) {
    const ring = [[3, -1], [6, -3], [10, -4], [14, -3], [17, -1], [10, -1]]
    for (let i = 0; i < 3; i++) { const q = ring[(s.pf + i * 2) % 6]; o.p(q[0], q[1], GOLD) }
}
OVER.sparkle = function (o, s) {
    if (s.pf !== 1) o.pic(S.plus, -1, -2, I_X_GLOW)
    if (s.pf !== 0) o.pic(S.plus, 18, -2, I_X_GLOW)
    if (s.pf === 1) o.p(1, -4, GLOW, 0.6)
}
OVER.z = function (o, s) { o.pic(S.zed, 15, -3 - s.pf, I_X_CREAM, 0.85) }
// bubblegum (g 1-3: how big; 4: popped)
OVER.gum = function (o, s) {
    const g = s.fx.g || 0, c = "#ff8fb8"
    if (g === 1) o.r(9, 4, 2, 2, c)
    else if (g === 2) { o.r(8, 3, 4, 4, c); o.p(8, 3, "body"); o.p(11, 3, "body"); o.p(8, 6, "body"); o.p(11, 6, "body"); o.p(9, 4, "#ffd0e2") }
    else if (g === 3) { o.r(7, 1, 6, 6, c); o.r(6, 2, 8, 4, c); o.r(8, 2, 2, 1, "#ffd0e2"); o.p(7, 3, "#ffd0e2") }
    else if (g === 4) { o.p(5, 0, c); o.p(14, 1, c); o.p(4, 5, c); o.p(15, 6, c); o.p(9, -1, c); o.r(8, 4, 3, 1, c); o.p(7, 3, c); o.p(12, 5, c) }
    else if (g === 5) { o.p(8, 4, c); o.p(12, 5, c) }
}
// a balloon that carries it off
HELD.balloon = function (o, s) {
    if (s.fx.g === 9) return
    o.pic(S.balloon, 15, -8, { x: "red", h: "#ffb3bf" }); o.r(17, -2, 1, 4, "cream", 0.6)
}
// a parachute coming down, rocket flames going up
HELD.chute = function (o) {
    o.pic(S.chute, 4, -8, { a: "primary", b: "cream", l: ["cream", 0.6] })
    o.line(4, -4, 5, -1, "cream", 0.6); o.line(15, -4, 14, -1, "cream", 0.6); o.r(9, -4, 1, 4, "cream", 0.4)
}
HELD.jet = function (o, s) { o.pic(s.pf % 2 ? S.jetB : S.jet, 8, 10, { y: GOLD, o: FLAME }) }
HELD.mic = function (o) { o.pic(S.mic, 17, 0, { x: "#c9cdd8", h: GREY }) }
HELD.popper = function (o, s) { o.pic(S.cone, 17, 1, { x: "magenta", y: "yellow" }) }
// confetti flying out of a popper (and whenever there's something to celebrate)
FRONT.burst = function (o, s) {
    const fx = s.fx, f = fx.b !== undefined ? fx.b : s.pf, seed = fx.hue || 0
    const cols = ["magenta", "yellow", "cyan", "green", "red", "primary"]
    const cx = fx.cx !== undefined ? fx.cx : 19, cy = fx.cy !== undefined ? fx.cy : 0, wide = fx.cx !== undefined ? 0.5 : 0.35
    for (let i = 0; i < 16; i++) {
        const vx = (rnd(seed, i, 81) - wide) * 3.2, vy = -1.2 - rnd(seed, i, 82) * 2.2
        const x = Math.round(cx + vx * f), y = Math.round(cy + vy * f + 0.32 * f * f)
        if (y > 10 || f > 9) continue
        o.p(x, y, cols[i % 6], f > 7 ? 0.5 : 1)
    }
}
// levelling up
FRONT.levelup = function (o, s) {
    const f = s.pf, y = f < 1 ? -5 : f < 2 ? -6 : -7, a = f < 1 ? 0.5 : 1, ink = { x: f % 2 ? GOLD : GLOW }
    o.pic(S.L, 2, y, ink, a); o.pic(S.V, 6, y, ink, a); o.pic(S.U, 11, y, ink, a); o.pic(S.P, 15, y, ink, a)
    for (let i = 0; i < 4; i++) {
        const x = [-3, 0, 19, 22][i], yy = 8 - ((f * 2 + i * 3) % 12)
        o.r(x, yy, 1, 3, i % 2 ? "primary" : GOLD, 0.55)
        if ((f + i) % 3 === 0) o.pic(S.up, x - 1, yy - 3, { x: GOLD }, 0.9)
    }
}
// asleep by the hourglass: dreaming of a full battery, a bubble at its nose
OVER.dream = function (o, s) {
    o.p(15, -1, "cream", 0.7); o.r(16, -3, 2, 1, "cream", 0.8)
    o.pic(S.cloud, 15, -8, { w: ["cream", 0.92] }); o.r(16, -9, 5, 1, "cream", 0.92)
    o.r(16, -8, 4, 2, "#3b3f51"); o.p(20, -8, "#3b3f51"); o.r(16, -8, Math.min(4, 1 + s.pf), 2, "green")
}
OVER.snot = function (o, s) {
    const g = s.fx.g || 0, c = ["#bfe3ff", 0.75]
    if (g === 1) o.p(11, 5, c[0], c[1])
    else if (g === 2) o.r(11, 4, 2, 2, c[0], c[1])
    else if (g === 3) { o.pic(S.ringBig, 11, 3, { x: c }); o.p(12, 4, "#ffffff") }
    else if (g === 4) { o.p(10, 3, c[0]); o.p(15, 4, c[0]); o.p(12, 2, c[0]); o.p(14, 7, c[0], 0.6) }
}
// ---- visitors ----
// a butterfly (or, Halloween week, a bat) drops by and perches on its head
FRONT.fly = function (o, s) {
    const q = at([[-3, -2], [0, -4], [3, -5], [6, -4], [8, -2], [8, -2], [8, -2], [11, -4], [14, -6], [17, -7], [20, -8], [23, -9]], s.pf)
    o.pic(s.pf % 2 === 0 || (s.pf >= 4 && s.pf <= 6) ? S.flyOpen : S.flyShut, q[0], q[1] - (s.hat ? 4 : 0) * (s.pf >= 3 && s.pf <= 7 ? 1 : 0), { x: "magenta" })
}
FRONT.bat = function (o, s) {
    const q = at([[-3, -6], [0, -8], [3, -7], [6, -9], [9, -8], [12, -9], [15, -7], [18, -8], [21, -6], [24, -7]], s.pf)
    o.pic(s.pf % 2 === 0 ? S.batOpen : S.batShut, q[0], q[1], { x: "#7a6a99" })
}
// a little bird: lands on its head, hops, sings, flies on
FRONT.bird = function (o, s) {
    const f = s.pf, top = s.hat ? -4 : 0
    const q = at([[-6, -7], [-3, -6], [0, -5], [4, -5], [7, -4 + top], [7, -4 + top], [7, -5 + top], [7, -4 + top], [7, -4 + top],
                  [10, -5 + top], [14, -7], [18, -8], [23, -9]], f)
    const fly = f < 4 || f > 8
    o.pic(fly && f % 2 ? S.birdUp : S.bird, q[0], q[1], { x: "#8ec5ff", y: GOLD })
    if (!fly) o.p(q[0] + 2, q[1], "ink")
}
// seasons passing: a leaf in autumn, petals in spring, a firefly on summer nights, a snowflake to catch
FRONT.leaf = function (o, s) {
    const q = at([[15, -8], [13, -7], [14, -6], [12, -5], [13, -4], [11, -3], [10, -2], [10, -2], [10, -2], [13, -1], [16, 3], [18, 7], [19, 9]], s.pf)
    const top = s.hat && s.pf >= 5 && s.pf <= 8 ? -4 : 0
    o.r(q[0], q[1] + top, 2, 1, "#e2a14b"); o.p(q[0] + (s.pf % 2), q[1] + 1 + top, "#c8734f")
}
FRONT.petal = function (o, s) {
    for (let i = 0; i < 4; i++) {
        const t = s.pf + i * 3, x = 24 - t * 2 + (i % 2), y = -8 + t + (t % 3 === 0 ? 1 : 0) + i
        if (y > 9 || x < -6) continue
        o.p(x, y, "#ffb7d0"); if (t % 2) o.p(x + 1, y, "#ffd9e6", 0.8)
    }
}
FRONT.firefly = function (o, s) {
    const q = at([[22, -2], [20, -4], [17, -5], [13, -6], [9, -5], [5, -6], [2, -4], [0, -2], [-2, -4], [-4, -6]], s.pf)
    if (s.pf % 3 === 2) { o.p(q[0], q[1], "#9aa86a", 0.6); return }
    o.r(q[0] - 1, q[1] - 1, 3, 3, "#d8ff8a", 0.22); o.p(q[0], q[1], "#eaffb0")
}
FRONT.flake = function (o, s) {
    const q = at([[12, -8], [11, -6], [12, -4], [10, -2], [10, 0], [10, 2], [10, 3]], s.pf)
    if (s.pf < 7) { o.p(q[0], q[1], "#ffffff"); if (s.pf < 5) { o.p(q[0] - 1, q[1], "#ffffff", 0.5); o.p(q[0] + 1, q[1], "#ffffff", 0.5) } }
}
// Halloween: a little ghost says boo
FRONT.ghost = function (o, s) {
    const g = s.fx.g || 0, y = [8, 5, 3, 3, 2][Math.min(4, g)], a = g >= 4 ? 0.35 : 0.9
    o.pic(S.ghost, 19, y, { x: ["#f4f7fb", a], e: ["#3b3f51", a] })
    if (g === 2 || g === 3) { o.p(18, y + 2, "#f4f7fb", a); o.p(23, y + 2 - (g === 3 ? 1 : 0), "#f4f7fb", a) }
}
// ---- around it ----
// melted into a puddle (an act)
FRONT.puddle = function (o, s) {
    o.r(6, 6, 8, 1, "hi"); o.r(4, 7, 12, 1, "body"); o.r(2, 8, 16, 1, "body"); o.r(1, 9, 18, 1, "lo")
    o.p(7, 7, "ink"); o.p(12, 7, "ink")
    if (s.pf === 1) { o.p(0, 8, "hi"); o.p(19, 8, "hi") }
}
// dust kicked up by a landing (dust 1: at its feet, 2: drifting off)
FRONT.dust = function (o, s) {
    const k = s.fx.dust, x = s.fx.dx || 0, c = "#dfe3ec"
    if (k === 1) { o.r(1 + x, 9, 2, 1, c, 0.7); o.r(17 + x, 9, 2, 1, c, 0.7); o.p(2 + x, 8, c, 0.5); o.p(17 + x, 8, c, 0.5) }
    else if (k === 2) { o.p(-1 + x, 8, c, 0.4); o.p(0 + x, 9, c, 0.3); o.p(20 + x, 8, c, 0.4); o.p(19 + x, 9, c, 0.3) }
}
// one thing put away and the next brought out, in a puff (zone: where it was and where the next goes)
FRONT.poof = function (o, s) {
    const g = s.fx.g || 0, right = s.fx.zone !== "front", x = right ? 18 : 8, y = right ? 3 : 4, ink = { x: "#e8ecf4" }
    if (g === 0) o.pic(S.poofA, x, y + 1, ink, 0.85)
    else if (g === 1) o.pic(S.poofB, x - 1, y, ink, 0.9)
    else if (g === 2) o.pic(S.poofC, x - 1, y - 1, ink, 0.6)
}

// ---------- the whole picture ----------
const EMPTY = {}
// what is in the picture: [name, shown by this very frame]. A thing the frame names follows the frame's
// `f`; what Clawd just holds follows it only in its own state's acts (`hf`), so a wave or a dance
// doesn't swing the hammer too
function names(s, held) {
    const fx = s.fx, out = []
    const add = (n, own) => {
        if (!n) return
        n = ALIAS[n] || n
        for (let i = 0; i < out.length; i++) if (out[i][0] === n) { out[i][1] = out[i][1] || own; return }
        out.push([n, own])
    }
    add(held, false)
    if (!fx.norest) add(s.rest, false)
    add(fx.prop, true); add(fx.prop2, true); add(fx.prop3, true)
    return out
}
function layer(o, c, list, table) {
    for (let i = 0; i < list.length; i++) {
        const d = table[list[i][0]]
        if (d) { c.pf = list[i][1] ? c.f : c.hf; d(o, c) }
    }
}

function compose(scene) {
    const s = Object.assign({ pf: 0 }, scene)
    const o = new Out(), fx = s.fx || EMPTY
    const held = fx.hold !== undefined ? fx.hold : fx.bare ? "" : s.held
    const list = names(s, held)
    const sh = SHAPES[fx.sh || (s.sitting ? "d" : "n")] || SHAPES.n
    const B = { x: sh[0], y: sh[1], w: sh[2], h: sh[3] }
    const lift = held === "skate" ? -2 : 0
    const dx = fx.dx || 0, dy = (fx.dy || 0) + lift + (s.bob || 0)
    const hidden = !!fx.hide

    // ground shadow, fainter while it's in the air
    const air = Math.max(0, 1 + Math.min(0, (fx.dy || 0) + (s.bob || 0)) / 5)
    if (air > 0.04) o.r(3.5 + dx, 9.75, 13, 0.6, "#000000", (hidden ? 0.12 : 0.22) * air)

    layer(o, s, list, BACK)

    if (!hidden) {
        o.dx = dx; o.dy = dy; o.mir = !!fx.flip; o.rot = ((fx.spin || 0) / 90) & 3
        figure(o, s, B, sh[4], held)
        layer(o, s, list, HELD)
        o.mir = false; o.rot = 0
        layer(o, s, list, OVER)
        // asleep by the hourglass: Zzz, and a bubble at its nose that grows with every breath
        if (s.sitting && s.eyeR === "sleep" && !fx.prop) {
            s.fx = { g: s.zz % 6 }; OVER.snot(o, s); s.fx = fx      // (the snore counts its size)
            const zs = [[12, -2, s.zz % 3 !== 2], [15, -6, s.zz % 3 !== 0]]
            for (let i = 0; i < 2; i++) if (zs[i][2]) {
                const x = zs[i][0], y = zs[i][1]
                o.r(x, y, 4, 1, "cream", 0.85); o.p(x + 2, y + 1, "cream", 0.85); o.p(x + 1, y + 2, "cream", 0.85); o.r(x, y + 3, 4, 1, "cream", 0.85)
            }
        }
    }
    o.still()
    layer(o, s, list, FRONT)
    if (fx.dust) FRONT.dust(o, s)

    // tired: a battery running down (blinks when it's nearly out); the update badge takes its place
    if (s.tired >= 2 && !(s.notice && !s.alert)) {
        const c = s.tired >= 3 ? "#ff6b6b" : "#c9cdd8"
        o.pic(s.tired >= 4 ? S.batteryOut : S.battery, 0, -2, { n: "#c9cdd8", f: c, c: s.tired >= 3 ? "#ff6b6b" : GOLD },
              s.tired >= 3 && !s.lowOn ? 0.25 : 0.9)
    }
    // a window just reset: confetti
    if (s.celebrate) {
        const bits = [[1, -3, "magenta"], [3, -1, "yellow"], [0, 0, "cyan"], [14, -4, "green"], [16, -2, "red"], [19, 1, "primary"], [-2, 3, "tertiary"]]
        for (let i = 0; i < bits.length; i++) if ((i + s.tw) % 4 !== 0) o.p(bits[i][0], bits[i][1] + (i + s.tw) % 2, bits[i][2])
    }
    // a star out at night
    if (s.star && !fx.prop) {
        const c = "yellow_bright"
        o.p(20, -2, c)
        if (s.tw % 3 !== 2) { o.p(20, -3, c, 0.6); o.p(19, -2, c, 0.6); o.p(21, -2, c, 0.6); o.p(20, -1, c, 0.6) }
    }
    // rain (only out under the umbrella) and snow falling around it
    const snow = s.weather === "snow"
    if (snow || (s.weather === "rain" && held === "umbrella")) {
        const drops = [[0, 0], [1, 5], [19, 2], [21, 7], [-1, 9], [23, 4], [-4, 3]]
        for (let i = 0; i < drops.length; i++) {
            const m = drops[i]
            o.r(m[0] + (snow ? (s.wx + m[1]) % 2 : 0), -6 + (m[1] + s.wx * (snow ? 1 : 2)) % 15, 1, snow ? 1 : 2, snow ? "#ffffff" : WATER, 0.7)
        }
    }
    // check-in from Claude: a big "!" badge on top of everything, hopping in steps
    if (s.alert) {
        const y = -s.bounce
        o.r(15.5, -4.4 + y, 6, 8, "#000000", 0.35); o.r(14.5, -3.4 + y, 8, 6, "#000000", 0.35)
        o.r(15, -5 + y, 6, 8, "red"); o.r(14, -4 + y, 8, 6, "red"); o.r(15, -5 + y, 6, 1, "alert_hi")
        o.r(17, -4 + y, 2, 4, "cream"); o.r(17, 1 + y, 2, 1, "cream")
    } else if (s.notice) {
        // an important update waits: a green badge with an arrow up, on the left, still (it isn't urgent)
        o.r(-2.5, -4.4, 5, 7, "#000000", 0.3); o.r(-3.5, -3.4, 7, 5, "#000000", 0.3)
        o.r(-3, -5, 5, 7, "green"); o.r(-4, -4, 7, 5, "green"); o.r(-3, -5, 5, 1, "notice_hi")
        o.pic(S.arrow, -3, -4, I_X_INK)
    }
    return o.l
}

// the display list onto a canvas: `u` logical px per cell, `dpr` device px per logical px. Every edge
// lands on a whole device pixel, so cells stay crisp and equal at any fractional scale.
function paint(ctx, list, inks, u, dpr, width, height) {
    ctx.clearRect(0, 0, width, height)
    const k = u * dpr
    let ink = null, alpha = 1
    ctx.globalAlpha = 1
    for (let i = 0; i < list.length; i += 6) {
        const a = list[i + 5]
        if (a <= 0) continue
        const x0 = Math.round((list[i] - X0) * k), y0 = Math.round((list[i + 1] - Y0) * k)
        const x1 = Math.round((list[i] + list[i + 2] - X0) * k), y1 = Math.round((list[i + 1] + list[i + 3] - Y0) * k)
        if (x1 <= x0 || y1 <= y0) continue
        const c = list[i + 4]
        if (c !== ink) { ink = c; ctx.fillStyle = inks[c] || c }
        if (a !== alpha) { alpha = a; ctx.globalAlpha = a }
        ctx.fillRect(x0 / dpr, y0 / dpr, (x1 - x0) / dpr, (y1 - y0) / dpr)
    }
    ctx.globalAlpha = 1
}

// every prop there is a picture of (the tests check that nothing asks for one that isn't)
function known(name) { name = ALIAS[name] || name; return !!(BACK[name] || HELD[name] || OVER[name] || FRONT[name]) || name === "drop" || name === "music" }
