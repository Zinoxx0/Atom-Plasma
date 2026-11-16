pragma Singleton
import QtQuick
import Atom.Native

// The rice shell's switchboard: which panel is open, on which screen, and the island it grew from.
// Bar widgets (islands) ask for panels; each screen's host (com.zinoxx.shell) draws them on its sheet.
// plasmashell loads every widget in one QML engine and Atom is imported by URI (QML_IMPORT_PATH), so
// this is one object for all of them. Plain data only crosses here (strings, numbers, plain objects):
// widgets load Rice from their own paths, so their Rice types never match the host's.
//
//   Shell.toggle("calendar", Screen.name, island.globalRect())       Shell.kind, Shell.screen, Shell.anchor
QtObject {
    id: shell

    // what the sheet can show: kind -> the panel's QML (each takes ricePalette, screenName, ui, kind, args)
    readonly property var panels: ({
        calendar: Qt.resolvedUrl("panels/Calendar.qml"),
        control: Qt.resolvedUrl("panels/Control.qml"),
        traymenu: Qt.resolvedUrl("panels/TrayMenu.qml"),
        clipboard: Qt.resolvedUrl("panels/Clipboard.qml"),
        room: Qt.resolvedUrl("panels/Room.qml"),
        stats: Qt.resolvedUrl("panels/Portal.qml"),
        claude: Qt.resolvedUrl("panels/Portal.qml"),
        apps: Qt.resolvedUrl("panels/Portal.qml"),        // the status island's stack of quiet apps
        demo: Qt.resolvedUrl("panels/Demo.qml"),
        demo2: Qt.resolvedUrl("panels/Demo.qml"),
    })

    // the open panel ("" = none), the screen it's on, the island it grew from ({ x, y, width, height },
    // global logical px) and anything the panel was opened with (e.g. the notification group to show)
    property string kind: ""
    property string screen: ""
    property var anchor: null
    property var args: ({})
    readonly property bool busy: kind !== ""
    property bool debug: false              // tests: log every transition (console.warn "ATOM")

    // The bar's islands live on ONE screen at a time; KWin's rice_islands script picks it and fades the bars
    // (kwin/rice_islands), and says so over D-Bus (Atom.Native Bus, topic "bar"): `screen` holds the islands
    // ("" = none, every screen fullscreen), `covered` lists the screens a fullscreen window covers, `pointer`
    // is the pointer's screen. null until KWin has spoken (a bar then counts as shown, as before).
    // Kept apart from Bus.state and changed only when KWin says something new: bound to Bus.state, it was
    // remade on ANY key's change ("cover" too), waking every barShown() on every bar, and the launcher
    // following the pointer (onBarChanged -> Shell.open -> updateCover -> Bus.set) wrote to the state from
    // inside bar's own update: a binding loop.
    readonly property var bar: barState
    property var barState: null
    property Connections barWatch: Connections {
        target: Bus
        function onMessage(topic, data) { if (topic === "bar") shell.takeBar(data) }
    }
    function takeBar(v) {
        const next = v ?? null
        if (JSON.stringify(next) !== JSON.stringify(barState)) barState = next
    }
    Component.onCompleted: takeBar(Bus.get("bar"))
    function barShown(screenName) { return !bar || bar.screen === screenName }
    // the screen the shell's things open on (the launcher, the clipboard, notification cards): where the
    // islands are, else the active window's screen, else `fallback`
    function home(fallback) { return (bar && bar.screen) || Windows.activeScreen || fallback || "" }
    onBarChanged: if (debug) console.warn("ATOM bar", JSON.stringify(bar))
    // one set of pins on every bar (Glimpse): the last list a bar changed to, the others follow
    property var pins: null
    // the system stats' last three minutes (sysstats), handed from bar to bar as the islands move
    property var stats: null
    function logIsland(key, r) {
        const parts = key.split("/")
        console.warn("ATOM island", parts[1], "at", Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2), "on", parts[0])
    }
    onDebugChanged: if (debug) for (const key in islands) logIsland(key, islands[key])
    // The screens the shell's own full-screen surfaces cover: the launcher's (not its search-only finder, which
    // leaves the screen be). KWin's rice_islands script reads it (Bus Peek "cover") as it does a fullscreen
    // window: the bar's islands get out of the way, to another screen, as they do for a game.
    function updateCover() {
        const home = kind === "launcher" ? { screen: screen, args: args } : under && under.kind === "launcher" ? under : null
        const on = home && home.screen && !(home.args && home.args.searchOnly)
        const next = on ? [home.screen] : []
        const now = Bus.get("cover")
        if (JSON.stringify(now ? now.screens : []) !== JSON.stringify(next)) Bus.set("cover", { screens: next })
    }
    onScreenChanged: updateCover()
    onArgsChanged: updateCover()
    onKindChanged: {
        updateCover()
        if (debug) console.warn("ATOM shell kind", JSON.stringify(kind), "screen", screen, Date.now() % 100000)
        // a game controller drives the full-screen ones as the keyboard does (Atom.Native Gamepad: read only
        // while one of them is open, never while a game is)
        Gamepad.active = kind === "launcher" || kind === "power"
    }

    // the click that closed a panel (the sheet lost focus to the bar) must not open it again
    property string closedKind: ""
    property string closedScreen: ""
    property double closedAt: 0

    // A surface kept open beneath the current one: the launcher under the power page opened from it (its power
    // button). Dismissing the power page returns to it, as it was; an action run (close(k, true)) closes both.
    property var under: null                // { kind, screen, args } or null
    function open(k, scr, anchorRect, a) {
        hoverWait.stop()
        // kind last: it's the one hosts react to, the rest is read then. The screen just before it: a
        // panel moving to another screen (the launcher follows the pointer) keeps its kind, so the new
        // screen's host reacts to the screen and must find the anchor and args already there
        if (k === "power" && kind === "launcher" && (scr || "") === screen && !(args && args.searchOnly))
            under = { kind: kind, screen: screen, args: args }      // (first: the launcher never sees itself go)
        else if (k !== kind) under = null
        anchor = anchorRect || null
        args = a || ({})
        screen = scr || ""
        kind = k
    }
    function close(k, all) {
        if (k && k !== kind) return
        hoverWait.stop()
        if (kind) {
            closedKind = kind
            closedScreen = screen
            closedAt = Date.now()
        }
        const u = under
        if (u && !all) {        // back to what was beneath (kind before `under` goes: it never looks closed)
            anchor = null
            args = u.args
            screen = u.screen
            kind = u.kind
            under = null
            return
        }
        under = null
        kind = ""
    }
    function toggle(k, scr, anchorRect, a) {
        if (debug) console.warn("ATOM toggle", k, "open:", kind, "closed", Date.now() - closedAt, "ms ago:", closedKind)
        if (kind === k && screen === scr) { close(); return }
        if (closedKind === k && closedScreen === scr && Date.now() - closedAt < 300) return
        open(k, scr, anchorRect, a)
    }
    // while a panel is open, pointing at another island on the same screen moves the sheet there
    // (menu-bar style) once the pointer rests on it a moment: crossing islands on the way to another one
    // (or off the bar) no longer flicks through their panels. Islands call unhover when the pointer leaves.
    // The launcher, fullscreen, never follows the pointer.
    function hover(k, scr, anchorRect, a) {
        if (!kind || (kind in solo) || (k in solo) || kind === k || screen !== scr) { hoverWait.stop(); return }
        hoverNext = { k: k, scr: scr, anchor: anchorRect, args: a }
        hoverWait.restart()
    }
    function unhover(k, scr) {
        const n = hoverNext
        if (hoverWait.running && n && n.k === k && n.scr === scr) hoverWait.stop()
    }
    property var hoverNext: null            // { k, scr, anchor, args } of the island the pointer rests on
    property Timer hoverWait: Timer {
        interval: 70
        onTriggered: {
            const n = shell.hoverNext
            if (n && shell.kind && !(shell.kind in shell.solo) && shell.kind !== n.k && shell.screen === n.scr)
                shell.open(n.k, n.scr, n.anchor, n.args)
        }
    }
    // kinds that never follow the pointer (and never open by it): their own surfaces, not the sheet
    readonly property var solo: ({ launcher: true, power: true })

    // portals: a bar widget whose popup content is its own (its data lives there) registers it here, per
    // screen; panels/Portal.qml makes it on the sheet, in the widget's own context
    property var portals: ({})
    function portal(scr, k, component) {
        if (!scr || !k) return
        const next = Object.assign({}, portals)
        next[scr + "/" + k] = component
        portals = next
    }

    // islands on the bars, so a host can grow something out of one without being asked (a notification
    // out of the status island): key "<screen>/<kind>" -> { x, y, width, height } (global logical px)
    property var islands: ({})
    function place(k, scr, r) {
        const key = scr + "/" + k
        const old = islands[key]
        if (old && old.x === r.x && old.y === r.y && old.width === r.width && old.height === r.height) return
        const next = Object.assign({}, islands)
        next[key] = { x: r.x, y: r.y, width: r.width, height: r.height }
        islands = next
        if (debug) logIsland(key, r)
    }
    function forget(k, scr) {
        const key = scr + "/" + k
        if (!(key in islands)) return
        const next = Object.assign({}, islands)
        delete next[key]
        islands = next
    }
    function island(k, scr) { return islands[scr + "/" + k] ?? null }

    // an item's rect in global logical px (x, y: a point of the item's own; width, height: passed through).
    // Not mapToGlobal: that adds Qt's idea of the window's global position, which can go stale for a bar
    // (2026-11-16, a monitor coming back after a power cut moved the 1440p from x 0 to 2400 and its bar's items
    // still mapped as if at 0: the roof Clawd stood on the 4K). The item's place in its window plus the
    // window's offset in its own screen, clamped to that screen (a bar filling the width sits at 0).
    function rectOf(item, x, y, width, height) {
        const win = item.Window.window, s = win ? win.screen : null
        if (!s) { const g = item.mapToGlobal(x, y); return { x: g.x, y: g.y, width: width, height: height } }
        const p = item.mapToItem(null, x, y)
        const inside = (v, room) => Math.max(0, Math.min(v, Math.max(0, room)))
        return { x: s.virtualX + inside(win.x - s.virtualX, s.width - win.width) + p.x,
                 y: s.virtualY + inside(win.y - s.virtualY, s.height - win.height) + p.y, width: width, height: height }
    }
}
