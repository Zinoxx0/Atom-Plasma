import QtQuick

// The room's lights for the control center: the bedside lamp (`lamp serve`, 127.0.0.1:48723) and the LED
// strip (`roomlight serve`, 127.0.0.1:48724, which also knows whether this PC is home). Plain
// XMLHttpRequest, polled only while `active`; the services refuse a POST without their header.
// (The full controls live in the Room light widget, ~/Projects/personal/roomlight.)
QtObject {
    id: rl
    property bool active: false
    property var lamp: null                     // the lamp's /state
    property var room: null                     // the room's /api/state
    readonly property bool reachable: lamp !== null || room !== null
    readonly property bool home: room ? room.home !== false : lamp !== null
    readonly property bool lampOn: !!lamp && lamp.power === true
    readonly property int lampBright: lamp ? lamp.bright : 50
    readonly property bool stripOn: !!room && !!room.strip && room.strip.on === true
    readonly property int stripBright: room && room.strip ? room.strip.bright : 50

    function request(method, url, header, body, done) {
        const x = new XMLHttpRequest()
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE) return
            if (x.status !== 200) { done(null); return }
            try { done(JSON.parse(x.responseText)) } catch (e) { done(null) }
        }
        x.open(method, url)
        if (body !== null) {
            x.setRequestHeader("Content-Type", "application/json")
            x.setRequestHeader(header, "1")
            x.send(JSON.stringify(body))
        } else {
            x.send()
        }
    }
    function refresh() {
        request("GET", "http://127.0.0.1:48723/state", "", null, d => rl.lamp = d)
        request("GET", "http://127.0.0.1:48724/api/state", "", null, d => rl.room = d)
    }
    function setLamp(on) {
        lamp = Object.assign({}, lamp || {}, { power: on })
        request("POST", "http://127.0.0.1:48723/set", "X-Lamp", { power: on ? "on" : "off" }, d => { if (d) rl.lamp = d })
    }
    function setLampBright(v) {
        const level = Math.max(1, Math.min(100, Math.round(v)))
        lamp = Object.assign({}, lamp || {}, { bright: level, power: true })
        request("POST", "http://127.0.0.1:48723/set", "X-Lamp", { bright: level, fade: 200 }, d => {})
    }
    function setStrip(on) {
        room = Object.assign({}, room || {}, { strip: Object.assign({}, (room || {}).strip || {}, { on: on }) })
        request("POST", "http://127.0.0.1:48724/api/strip", "X-Roomlight", { on: on }, d => { if (d) rl.room = d })
    }
    function setStripBright(v) {
        const level = Math.max(1, Math.min(100, Math.round(v)))
        room = Object.assign({}, room || {}, { strip: Object.assign({}, (room || {}).strip || {}, { bright: level, on: true }) })
        request("POST", "http://127.0.0.1:48724/api/strip", "X-Roomlight", { bright: level, on: true }, d => {})
    }
    property Timer poll: Timer {
        interval: 2500
        repeat: true
        running: rl.active
        triggeredOnStart: true
        onTriggered: rl.refresh()
    }
}
