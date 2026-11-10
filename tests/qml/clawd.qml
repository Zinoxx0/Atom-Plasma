import QtQuick
import QtQuick.Window
import "../../qml/Rice"
import "../../qml/Rice/ClawdArt.js" as Art
import "../../qml/Rice/ClawdActs.js" as Acts

// Clawd, run offscreen (tests/test_clawd.py reads the "clawd ok ..." / "clawd FAIL ..." lines):
// every act and every hobby has frames and a picture, the hobbies' projects move on the way the
// clock says, two views agree with each other, a click reaches the other view, and it only repaints
// when its picture changed.
Window {
    id: win
    width: 600; height: 300; visible: true; color: "#1a1b26"
    property int failed: 0
    function ok(what) { console.warn("clawd ok " + what) }
    function fail(what) { failed++; console.warn("clawd FAIL " + what) }
    function check(cond, what) { if (cond) ok(what); else fail(what) }

    // two views of it, with nothing in their hands (a chat: no hobby, no loop)
    Clawd { id: a; x: 100; y: 150; px: 3; continuous: false; activity: "chat" }
    Clawd { id: b; x: 350; y: 150; px: 3; continuous: false; activity: "chat" }
    property var heard: []
    Connections { target: b; function onPlayingChanged() { if (b.playing) win.heard = win.heard.concat([b.playing]) } }

    function scene(fx, more) {
        return Object.assign({ fx: fx, f: fx.f || 0, hf: fx.f || 0, held: "", rest: "", hat: "", shades: false, star: false, cans: false,
            eyeL: fx.eyeL || fx.eyes || "open", eyeR: fx.eyeR || fx.eyes || "open", armL: fx.armL === undefined ? 0 : fx.armL,
            armR: fx.armR === undefined ? 0 : fx.armR, mouth: fx.mouth || "", blush: !!fx.blush, gaze: fx.glance || 0,
            sitting: false, tired: 0, weather: "", celebrate: false, alert: false, notice: false, tw: 0, zz: 0, typed: 0, bounce: 0,
            lowOn: true, sand: 0.5, prog: 0, wx: 0, bob: 0, slot: 1 }, more || {})
    }
    function heldFor(act) {
        for (const h of Acts.hobbies()) if (Acts.hobby(h).act === act) return h === "coffee" ? "mug" : h
        return ({ type: "laptop", think: "laptop", hammer: "hammer", scan: "magnifier", surf: "globe", delegate: "balls",
                  sweep: "broom", fixed: "wrench", tighten: "wrench" })[act] || ""
    }

    function acts() {
        let bad = 0, frames = 0
        for (const name of Acts.names()) for (let seed = 0; seed < 10; seed++) for (const prog of [0, 2, 3, 4, 5, 7]) {
            const env = { prog: prog, k: seed, grow: seed % 2 === 0, hat: seed % 3 ? "" : "party", look: 1, zoneFrom: "front", zoneTo: "right", from: "book" }
            let list
            try { list = Acts.frames(name, seed, env) } catch (e) { bad++; fail("act " + name + " throws: " + e); continue }
            if (!list || !list.length) { bad++; fail("act " + name + " has no frames"); continue }
            for (const fr of list) {
                frames++
                if (!(fr.d > 0)) { bad++; fail("act " + name + ": a frame with no duration") }
                for (const p of [fr.prop, fr.prop2, fr.prop3, fr.hold]) if (p && !Art.known(p)) { bad++; fail("act " + name + " shows '" + p + "', which has no picture") }
                try {
                    const cells = Art.compose(scene(fr, { held: heldFor(name), prog: prog, hat: env.hat, slot: seed }))
                    for (let i = 0; i < cells.length; i += 6) {
                        if (!(isFinite(cells[i]) && isFinite(cells[i + 1]) && cells[i + 2] > 0 && cells[i + 3] > 0 && typeof cells[i + 4] === "string" && isFinite(cells[i + 5])))
                            { bad++; fail("act " + name + ": a cell that can't be drawn: " + cells.slice(i, i + 6)); break }
                        // a colour is "#rrggbb" or one of the view's inks
                        const ink = cells[i + 4]
                        if (!/^#[0-9a-f]{6}$/i.test(ink) && a.inks[ink] === undefined) { bad++; fail("act " + name + ": no ink called '" + ink + "'"); break }
                    }
                } catch (e) { bad++; fail("act " + name + " can't be drawn: " + e) }
            }
        }
        if (!bad) ok("acts " + Acts.names().length + " frames " + frames)
    }
    function hobbies() {
        let bad = 0
        for (const daypart of ["morning", "day", "evening", "night"]) for (const season of ["", "halloween", "xmas", "newyear"])
            for (const weather of ["", "rain", "snow"]) for (const tired of [0, 2]) for (const music of [false, true]) {
                const c = { daypart: daypart, season: season, weather: weather, tired: tired, music: music, weekend: season === "" }
                for (const h of Acts.pool(c)) {
                    const d = Acts.hobby(h)
                    if (!d || !d.text || !Acts.frames(d.act, 1, { prog: 0, k: 0 })) { bad++; fail("hobby " + h + " is missing its act or text") }
                    else if (!Art.known(h === "coffee" ? "mug" : h)) { bad++; fail("hobby " + h + " has no picture") }
                }
                // never the same one twice running, and the same answer whoever asks
                let last = ""
                for (let slot = 5000; slot < 5120; slot++) {
                    const h = Acts.hobbyFor(slot, c)
                    if (h === last) { bad++; fail("hobby " + h + " twice running (" + JSON.stringify(c) + ")"); break }
                    last = h
                }
            }
        // a project is where the clock says it is, and its burst takes it to where the next one starts
        for (const h of Acts.hobbies()) for (const slot of [3, 17]) for (let k = 0; k < 40; k++) {
            let p = Acts.stage(h, slot, k)
            for (const fr of Acts.frames(Acts.hobby(h).act, slot * 1000 + k, { prog: p, k: k, grow: Acts.grows(slot, k), hat: "" })) {
                if (fr.adv) p += fr.adv
                if (fr.set !== undefined) p = fr.set
            }
            if (p !== Acts.stage(h, slot, k + 1)) { bad++; fail("hobby " + h + ": burst " + k + " leaves it at " + p + ", the next starts at " + Acts.stage(h, slot, k + 1)); break }
        }
        if (!bad) ok("hobbies " + Acts.hobbies().length)
    }

    property int step: 0
    property int paintsBefore: 0
    Timer {
        id: seq
        interval: 300; running: true; repeat: true
        onTriggered: {
            switch (win.step++) {
            case 0:
                win.acts(); win.hobbies()
                win.check(a.paints > 0 && a.cells.length > 0, "painted")
                win.check(a.hobby !== "" && a.hobby === b.hobby && a.prog === b.prog && a.hobbyText !== "", "two views, one hobby")
                // an act with chance in it goes the same way in both
                a.play("type", 2, 7); b.play("type", 2, 7)
                win.check(a.playing === "type" && JSON.stringify(a.frames) === JSON.stringify(b.frames), "two views, one act")
                a.playing = ""; a.prio = 0; a.fx = a.still; b.playing = ""; b.prio = 0; b.fx = b.still
                a.play("hop", 1)
                break
            case 4:
                win.check(a.playing === "" && Object.keys(a.fx).length === 0 && a.paints > 2, "a hop, and back at rest")
                // nothing twinkles in this picture: a tick of the twinkle clock mustn't repaint it
                win.paintsBefore = a.paints
                a.twinkle++
                break
            case 5:
                win.check(a.paints === win.paintsBefore, "no repaint without a change")
                a.greet()
                win.check(a.playing !== "" && a.prio === 1, "greets on hover")
                // four quick clicks (a third of a second apart): dizzy, here and in the other view
                a.poke()
                win.check(a.prio === 2, "a click plays an act")
                break
            case 6: a.poke(); break
            case 7: a.poke(); break
            case 8:
                a.poke()
                win.check(a.playing === "dizzy" && a.prio === 3, "four clicks make it dizzy")
                break
            case 13:
                win.check(win.heard.indexOf("dizzy") >= 0, "a click reaches the other view (" + win.heard.join(",") + ")")
                // a hobby, then work: it holds what it should
                a.pinned = "knit"; a.activity = "idle"
                win.check(a.held === "knit" && a.twoHands && a.hobbyText === "Knitting a scarf." && a.loopAct === "knit", "a pinned hobby")
                a.activity = "building"
                win.check(a.held === "hammer" && a.loopAct === "hammer", "at work")
                a.mood = "limited"
                win.check(a.sitting && a.held === "hourglass" && a.loopAct === "snore" && a.tired === 4, "out of energy")
                a.animate = false
                win.check(!a.live, "paused")
                break
            case 14:
                console.warn("clawd done " + win.failed)
                Qt.quit()
            }
        }
    }
}
