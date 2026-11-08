pragma Singleton
import QtQuick

// The room's lights, for the whole shell (one object: the status island's button, the control center and
// the Room panel all see the same state at once): the bedside lamp through its bridge (`lamp serve`,
// 127.0.0.1:48723) and the LED strip, the wallpaper sync and whether this PC is home through the Room
// light service (`roomlight serve`, 127.0.0.1:48724). Both are optional: with neither answering, nothing
// of this shows anywhere. Plain XMLHttpRequest (plasmashell spawns nothing); the services refuse a POST
// without their header.
//
// Per service one request at a time, and each slot keeps only its latest wish, so a slider drag can't
// queue up; changes show at once (patch) and polls are ignored for a moment after them, so a stale answer
// can't make a slider jump back. Polled slowly to notice coming home and changes made elsewhere, often
// while a panel shows the lights (watch).
//
//   RoomLight.watch("control/" + screenName, visible)     RoomLight.lampOn, RoomLight.setStrip(true) ...
QtObject {
    id: rl

    // ------------------------------------------------------------------ who's looking
    property var viewers: ({})
    readonly property bool watched: Object.keys(viewers).length > 0
    function watch(key, on) {
        if (!!viewers[key] === !!on) return
        const next = Object.assign({}, viewers)
        if (on) next[key] = true
        else delete next[key]
        viewers = next
        if (on) { refresh(); wake() }       // have the strip's Bluetooth link ready by the first click
    }

    // ------------------------------------------------------------------ the lamp
    property var lamp: null                     // the bridge's last /state answer
    property bool lampLoaded: false
    property string lampProblem: ""             // why it can't be reached; "" when it can
    readonly property bool lampReachable: lampLoaded && lampProblem === ""
    readonly property bool lampOn: !!lamp && lamp.power === true
    readonly property int lampBright: lamp ? lamp.bright : 50
    readonly property string lampMode: lamp ? lamp.mode : "white"     // white, colour, night
    readonly property int lampCt: lamp ? lamp.ct : 2700
    readonly property int lampHue: lamp ? lamp.hue : 0
    readonly property int lampSat: lamp ? lamp.sat : 100
    readonly property string lampRgb: lamp ? lamp.rgb : "#ffffff"
    readonly property string lampScene: lamp ? (lamp.scene || "") : ""
    readonly property string lampFlow: lamp && lamp.flow ? lamp.flow.name : ""
    property string lampSpeed: "normal"         // for the next animation
    readonly property var flowNames: ({ candle: "Candle", breathe: "Breathe", drift: "Colour drift",
                                        sunset: "Sunset", ocean: "Ocean", aurora: "Aurora", other: "Animation" })
    readonly property string lampSummary: {
        if (!lampLoaded) return "Connecting…"
        if (lampProblem) return lampProblem
        if (!lampOn) return "Off"
        if (lampMode === "night") return "Ultra night"
        if (lampFlow) return flowNames[lampFlow] + " · " + lampBright + "%"
        return lampBright + "% · " + (lampMode === "white" ? lampCt + " K" : "colour")
    }

    function lampPatch(fields) { lamp = Object.assign({}, lamp, fields) }
    // a colour, white, scene or animation picked by hand ends the wallpaper sync
    function lampManual() { if (sync.on) setSync({ on: false }) }
    function setLamp(on) {
        if (on && !lampOn && sync.on) syncLamp.restart()    // the sync gives it its colour once it's on
        lampPatch({ power: on })
        lampPost("action", { power: on ? "on" : "off" })
    }
    function setLampBright(v) {
        const level = Math.max(1, Math.min(100, Math.round(v)))
        const flowing = lamp && lamp.flow
        lampPatch({ bright: level, power: true, scene: null, mode: lampMode === "night" ? "white" : lampMode,
                    flow: flowing ? Object.assign({}, lamp.flow, { level: level }) : null })
        lampPost("bright", { bright: level, fade: 200 })
    }
    function setLampCt(kelvin) {
        lampManual()
        lampPatch({ ct: kelvin, mode: "white", power: true, scene: null, flow: null })
        lampPost("colour", { ct: kelvin, fade: 200 })
    }
    function setLampHsv(h, s) {
        lampManual()
        lampPatch({ hue: h, sat: s, rgb: String(Qt.hsva(h / 360, s / 100, 1, 1)), mode: "colour", power: true, scene: null, flow: null })
        lampPost("colour", { hsv: [h, s], fade: 200 })
    }
    function setLampScene(name) {
        lampManual()
        lampPatch({ scene: name, power: true, flow: null, mode: name === "night" ? "night" : "white" })
        lampPost("action", { scene: name })
    }
    function startLampFlow(name) {
        lampManual()
        lampPatch({ flow: { name: name, speed: lampSpeed, level: lampBright }, scene: null, power: true })
        lampPost("action", { flow: name, speed: lampSpeed })
    }
    function stopLampFlow() {
        lampPatch({ flow: null })
        lampPost("action", { stop: true })
    }
    function setLampSpeed(v) {
        lampSpeed = v
        if (lampFlow && lampFlow !== "other") startLampFlow(lampFlow)
    }
    property Timer syncLamp: Timer { interval: 1500; onTriggered: rl.applySync() }

    // ------------------------------------------------------------------ the strip, the sync, home
    property var room: null                     // the service's last /api/state answer
    property bool roomLoaded: false
    property string roomProblem: ""
    readonly property bool roomReachable: roomLoaded && roomProblem === ""
    readonly property bool home: !roomReachable || !room || room.home !== false
    readonly property var strip: room && room.strip ? room.strip
        : ({ on: false, mode: "colour", color: "#ffffff", kelvin: 4000, bright: 80, status: "idle", error: null })
    readonly property var sync: room && room.sync ? room.sync
        : ({ on: false, screen: "theme", vivid: true, screens: [], colours: null, problem: null })
    readonly property bool stripOn: !!strip.on
    readonly property int stripBright: strip.bright || 0
    readonly property bool stripTrouble: strip.status === "error"
    readonly property bool stripBusy: strip.status === "connecting"
    readonly property string stripSummary: {
        if (!roomLoaded) return "Connecting…"
        if (roomProblem) return roomProblem
        if (stripTrouble) return strip.error || "The strip isn't answering."
        if (stripBusy) return "Connecting…"
        if (!stripOn) return "Off"
        return strip.bright + "% · " + (strip.mode === "white" ? strip.kelvin + " K" : "colour")
    }

    function roomPatch(part, fields) {
        const next = Object.assign({}, room || { home: true, strip: strip, sync: sync })
        next[part] = Object.assign({}, next[part], fields)
        room = next
    }
    function setStrip(on) {
        roomPatch("strip", { on: on })
        roomPost("power", "/api/strip", { on: on })
    }
    function setStripBright(v) {
        const level = Math.max(1, Math.min(100, Math.round(v)))
        roomPatch("strip", { bright: level, on: true })
        roomPost("bright", "/api/strip", { bright: level, on: true })
    }
    function setStripColour(hex) {
        roomPatch("strip", { mode: "colour", color: hex, on: true })
        roomPatch("sync", { on: false })
        roomPost("look", "/api/strip", { color: hex, on: true })
    }
    function setStripKelvin(kelvin) {
        roomPatch("strip", { mode: "white", kelvin: kelvin, on: true })
        roomPatch("sync", { on: false })
        roomPost("look", "/api/strip", { kelvin: kelvin, on: true })
    }
    function setStripLook(look) {               // a preset: { color } or { kelvin }, plus { bright }
        const fields = Object.assign({ on: true }, look)
        roomPatch("strip", Object.assign({ mode: look.kelvin ? "white" : "colour" }, fields))
        roomPatch("sync", { on: false })
        delete roomQueue["bright"]
        roomPost("look", "/api/strip", fields)
    }
    function setSync(fields) {
        roomPatch("sync", fields)
        roomPost("sync", "/api/sync", fields)
    }
    function applySync() { roomPost("apply", "/api/sync/apply", {}) }
    function wake() { if (roomReachable && home) roomPost("wake", "/api/wake", {}) }

    // ------------------------------------------------------------------ both
    readonly property bool present: roomReachable ? home : lampReachable        // anything to show
    readonly property bool anyOn: lampOn || stripOn
    function setAll(on) {
        if (lampReachable) setLamp(on)
        if (roomReachable) setStrip(on)
    }
    function nudge(delta) {                     // the wheel: dims (or brightens) what's on
        if (lampOn) setLampBright(lampBright + delta)
        if (stripOn) setStripBright(stripBright + delta)
    }

    // ------------------------------------------------------------------ plumbing
    readonly property string lampBase: "http://127.0.0.1:48723"
    readonly property string roomBase: "http://127.0.0.1:48724"
    property var lampQueue: ({})
    property bool lampSending: false
    property double lampQuiet: 0
    property var roomQueue: ({})
    property bool roomSending: false
    property double roomQuiet: 0

    function lampPost(slot, body) {
        lampQueue[slot] = body
        lampQuiet = Date.now() + 1500
        lampPump()
    }
    function lampPump() {
        if (lampSending) return
        const slot = Object.keys(lampQueue)[0]
        if (slot === undefined) return
        const body = lampQueue[slot]
        delete lampQueue[slot]
        lampSending = true
        request(lampBase, "POST", "/set", "X-Lamp", body, 9000, (ok, data) => {
            lampSending = false
            if (!ok) lampGone()
            else if (Object.keys(lampQueue).length === 0) lampTake(data)
            lampPump()
        })
    }
    function lampTake(data) {
        lampLoaded = true
        if (data.online === false) { lampProblem = data.error || "The lamp isn't answering."; return }
        lampProblem = ""
        lamp = data
        if (data.flow && data.flow.speed) lampSpeed = data.flow.speed
    }
    function lampGone() { lampLoaded = true; lampProblem = "The lamp service isn't running." }

    function roomPost(slot, path, body) {
        roomQueue[slot] = { path: path, body: body }
        roomQuiet = Date.now() + 1500
        roomPump()
    }
    function roomPump() {
        if (roomSending) return
        const slot = Object.keys(roomQueue)[0]
        if (slot === undefined) return
        const job = roomQueue[slot]
        delete roomQueue[slot]
        roomSending = true
        request(roomBase, "POST", job.path, "X-Roomlight", job.body, 8000, (ok, data) => {
            roomSending = false
            if (!ok) roomGone()
            else if (data && Object.keys(roomQueue).length === 0) roomTake(data)
            roomPump()
        })
    }
    function roomTake(data) { roomLoaded = true; roomProblem = ""; room = data }
    function roomGone() { roomLoaded = true; roomProblem = "The Room light service isn't running." }

    // the lamp's bridge asks the lamp itself every time: unwatched, only every fourth round (~40 s)
    property int round: 0
    function refresh() {
        round++
        if (!roomSending && Date.now() >= roomQuiet)
            request(roomBase, "GET", "/api/state", "", null, 8000, (ok, data) => {
                if (roomSending || Date.now() < roomQuiet) return
                if (ok && data) roomTake(data); else roomGone()
            })
        if (home && (watched || round % 4 === 1) && !lampSending && Date.now() >= lampQuiet)
            request(lampBase, "GET", "/state", "", null, 9000, (ok, data) => {
                if (lampSending || Date.now() < lampQuiet) return
                if (ok && data) lampTake(data); else lampGone()
            })
    }
    // a refused value (400) isn't an outage
    function request(base, method, path, header, body, limit, done) {
        const x = new XMLHttpRequest()
        let finished = false
        const guard = guardTimer.createObject(rl, { interval: limit })
        const finish = (ok, data) => {
            if (finished) return
            finished = true
            guard.destroy()
            done(ok, data)
        }
        guard.triggered.connect(() => { x.abort(); finish(false, null) })
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE) return
            if (x.status !== 200) { finish(x.status === 400, null); return }
            try { finish(true, JSON.parse(x.responseText)) } catch (e) { finish(false, null) }
        }
        x.open(method, base + path)
        if (body === null) x.send()
        else {
            x.setRequestHeader("Content-Type", "application/json")
            x.setRequestHeader(header, "1")
            x.send(JSON.stringify(body))
        }
    }
    property Component guardTimer: Component { Timer { running: true } }

    // often while looked at; slowly otherwise, and rarely when neither service is there at all
    property Timer poll: Timer {
        interval: rl.watched ? 2000 : (rl.roomReachable || rl.lampReachable) ? 10000 : 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: rl.refresh()
    }
}
