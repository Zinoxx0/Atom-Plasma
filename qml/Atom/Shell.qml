pragma Singleton
import QtQuick

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
        stats: Qt.resolvedUrl("panels/Portal.qml"),
        claude: Qt.resolvedUrl("panels/Portal.qml"),
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
    function logIsland(key, r) {
        const parts = key.split("/")
        console.warn("ATOM island", parts[1], "at", Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2), "on", parts[0])
    }
    onDebugChanged: if (debug) for (const key in islands) logIsland(key, islands[key])
    onKindChanged: if (debug) console.warn("ATOM shell kind", JSON.stringify(kind), "screen", screen, Date.now() % 100000)

    // the click that closed a panel (the sheet lost focus to the bar) must not open it again
    property string closedKind: ""
    property string closedScreen: ""
    property double closedAt: 0

    function open(k, scr, anchorRect, a) {
        // kind last: it's the one hosts react to, the rest is read then
        screen = scr || ""
        anchor = anchorRect || null
        args = a || ({})
        kind = k
    }
    function close(k) {
        if (k && k !== kind) return
        if (kind) {
            closedKind = kind
            closedScreen = screen
            closedAt = Date.now()
        }
        kind = ""
    }
    function toggle(k, scr, anchorRect, a) {
        if (debug) console.warn("ATOM toggle", k, "open:", kind, "closed", Date.now() - closedAt, "ms ago:", closedKind)
        if (kind === k && screen === scr) { close(); return }
        if (closedKind === k && closedScreen === scr && Date.now() - closedAt < 300) return
        open(k, scr, anchorRect, a)
    }
    // while a panel is open, pointing at another island on the same screen moves the sheet there
    // (menu-bar style); the launcher, fullscreen, never follows the pointer
    function hover(k, scr, anchorRect, a) {
        if (kind && !(kind in solo) && !(k in solo) && kind !== k && screen === scr) open(k, scr, anchorRect, a)
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
}
