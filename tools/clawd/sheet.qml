import QtQuick
import QtQuick.Window
import "../../qml/Rice"
import "../../qml/Rice/ClawdActs.js" as Acts

// A contact sheet of Clawd: every frame of an act side by side, every hobby at each stage of its
// project, or every situation, saved as a PNG. For looking at the art while changing it.
//
//   QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl \
//       qml6 tools/clawd/sheet.qml -- <what> <out.png> [px] [seed] [per row]
//
//   <what>   acts:dance,flip,...  (or acts:all, acts:hobbies, acts:work)   each act's frames in a row
//            hobbies  (or hobbies:knit,fish,...)                            each hobby, stage by stage
//            rest  (or rest:<burst>)                                       every hobby between bursts
//            states                                                        the situations
Window {
    id: win
    visible: true; color: "#1a1b26"
    width: 400; height: 300
    readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
    readonly property string what: args[0] || "states"
    readonly property string out: args[1] || "clawd-sheet.png"
    readonly property real cellPx: Number(args[2] || 4)
    readonly property int seed: Number(args[3] || 7)
    readonly property int perRow: Number(args[4] || 0)
    readonly property real cw: 41 * cellPx
    readonly property real ch: 24 * cellPx + 14

    readonly property var workHeld: ({ type: ["typing"], think: ["thinking"], hammer: ["building"], scan: ["reading"], surf: ["web"],
        delegate: ["juggling"], sweep: ["sweeping"], ask: ["waiting"], hail: ["attention"], wait: ["running"], done: ["done"],
        proud: ["done"], fixed: ["fixed"], tighten: ["fixed"], eureka: ["found"], glow: ["found"], oops: ["stuck"], shrug: ["stuck"],
        hello: ["chat"] })
    function hobbyOf(act) { for (const h of Acts.hobbies()) if (Acts.hobby(h).act === act) return h; return "" }

    property var rows: []
    function build() {
        const r = []
        if (what === "states") {
            const cases = [["idle", {}], ["typing", { activity: "typing" }], ["thinking", { activity: "thinking" }], ["building", { activity: "building" }],
                ["reading", { activity: "reading" }], ["web", { activity: "web" }], ["juggling", { activity: "juggling" }], ["sweeping", { activity: "sweeping" }],
                ["attention", { activity: "attention" }], ["waiting", { activity: "waiting" }], ["running", { activity: "running" }], ["done", { activity: "done" }],
                ["fixed", { activity: "fixed" }], ["found", { activity: "found" }], ["stuck", { activity: "stuck" }], ["tired 55", { usage: 55, activity: "typing" }],
                ["tired 80", { usage: 80, activity: "typing" }], ["tired 95", { usage: 95, activity: "idle" }], ["limited", { mood: "limited", usage: 100, sand: 0.5 }],
                ["celebrate", { celebrate: true }], ["alert", { alert: true }], ["notice", { notice: true }], ["night", { daypart: "night" }],
                ["xmas + snow", { season: "xmas", weather: "snow" }], ["halloween", { season: "halloween" }], ["rain", { weather: "rain", hobby: "umbrella" }],
                ["weekend", { weekend: true }], ["music", { music: true, hobby: "music" }], ["music + book", { music: true, hobby: "book" }],
                ["morning", { daypart: "morning" }], ["evening", { daypart: "evening" }], ["warm", { warm: true, activity: "typing" }],
                ["limited, nearly back", { mood: "limited", usage: 100, sand: 0.1, zz: 3 }], ["tired 80, idle", { usage: 80, hobby: "coffee" }]]
            const n = perRow || 8
            for (let i = 0; i < cases.length; i += n)
                r.push({ label: "", cells: cases.slice(i, i + n).map(c => ({ t: c[0], p: Object.assign({ hobby: "yoyo" }, c[1]) })) })
        } else if (what.startsWith("rest")) {
            // every hobby as it sits between bursts, a few bursts in
            const k = what.indexOf(":") > 0 ? Number(what.split(":")[1]) : 2
            const cells = Acts.hobbies().map(h => ({ t: h, p: { hobby: h, prog: Acts.stage(h, seed, k), beatK: k } }))
            const n = perRow || 6
            for (let i = 0; i < cells.length; i += n) r.push({ label: "", cells: cells.slice(i, i + n) })
        } else if (what.startsWith("hobbies")) {
            const only = what.indexOf(":") > 0 ? what.split(":")[1].split(",") : Acts.hobbies()
            for (const h of only) {
                const cells = []
                for (let k = 0; k < 9; k++) cells.push({ t: k === 0 ? h : "burst " + k, p: { hobby: h, prog: Acts.stage(h, seed, k), beatK: k } })
                const n = perRow || 9
                for (let i = 0; i < cells.length; i += n) r.push({ label: i ? "" : h, cells: cells.slice(i, i + n) })
            }
        } else {
            let list = what.replace(/^acts:/, "").split(",")
            if (list[0] === "all") list = Acts.names()
            else if (list[0] === "hobbies") list = Acts.hobbies().map(h => Acts.hobby(h).act)
            else if (list[0] === "work") list = Object.keys(workHeld)
            for (const spec of list) {
                // name[@prog][#seed]
                const m = /^([a-zA-Z0-9]+)(?:@(\d+))?(?:#(\d+))?$/.exec(spec)
                const name = m[1], prog = Number(m[2] || 0), s = Number(m[3] || seed)
                const hobby = hobbyOf(name), work = workHeld[name]
                const env = { prog: prog, k: s, grow: true, hat: "", hands: false, look: 1, tired: 0, zoneFrom: "front", zoneTo: "right", from: "book" }
                const fr = Acts.frames(name, s, env) || []
                let p = prog
                const cells = fr.map((f, i) => {
                    if (f.adv) p += f.adv
                    if (f.set !== undefined) p = f.set
                    const props = { hobby: hobby, prog: p, beatK: s, fx: f, mine: !!(hobby || work), playing: name, wx: i }
                    if (work) props.activity = work[0]
                    if (!hobby && !work) props.activity = "chat"       // (nothing in its hands)
                    return { t: i + "  " + f.d + "ms", p: props }
                })
                const n = perRow || 12
                for (let i = 0; i < cells.length; i += n) r.push({ label: i ? "" : spec, cells: cells.slice(i, i + n) })
            }
        }
        rows = r
    }
    Component.onCompleted: build()

    Column {
        id: sheet
        Repeater {
            model: win.rows
            Row {
                id: line
                required property var modelData
                Text { width: 90; text: line.modelData.label; color: "#c0caf5"; font.pixelSize: 13; font.bold: true; y: win.ch / 2 }
                Repeater {
                    model: line.modelData.cells
                    Item {
                        id: cell
                        required property var modelData
                        width: win.cw; height: win.ch
                        Rectangle { anchors.fill: parent; anchors.margins: 1; color: "#1f2030"; radius: 4 }
                        Text { text: cell.modelData.t; color: "#737aa2"; font.pixelSize: 10; x: 5; y: 3 }
                        Clawd {
                            id: c
                            x: 9 * win.cellPx; y: 12 * win.cellPx + 12
                            px: win.cellPx
                            animate: false; interactive: false; continuous: false
                            activity: "idle"
                            pal: ({})
                            Component.onCompleted: {
                                const p = cell.modelData.p
                                for (const k in p) if (k !== "hobby" && k !== "prog" && k !== "fx") c[k] = p[k]
                                if (p.hobby !== undefined && p.hobby !== "") c.hobby = p.hobby
                                if (p.prog !== undefined) c.prog = p.prog
                                if (p.fx !== undefined) c.fx = p.fx
                            }
                        }
                    }
                }
            }
        }
    }
    Timer {
        interval: 700; running: true
        onTriggered: sheet.grabToImage(r => { r.saveToFile(win.out); console.warn("clawd sheet:", win.out, sheet.width + "x" + sheet.height); Qt.quit() })
    }
}
