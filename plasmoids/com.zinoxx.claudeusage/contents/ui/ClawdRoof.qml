import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import Atom.Native
import "Rice"

// Clawd's roof (main.qml, "one Clawd, three places"): a small transparent layer surface over the Claude
// island and the space above it. When nothing covers that space Clawd stands there, on the island's roof,
// bigger; this window also carries the jumps between the island, the roof and the popup.
// Layer TOP: above the bar (a dock) and the windows, so it must step aside the moment a window comes over
// the roof (main.qml does: Windows.occupied). Only Clawd takes the pointer (InputMask).
Window {
    id: win
    required property var w                 // the widget's root
    property var scr: null                  // the bar's Qt screen
    readonly property Item mini: w.compactRepresentationItem ? w.compactRepresentationItem.clawd : null
    readonly property alias clawd: clawd

    screen: scr
    x: scr ? scr.virtualX : 0               // keep Qt's idea of the position on this screen,
    y: scr ? scr.virtualY : 0               // or it re-homes the window to another one
    onScreenChanged: if (scr && screen?.name !== scr.name) screen = scr
    transientParent: null
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
    width: Math.max(1, Math.ceil(w.roofWinW))
    height: Math.max(1, Math.ceil(w.roofWinH))
    LayerShell.Window.scope: "dock"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft
    LayerShell.Window.margins: ({ left: Math.round(w.roofWinX), top: 0, right: 0, bottom: 0 })
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.activateOnShow: false
    LayerShell.Window.wantsToBeOnActiveScreen: false

    // mapped while its bar is the one showing (kwin/rice_islands) and the screen isn't the launcher's; it
    // fades with the bar, so the roof Clawd leaves and arrives with the islands
    // (never before its screen is known: a layer surface stays on the output it was mapped on)
    readonly property bool wanted: !!scr && w.barSeen && !w.screenBusy && w.islandH > 0
    onScrChanged: if (visible) { visible = false; Qt.callLater(() => { visible = Qt.binding(() => wanted || shown > 0) }) }
    property real shown: wanted ? 1 : 0
    Behavior on shown { NumberAnimation { duration: Tokens.ms(win.wanted ? 400 : 200); easing.type: Easing.BezierSpline; easing.bezierCurve: win.wanted ? Tokens.calmIn : Tokens.calmOut } }
    visible: wanted || shown > 0

    readonly property real dpr: win.devicePixelRatio || 1
    function snap(v) { return Math.round(v * dpr) / dpr }

    InputMask {
        window: win
        shapes: w.place === "roof" && clawd.opacity > 0.5 && !flight.running
            ? [{ x: clawd.x, y: clawd.y, width: clawd.width, height: clawd.height, radius: 0 }] : []
    }

    // where Clawd rests on the roof (window coordinates): centred, its feet on the island's top edge
    readonly property real restX: snap((width - clawd.width) / 2)
    readonly property real restY: snap(height - w.islandH - clawd.height)

    Item {
        anchors.fill: parent
        opacity: win.shown
        Clawd {
            id: clawd
            x: win.restX
            y: win.restY
            opacity: 0
            px: w.roofPx
            continuous: false
            mood: w.mood
            usage: w.peak
            working: w.working
            activity: w.activity
            celebrate: w.celebrate
            warm: w.warm
            daypart: w.daypart
            weekend: w.weekend
            season: w.season
            sand: w.sand
            alert: w.asking
            notice: w.updating
            music: w.musicOn
            weather: w.sky
            pal: w.palValues
            animate: w.place === "roof" && win.wanted
            hovered: !!w.compactRepresentationItem && w.compactRepresentationItem.containsMouse
            onAlertClicked: w.openPanel()
            onSummoned: w.summonClaude()
            transform: [
                Scale { id: sc; origin.x: clawd.width / 2; origin.y: clawd.height; xScale: sc.k; yScale: sc.k; property real k: 1 },
                Translate { id: tr }
            ]
        }
    }

    // ------------------------------------------------------------------ the jumps
    // mini's spot (its feet, bottom centre) in this window's coordinates, and the scale that matches it
    function miniFeet() {
        if (!mini || !scr) return { x: restX + clawd.width / 2, y: height }
        const g = mini.mapToGlobal(mini.width / 2, mini.height)
        return { x: g.x - (scr.virtualX + Math.round(w.roofWinX)), y: g.y - (scr.virtualY + scr.height - height) }
    }
    readonly property real miniK: w.roofPx > 0 ? (2 * w.uiScale) / w.roofPx : 1
    function fromMini() {
        const f = miniFeet()
        return { x: f.x - (restX + clawd.width / 2), y: f.y - (restY + clawd.height) }
    }
    property real fx: 0                     // a flight's far end: offset and scale
    property real fy: 0
    property real fk: 1
    property real arc: 0                                                // 0..1 along it
    property bool towardRoof: true
    readonly property real hopH: snap(clawd.height * 0.55)
    // the arc: from the far end to the rest spot (towardRoof) or back, rising above the roof on the way
    function along(t) {
        const a = towardRoof ? 1 - t : t                 // 1 = at the far end, 0 = at rest
        tr.x = fx * a
        tr.y = fy * a - hopH * 4 * t * (1 - t)
        sc.k = fk + (1 - fk) * (1 - a)
    }
    onArcChanged: along(arc)
    SequentialAnimation {
        id: flight
        property bool down: false
        ScriptAction { script: { clawd.opacity = 1; if (!flight.down) w.miniOpacity = 0 } }
        NumberAnimation { target: win; property: "arc"; from: 0; to: 1; duration: Tokens.ms(560); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove }
        ScriptAction { script: { if (flight.down) { w.miniOpacity = 1; clawd.opacity = 0 } else clawd.hop(); win.rest(!flight.down) } }
    }
    SequentialAnimation {
        id: leaving         // up and away: into the popup
        ParallelAnimation {
            NumberAnimation { target: tr; property: "y"; to: -win.hopH; duration: Tokens.ms(240); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmOut }
            NumberAnimation { target: clawd; property: "opacity"; to: 0; duration: Tokens.ms(240); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmOut }
        }
        ScriptAction { script: win.rest(false) }
    }
    SequentialAnimation {
        id: arriving        // back from the popup: drops onto the roof
        ScriptAction { script: { sc.k = 1; tr.x = 0; tr.y = -win.hopH; clawd.opacity = 0 } }
        PauseAnimation { duration: Tokens.ms(120) }
        ParallelAnimation {
            NumberAnimation { target: tr; property: "y"; to: 0; duration: Tokens.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn }
            NumberAnimation { target: clawd; property: "opacity"; to: 1; duration: Tokens.ms(260) }
        }
        ScriptAction { script: clawd.hop() }
    }
    function stopAll() { flight.stop(); leaving.stop(); arriving.stop() }
    function rest(on) { tr.x = 0; tr.y = 0; sc.k = 1; clawd.opacity = on ? 1 : 0 }
    function up() {         // island -> roof
        stopAll()
        const d = fromMini()
        fx = d.x; fy = d.y; fk = miniK; towardRoof = true; arc = 0; along(0)
        flight.down = false
        flight.start()
    }
    function down() {       // roof -> island
        stopAll()
        const d = fromMini()
        fx = d.x; fy = d.y; fk = miniK; towardRoof = false; arc = 0; along(0)
        flight.down = true
        flight.start()
    }
    function leave() { stopAll(); leaving.start() }
    function arrive() { stopAll(); arriving.start() }
}
