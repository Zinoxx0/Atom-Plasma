import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import Atom
import Atom.Native
import Rice

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
    // The size it should have, put back by hand if the platform changes it: layer-shell-qt applies a
    // compositor configure (answering an older size request, e.g. the one made as it maps) to the window
    // behind the binding's back, and the binding, its inputs unchanged, never re-applies (2026-11-16: the
    // laptop's roof stuck at 112 px of its 215, Clawd standing outside it: he jumped into nothing).
    readonly property int wantW: Math.max(1, Math.ceil(w.roofWinW))
    readonly property int wantH: Math.max(1, Math.ceil(w.roofWinH))
    width: wantW
    height: wantH
    readonly property bool sizeOff: Math.abs(width - wantW) > 1 || Math.abs(height - wantH) > 1
    property int resizes: 0                 // tries since the wanted size last changed (no endless tug of war)
    onWantWChanged: resizes = 0
    onWantHChanged: resizes = 0
    onSizeOffChanged: if (sizeOff && visible) resync.restart()
    onVisibleChanged: if (sizeOff && visible) resync.restart()
    Timer {
        id: resync
        interval: 120                       // (lets a configure already on its way land first)
        onTriggered: {
            if (!win.sizeOff || !win.visible || win.resizes >= 3) return
            win.resizes++
            console.warn("ClawdRoof: the window is", win.width, "x", win.height, "instead of", win.wantW, "x", win.wantH, "- resizing it")
            win.width = Qt.binding(() => win.wantW)
            win.height = Qt.binding(() => win.wantH)
        }
    }
    LayerShell.Window.scope: "dock"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft
    LayerShell.Window.margins: ({ left: Math.round(w.roofWinX), top: 0, right: 0, bottom: 0 })
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.activateOnShow: false
    LayerShell.Window.wantsToBeOnActiveScreen: false

    // mapped while its bar is the one showing (kwin/rice_islands) and the screen isn't the launcher's; it
    // fades with the bar (kwin/rice_islands: fadeIn, fadeOut), so the roof Clawd leaves and arrives with the islands
    // (never before its screen is known: a layer surface stays on the output it was mapped on)
    // (and never before the island is measured: islandH comes last, islandW is checked too)
    readonly property bool wanted: !!scr && w.moduleOn && w.roofAllowed && w.barSeen && !w.screenBusy && w.islandH > 0 && w.islandW > 0
    onScrChanged: if (visible) { visible = false; Qt.callLater(() => { visible = Qt.binding(() => !w.screenBusy && (wanted || shown > 0)) }) }
    property real shown: wanted ? 1 : 0
    Behavior on shown { enabled: !w.screenBusy; NumberAnimation { duration: Tokens.ms(win.wanted ? 180 : 120); easing.type: Easing.BezierSpline; easing.bezierCurve: win.wanted ? Tokens.calmIn : Tokens.calmOut } }
    visible: !w.screenBusy && (wanted || shown > 0)

    readonly property real dpr: win.devicePixelRatio || 1
    function snap(v) { return Math.round(v * dpr) / dpr }

    InputMask {
        window: win
        shapes: w.place === "roof" && clawd.opacity > 0.5 && !flight.running
            ? [{ x: clawd.x, y: clawd.y, width: clawd.width, height: clawd.height, radius: 0 }] : []
    }

    // where Clawd rests on the roof (window coordinates): over the middle of the rings, its feet on the
    // island's top edge
    readonly property real restX: snap(w.roofCx - w.roofWinX - clawd.width / 2)
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
        const g = Shell.rectOf(mini, mini.width / 2, mini.height, 0, 0)
        return { x: g.x - (scr.virtualX + Math.round(w.roofWinX)), y: g.y - (scr.virtualY + scr.height - height) }
    }
    readonly property real miniK: w.roofPx > 0 ? w.seatPx / w.roofPx : 1
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
    // A jump, not a glide: Clawd crouches where he is (crouchMs), flies a ballistic arc (straight in time,
    // a parabola up and down: quick off the ground, hanging at the top, quick into the landing) and lands
    // with a squash and a puff of dust. His poses (Clawd's act "leap") get the arc's own timings, so the push
    // off, the tuck, the dangle and the touchdown fall on their part of the flight. (It used to glide on
    // an in-out curve and only then hop on the spot: carried up, then the jump.)
    readonly property int crouchMs: Tokens.ms(110)
    readonly property int airMs: Tokens.ms(460)
    readonly property int landMs: Tokens.ms(160)                        // the touchdown's two poses
    property real lift: 0                   // the arc's bow (the parabola's 4·lift·t(1-t))
    // the bow that peaks `apex` px over the higher end (the roof), with the far end `fy` px lower:
    // y(t) = fy·t - 4·lift·t(1-t) (or mirrored) has its top at fy - (fy + 4·lift)² / (16·lift)
    function bowFor(apex) {
        const d = Math.max(0, fy), b = 8 * d + 16 * apex
        return Math.max(apex, (b + Math.sqrt(Math.max(0, b * b - 64 * d * d))) / 32)
    }
    // when it reaches the top, 0..1 along the flight
    function topAt() {
        const t = (Math.max(0, fy) + 4 * lift) / (8 * lift)
        return Math.max(0.2, Math.min(0.8, towardRoof ? t : 1 - t))
    }
    // the arc: from the far end to the rest spot (towardRoof) or back
    function along(t) {
        const a = towardRoof ? 1 - t : t                 // 1 = at the far end, 0 = at rest
        tr.x = fx * a
        tr.y = fy * a - lift * 4 * t * (1 - t)
        sc.k = fk + (1 - fk) * (1 - a)
    }
    onArcChanged: along(arc)
    function leap() {
        const top = topAt()
        clawd.play("leap", 4, 0, false, { crouch: crouchMs, up: Math.round(airMs * top), down: Math.round(airMs * (1 - top)) })
    }
    SequentialAnimation {
        id: flight
        property bool down: false
        ScriptAction { script: { clawd.opacity = 1; if (!flight.down) w.miniOpacity = 0; win.leap() } }
        PauseAnimation { duration: win.crouchMs }
        NumberAnimation { target: win; property: "arc"; from: 0; to: 1; duration: win.airMs; easing.type: Easing.Linear }
        // up: he's home (the touchdown plays on); down: the touchdown first, then the island's Clawd takes over
        ScriptAction { script: if (!flight.down) win.rest(true) }
        PauseAnimation { duration: flight.down ? win.landMs : 0 }
        ScriptAction { script: if (flight.down) { w.miniOpacity = 1; win.rest(false) } }
    }
    SequentialAnimation {
        id: leaving         // up and away: into the popup (a crouch, then a spring upwards)
        ScriptAction { script: clawd.play("liftoff", 4, 0, false, { crouch: Tokens.ms(60), rise: Tokens.ms(240) }) }
        PauseAnimation { duration: Tokens.ms(60) }
        ParallelAnimation {
            NumberAnimation { target: tr; property: "y"; to: -win.hopH; duration: Tokens.ms(240); easing.type: Easing.OutQuad }
            NumberAnimation { target: clawd; property: "opacity"; to: 0; duration: Tokens.ms(240); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmOut }
        }
        ScriptAction { script: win.rest(false) }
    }
    SequentialAnimation {
        id: arriving        // back from the popup: drops onto the roof (falling, feet first) and lands
        ScriptAction { script: { clawd.stopAct(); sc.k = 1; tr.x = 0; tr.y = -win.hopH; clawd.opacity = 0 } }
        PauseAnimation { duration: Tokens.ms(120) }
        ScriptAction { script: clawd.play("land", 4, 0, false, { fall: Tokens.ms(300) }) }
        ParallelAnimation {
            NumberAnimation { target: tr; property: "y"; to: 0; duration: Tokens.ms(300); easing.type: Easing.InQuad }
            NumberAnimation { target: clawd; property: "opacity"; to: 1; duration: Tokens.ms(180) }
        }
    }
    function stopAll() { flight.stop(); leaving.stop(); arriving.stop(); clawd.stopAct() }
    function rest(on) { tr.x = 0; tr.y = 0; sc.k = 1; clawd.opacity = on ? 1 : 0 }
    function up() {         // island -> roof: a good jump, peaking well over the roof
        stopAll()
        const d = fromMini()
        fx = d.x; fy = d.y; fk = miniK; towardRoof = true; lift = bowFor(hopH * 0.7); arc = 0; along(0)
        flight.down = false
        flight.start()
    }
    function down() {       // roof -> island: a little hop off the edge, then the drop into his seat
        stopAll()
        const d = fromMini()
        fx = d.x; fy = d.y; fk = miniK; towardRoof = false; lift = bowFor(hopH * 0.35); arc = 0; along(0)
        flight.down = true
        flight.start()
    }
    function leave() { stopAll(); leaving.start() }
    function arrive() { stopAll(); arriving.start() }
}
