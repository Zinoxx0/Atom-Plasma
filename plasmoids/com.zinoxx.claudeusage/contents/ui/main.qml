import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import Atom
import Rice

// Claude usage limits with Clawd in the panel.
// Data:    ~/.cache/claude-usage.json  (written by ~/.claude/statusline.sh, when the numbers change and
//          every 20 s while a session runs)
// Colours: this screen's palette (RicePalette, written by ~/.config/plasma-rice/rice.py)
PlasmoidItem {
    id: root

    // its panel lives on the shell's sheet (Atom.Shell kind "claude"), grown out of this island
    readonly property string myScreenName: root.Window.window ? Screen.name : ""
    PortalHost { id: portal; widget: root; kind: "claude"; screenName: root.myScreenName; popup: root.popup; onPlaced: root.measure() }
    readonly property bool panelOpen: portal.open
    function islandRect() { return portal.rect() }
    function togglePanel() { portal.toggle() }
    function openPanel() { portal.show() }
    function closePanel() { portal.close() }
    function hoverPanel() { portal.hover() }
    Component.onCompleted: Qt.callLater(moveClawd)

    RicePalette { id: pal; output: Screen.name }
    readonly property var palValues: pal.values     // Clawd takes the raw palette (it has its own `pal`)
    readonly property real uiScale: pal.uiScale

    // ---------- data ----------
    // the limits, watched (no polling); the 80% / 95% notifications come from ~/.claude/statusline.sh
    // when the data changes (contents/code/alerts.py)
    // every bar has this widget, the islands show on one (kwin/rice_islands): the others' data rests (each
    // source reads its file again the moment it's live)
    readonly property bool live: Shell.barShown(myScreenName) || panelOpen
    ClaudeUsage { id: limits; fast: root.panelOpen; active: root.live }
    readonly property var usage: limits.usage
    readonly property real now: limits.now
    RiceShell { id: sh }
    // a check-in Claude asked for (~/.config/plasma-rice/bin/ask.sh): a big "!" over Clawd until "Done"
    // (or until Claude clears it); ClaudeAsk watches the file, no polling
    ClaudeAsk { id: checkIn; active: root.live }
    readonly property var ask: checkIn.ask
    readonly property bool asking: checkIn.asking
    // the island turns red for a check-in, or while Claude Code waits on a permission / a question form
    Plasmoid.status: asking || activity === "attention" ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus
    function ackAsk() { checkIn.done() }
    // an important update the update check found (~/.config/plasma-rice/bin/update-check.py): a green badge on
    // Clawd and a card in the popup, until it's marked seen or the update is installed
    ClaudeAsk {
        id: cachy
        active: root.live
        file: "update.json"
        ackCommand: 'python3 "$HOME/.config/plasma-rice/bin/update-check.py" --ack'
    }
    readonly property bool updating: cachy.asking
    readonly property var updateInfo: cachy.ask         // (not `update`: that's Item.update())
    function updateDone() { cachy.done() }
    // something playing: off duty, Clawd puts its headphones on
    NowPlaying { id: nowPlaying; ticking: false }
    readonly property bool musicOn: nowPlaying.playing
    // what the bar's Clawd is up to off duty (every Clawd works it out the same way from the clock)
    property string barHobby: ""            // "Knitting a scarf."
    property bool barIdle: false
    // behind a fullscreen window, or on a bar whose islands are on another screen (kwin/rice_islands),
    // nobody sees it: its Clawd holds still (no timers, no redraws)
    readonly property bool covered: Windows.isFullscreen(myScreenName) || !Shell.barShown(myScreenName)
    // rain or snow outside, from the desk's weather (weather.py caches it): an umbrella, a scarf
    WatchedJson { id: weatherFile; path: sh.home + "/.cache/rice/weather.json" }
    readonly property string sky: {
        const c = Number(weatherFile.value?.now?.code ?? -1)
        return (c >= 51 && c <= 67) || (c >= 80 && c <= 82) || c >= 95 ? "rain"
             : (c >= 71 && c <= 77) || c === 85 || c === 86 ? "snow" : ""
    }
    // a double click on Clawd: Claude Code in a new terminal (KIO starts it in its own scope, so it
    // outlives plasmashell)
    function summonClaude() {
        root.closePanel();
        sh.connectSource("kstart --application net.local.claude #claude");
    }

    readonly property var session: limits.session
    readonly property var weekly: limits.weekly
    readonly property bool hasData: limits.hasData
    readonly property real updatedAgo: limits.updatedAgo
    readonly property bool stale: limits.stale
    readonly property real peak: limits.peak
    // how full the usage is shows as how tired Clawd looks (Clawd.usage), not as a mood
    readonly property string mood: limits.mood

    // ---------- Clawd's situation ----------
    readonly property var clock: new Date(now * 1000)
    readonly property int hour: clock.getHours()
    readonly property string daypart: hour < 5 || hour >= 22 ? "night" : hour < 10 ? "morning"
                                    : hour < 18 ? "day" : "evening"
    readonly property bool weekend: clock.getDay() === 0 || clock.getDay() === 6
    readonly property string season: clock.getMonth() === 9 && clock.getDate() >= 24 ? "halloween"
        : clock.getMonth() === 11 && clock.getDate() <= 26 ? "xmas"
        : (clock.getMonth() === 11 && clock.getDate() === 31) || (clock.getMonth() === 0 && clock.getDate() === 1) ? "newyear" : ""
    // the status line rewrites the cache on every Claude Code update
    readonly property bool working: limits.working
    // what Claude Code is doing right now (its hooks write it, ClaudeActivity watches)
    ClaudeActivity { id: claude; active: root.live }
    readonly property string activity: claude.activity
    readonly property bool warm: limits.warm
    readonly property bool celebrate: limits.celebrate      // a window that was half used or more just reset
    readonly property var limitWin: limits.limitWin
    readonly property real sand: limits.sand

    readonly property string moodText: {
        if (celebrate) return "Fresh limits! Let's go.";
        if (mood === "limited") return "Out of energy. Recharging " + (limitWin.reset ? "until " + at(limitWin.reset) : "for a while") + ".";
        if (activity === "attention") return "Claude Code needs your OK.";
        if (activity === "waiting") return "Claude asked you something.";
        const after = ({ running: "Waiting on a background job…", done: "All done!", fixed: "Fixed it!",
                         found: "Found some answers.", stuck: "Hit a snag. Have a look?", chat: "Just chatting." })[activity];
        if (after) return after;
        if (peak >= 90) return "Running on fumes. So… sleepy.";
        if (!hasData) return "No usage data yet.";
        // off duty: what Clawd's doing with its time
        if (mood === "sleep" && barHobby) return barHobby + " Claude Code is resting.";
        const busy = ({ thinking: "Thinking it through…", typing: "Typing away with you.", building: "Running commands…",
                        reading: "Reading the code…", web: "Looking things up…", juggling: "Juggling subagents…",
                        sweeping: "Tidying up the context…" })[activity];
        if (busy) return peak >= 75 ? busy + " A bit sleepy." : busy;
        if (working && activity !== "idle") return daypart === "night" ? "Burning the midnight oil with you."
                          : warm ? "In the zone, a bit ahead of pace." : "In the zone with you.";
        if (peak >= 75) return "Getting sleepy. Maybe pace yourself.";
        if (barIdle && barHobby) return barHobby + (peak < 50 ? " Plenty of room left." : "");
        if (season === "xmas") return "Ho ho ho. Plenty of room left.";
        return ({
            morning: "Good morning! Coffee's ready.",
            day:     weekend ? "Weekend mode. Plenty of room." : "Plenty of room. Let's build something.",
            evening: "Evening. Still plenty of room.",
            night:   "Up late? Plenty of room left.",
        })[daypart];
    }

    function until(ts) {
        let s = Math.max(0, Math.floor(ts - now));
        const d = Math.floor(s / 86400); s -= d * 86400;
        const h = Math.floor(s / 3600); s -= h * 3600;
        const m = Math.floor(s / 60);
        if (d) return d + "d " + h + "h";
        if (h) return h + "h " + String(m).padStart(2, "0") + "m";
        return m + "m";
    }
    function at(ts) {
        const t = new Date(ts * 1000), today = new Date();
        const hm = Qt.formatTime(t, "HH:mm");
        return t.toDateString() === today.toDateString() ? hm : Qt.formatDate(t, "ddd") + " " + hm;
    }
    function ago(s) {
        if (s < 90) return "just now";
        if (s < 3600) return Math.round(s / 60) + " min ago";
        if (s < 86400) return Math.round(s / 3600) + " h ago";
        return Math.round(s / 86400) + " d ago";
    }
    function ringFrom(i, hot) { return hot ? pal.red : i === 0 ? pal.primary : pal.tertiary }
    function ringTo(i, hot) { return hot ? pal.orange : i === 0 ? pal.tertiary : pal.secondary }

    toolTipMainText: asking ? "Claude needs you" : updating ? String(updateInfo?.title ?? "Important Cachy update!") : "Claude"
    toolTipSubText: asking ? ask.msg + "\nOpen this to mark it done."
                  : updating ? String(updateInfo?.msg ?? "") + "\nOpen this for the report."
                  : hasData ? "Session " + Math.round(session.pct) + "%  ·  Weekly " + Math.round(weekly.pct) + "%\n" + moodText
                            : "No usage data yet"
    preferredRepresentation: compactRepresentation

    // ---------- fitting the bar (Rice/BarFit.qml): nothing to give up any more (no numbers on the bar,
    // the user 2026-11-14: they live in the popup and the tooltip), so the same width at every step
    BarFit { id: fit; widget: root }
    readonly property var riceFit: compactRepresentationItem ? compactRepresentationItem.fitWidths : []
    // beside the rings: how long until the session window resets (or, out of energy, the limit's window)
    readonly property real resetAt: mood === "limited" && limitWin.reset ? limitWin.reset
                                  : hasData && !session.expired && session.reset ? session.reset : 0
    // no session window running (the last one reset and Claude Code hasn't been used since): a whole one is
    // ready, and the next message starts it ("–" read as numbers gone missing; the user, 2026-11-15)
    readonly property string resetText: resetAt > 0 ? until(resetAt) : hasData ? "5h 00m" : "–"

    // ---------- panel ----------
    compactRepresentation: MouseArea {
        id: compact
        readonly property Item clawd: mini      // (ClawdRoof flies from and to it)
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        // what this widget takes (root.riceFit, for BarFit): Clawd's seat, the double ring and the reset
        // countdown (room kept for "0h 00m", so the island never shifts as it counts down). It shares its
        // island with the system rings on its right: a narrower right padding, and a hairline between them
        Text {
            id: cdFont
            visible: false
            font.family: Tokens.font.ui
            font.weight: Font.Medium
            font.pixelSize: Math.round(Tokens.size.label * root.uiScale)
            font.features: { "tnum": 1 }
        }
        TextMetrics { id: cdWidest; font: cdFont.font; text: "0h 00m" }
        readonly property real ringW: 22 * root.uiScale                                       // as the system rings
        readonly property real cdW: Tokens.space.sm * root.uiScale + Math.ceil(cdWidest.advanceWidth)
        readonly property real padL: Tokens.space.md * root.uiScale
        readonly property real padR: Tokens.space.sm * root.uiScale
        readonly property real seatW: mini.implicitWidth + Tokens.space.sm * root.uiScale      // Clawd's seat
        readonly property real bare: padL + seatW + ringW + cdW + padR
        // (BarFit plans with Clawd's seat open: the bar never has to refit when he goes up to the roof)
        readonly property var fitWidths: [bare, bare, bare]
        readonly property real shown: bare
        // while Clawd is up on the roof his seat closes, so the rings sit in the middle of their island
        // (the stretch is on the island's left: its right edge, and the rings, stay put)
        // whole pixels: the panel sizes a widget to the floor of a fractional width but keeps the room,
        // and the island's glass then parts at the joint (a hairline of wallpaper)
        Layout.minimumWidth: Math.ceil(shown - (1 - root.seat) * seatW)
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) Qt.openUrlExternally("https://claude.ai/settings/usage");
            else root.togglePanel();
        }

        // the island around it lights up on hover (Panel Colorizer); Clawd says hi and its eyes follow
        // the pointer. A click on Clawd itself plays one of its acts, anywhere else opens the popup.
        // (whichever Clawd is out: the island's, or the one on its roof)
        readonly property Item seen: root.place === "roof" ? roof.clawd : mini
        onContainsMouseChanged: if (containsMouse) { seen.greet(); root.hoverPanel() } else portal.unhover()
        onPositionChanged: mouse => seen.lookAt(seen.mapFromItem(compact, mouse.x, mouse.y).x / seen.width)

        // the hairline between this and the system rings, halfway across the gap (its own right padding,
        // Colorizer's 6 px between widgets, the system rings' left padding)
        Rectangle {
            x: compact.width - compact.padR + Math.round((compact.padR + 6 + Tokens.space.md * root.uiScale) / 2)
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: Math.round(16 * root.uiScale)     // (as the status island's own divider)
            color: C.alpha(pal.fg, 0.18)
        }
        RowLayout {
            id: row
            x: compact.padL            // (the seat shrinks itself as it closes)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Item {
                // Clawd's seat: it closes from the left, and Clawd keeps his place beside the rings, so
                // the roof's jumps always aim at the spot he lands in
                Layout.preferredWidth: compact.seatW * root.seat
                Layout.preferredHeight: mini.implicitHeight
                Layout.alignment: Qt.AlignVCenter
                Clawd {
                    id: mini
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.space.sm * root.uiScale
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 1
                    px: root.seatPx
                    continuous: false
                    mood: root.mood
                    usage: root.peak
                    working: root.working
                    activity: root.activity
                    celebrate: root.celebrate
                    warm: root.warm
                    daypart: root.daypart
                    weekend: root.weekend
                    season: root.season
                    sand: root.sand
                    alert: root.asking
                    notice: root.updating
                    music: root.musicOn
                    weather: root.sky
                    pal: root.palValues
                    hovered: compact.containsMouse
                    animate: !root.covered
                    onHobbyTextChanged: root.barHobby = hobbyText
                    onIdleChanged: root.barIdle = idle
                    Component.onCompleted: { root.barHobby = hobbyText; root.barIdle = idle }
                    onAlertClicked: root.openPanel()        // the popup has the message and Done
                    onSummoned: root.summonClaude()
                    // only while Clawd is in its island (root.place); it leaves and drops back in from above
                    opacity: root.miniOpacity
                    transform: Translate { y: root.miniLift }
                }
            }
            // one double ring: the session (5 h) outside, the week (7 d) inside
            Item {
                implicitWidth: compact.ringW; implicitHeight: implicitWidth
                Layout.alignment: Qt.AlignVCenter
                readonly property real thick: 2.5 * root.uiScale
                Ring {
                    id: outer
                    anchors.fill: parent
                    readonly property bool hot: root.session.pct >= 90
                    thickness: parent.thick
                    instant: true    // a sweep per update would keep the panel redrawing
                    value: root.session.pct
                    from: root.ringFrom(0, hot)
                    to: root.ringTo(0, hot)
                    track: C.alpha(pal.fg, 0.14)
                    showText: false
                }
                Ring {
                    anchors.centerIn: parent
                    readonly property bool hot: root.weekly.pct >= 90
                    width: parent.width - 2 * (parent.thick + 1.5 * root.uiScale); height: width
                    thickness: parent.thick
                    instant: true
                    value: root.weekly.pct
                    from: root.ringFrom(1, hot)
                    to: root.ringTo(1, hot)
                    track: C.alpha(pal.fg, 0.14)
                    showText: false
                }
            }
            Text {
                Layout.leftMargin: Tokens.space.sm * root.uiScale
                Layout.preferredWidth: compact.cdW - Tokens.space.sm * root.uiScale
                Layout.alignment: Qt.AlignVCenter
                text: root.resetText
                color: root.mood === "limited" ? pal.red : pal.fgDim
                font: cdFont.font
            }
        }
    }

    // ---------- one Clawd, three places ----------
    // "island": in its island, as always: a window covers the space above it, or the launcher or the power
    //           overlay has the screen;
    // "roof":   standing on the island's roof, bigger, in a little window of its own (ClawdRoof.qml) when
    //           nothing covers that space;
    // "popup":  in the popup while it's open.
    // The other places show no Clawd; between them it jumps. A bar whose islands are on another screen
    // (kwin/rice_islands) or under a fullscreen window shows none at all (its window is transparent).
    readonly property var myScreen: Array.from(Qt.application.screens).find(s => s.name === myScreenName) ?? null
    readonly property bool barSeen: Shell.barShown(myScreenName) && !Windows.isFullscreen(myScreenName)
    readonly property bool screenBusy: Shell.screen === myScreenName && (Shell.kind === "power"
        || (Shell.kind === "launcher" && !(Shell.args && Shell.args.searchOnly)))    // (the finder leaves the bar be)
    readonly property real roofPx: 3.5 * uiScale
    // in his island he stays big (the user, 2026-11-14: he's the bar's whimsy), short of the roof's size
    // only so what he holds over his head still fits under the bar's top edge
    readonly property real seatPx: 3 * uiScale
    readonly property real roofClawdW: 22 * roofPx
    readonly property real roofClawdH: 10 * roofPx
    property real islandH: 0                // the island's height (it stands on the screen's bottom edge)
    property real islandR: 0                // its right edge, screen-local x (it stays put: the stretch is on its left)
    property real islandW: 0                // its width with Clawd's seat open
    property real seatW: 0
    // on the roof Clawd stands over the middle of the rings (the island without his seat)
    readonly property real roofCx: islandR - (islandW - seatW) / 2
    // his window spans the whole island (his jumps start and end in its seat) and the roof spot
    readonly property real roofWinX: Math.floor(Math.min(islandR - islandW, roofCx - roofClawdW / 2) - 8 * uiScale)
    readonly property real roofWinW: Math.ceil(Math.max(islandR, roofCx + roofClawdW / 2) + 8 * uiScale - roofWinX)
    readonly property real roofWinH: islandH + roofClawdH * 1.6 + 8 * uiScale
    readonly property var roofRect: myScreen && islandH > 0
        ? { x: myScreen.virtualX + roofCx - roofClawdW / 2, y: myScreen.virtualY + myScreen.height - islandH - roofClawdH,
            width: roofClawdW, height: roofClawdH } : null
    function measure() {
        const it = compactRepresentationItem, lay = fit.panelLayout, sc = myScreen
        if (!it || !lay || !sc || !it.width) return
        islandH = lay.height                // the layout runs from the island's top to the screen's edge
        islandR = Shell.rectOf(it, it.width, 0, 0, 0).x - sc.virtualX
        islandW = it.shown
        seatW = it.seatW
    }
    // again whenever the island may have moved: the bar reflowed (its container moved), the bar itself
    // moved or resized, this widget's width changed (numbers folding), the islands came to this screen
    Timer { id: remeasure; interval: 250; onTriggered: root.measure() }
    readonly property Item container: {
        const lay = fit.panelLayout
        let it = compactRepresentationItem
        while (it && it.parent && it.parent !== lay) it = it.parent
        return it && lay && it.parent === lay ? it : null
    }
    Connections { target: root.container; function onXChanged() { remeasure.restart() } function onWidthChanged() { remeasure.restart() } }
    Connections { target: root.Window.window; function onXChanged() { remeasure.restart() } function onWidthChanged() { remeasure.restart() } }
    Connections { target: root.compactRepresentationItem; function onWidthChanged() { remeasure.restart() } }
    Connections { target: Shell; function onBarChanged() { remeasure.restart() } }
    onMyScreenChanged: remeasure.restart()

    readonly property bool roofFree: barSeen && !screenBusy && !!roofRect && !Windows.occupied(roofRect)
    property bool roofOk: false             // roofFree for a moment: a window dragged past doesn't bounce Clawd
    onRoofFreeChanged: { if (!roofFree) { roofSettle.stop(); roofOk = false } else roofSettle.restart() }
    Timer { id: roofSettle; interval: 450; onTriggered: root.roofOk = root.roofFree }
    readonly property string place: panelOpen ? "popup" : roofOk ? "roof" : "island"

    property string clawdAt: ""             // where Clawd is now
    property real miniOpacity: 1
    property real miniLift: 0
    property real popupIn: 0
    property real seat: 1                   // Clawd's seat in the island: 1 open (he's in it), 0 closed (roof)
    NumberAnimation { id: seatGlide; target: root; property: "seat"; duration: Tokens.ms(560); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove }
    function seatTo(v, glide) {             // (the popup keeps the seat as it was: the island doesn't reflow under it)
        seatGlide.stop()
        if (glide && Math.abs(seat - v) > 0.001) { seatGlide.to = v; seatGlide.start() } else seat = v
    }
    // The launcher or the power overlay coming over the bar sends him down into his seat: nobody sees that
    // move (they cover the bar), so it's made at once, once they have (gliding the seat open reflowed the
    // whole bar every frame under the power overlay's ripple, for nothing). Back up on the roof once they've
    // gone is the jump everyone sees.
    onPlaceChanged: { if (screenBusy && place === "island") coverMove.restart(); else Qt.callLater(moveClawd) }
    Timer { id: coverMove; interval: Tokens.ms(700); onTriggered: if (root.screenBusy || !root.roofFree) root.moveClawd() }   // (gone already: the roof stands)
    function moveClawd() {
        const from = clawdAt, to = place
        if (from === to) return
        clawdAt = to
        measure()
        for (const a of [miniLeave, miniDrop, popupLand, popupLeave]) a.stop()
        const glide = from !== "" && barSeen && !screenBusy
        if (to !== "popup") seatTo(to === "roof" ? 0 : 1, glide)
        if (!glide) {                       // nobody's watching: no jump
            roof.stopAll(); roof.rest(to === "roof")
            miniOpacity = to === "island" ? 1 : 0; miniLift = 0; popupIn = to === "popup" ? 1 : 0
            return
        }
        if (to === "roof") from === "island" ? roof.up() : roof.arrive()
        else if (to === "island") from === "roof" ? roof.down() : miniDrop.start()
        else { from === "roof" ? roof.leave() : miniLeave.start(); popupLand.start() }
        if (from === "popup") popupLeave.start()
    }
    readonly property real liftPx: Math.round(14 * uiScale)
    ParallelAnimation {
        id: miniLeave       // up and out of the island, into the popup
        NumberAnimation { target: root; property: "miniLift"; to: -root.liftPx; duration: Tokens.ms(240); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmOut }
        NumberAnimation { target: root; property: "miniOpacity"; to: 0; duration: Tokens.ms(240); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmOut }
    }
    SequentialAnimation {
        id: miniDrop        // back from the popup: drops into the island
        PropertyAction { target: root; property: "miniLift"; value: -root.liftPx }
        PropertyAction { target: root; property: "miniOpacity"; value: 0 }
        PauseAnimation { duration: Tokens.ms(120) }
        ParallelAnimation {
            NumberAnimation { target: root; property: "miniLift"; to: 0; duration: Tokens.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn }
            NumberAnimation { target: root; property: "miniOpacity"; to: 1; duration: Tokens.ms(260) }
        }
    }
    SequentialAnimation {
        id: popupLand       // lands in the popup once it has grown out of the island
        PropertyAction { target: root; property: "popupIn"; value: 0 }
        PauseAnimation { duration: Tokens.ms(170) }
        NumberAnimation { target: root; property: "popupIn"; to: 1; duration: Tokens.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn }
    }
    NumberAnimation { id: popupLeave; target: root; property: "popupIn"; to: 0; duration: Tokens.ms(160); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmOut }
    ClawdRoof { id: roof; w: root; scr: root.myScreen }

    // ---------- popup ----------
    // the popup, drawn on the shell's sheet (Atom panels/Portal.qml makes it there, in this context, so it
    // reads this widget's data), grown out of this island
    property Component popup: Component {
        Item {
            id: full
            implicitWidth: 400
            implicitHeight: content.implicitHeight + 2 * Tokens.space.lg
            // Plasma restores a remembered popup size otherwise

            PopupIn {
                anchors.fill: parent
                active: root.panelOpen
                ricePalette: pal

                ColumnLayout {
                    id: content
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.space.lg }
                    spacing: Tokens.space.lg

                    // a check-in from Claude (ask.sh)
                    Rectangle {
                        visible: root.asking
                        Layout.fillWidth: true
                        implicitHeight: askRow.implicitHeight + 2 * Tokens.space.md
                        radius: Tokens.radius.md
                        color: C.alpha(pal.red, 0.13)
                        border.width: 1
                        border.color: C.alpha(pal.red, 0.45)
                        RowLayout {
                            id: askRow
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Tokens.space.md }
                            spacing: Tokens.space.md
                            Rectangle {
                                implicitWidth: 34; implicitHeight: 34
                                radius: Tokens.radius.sm
                                color: pal.red
                                Text {
                                    anchors.centerIn: parent
                                    text: "!"
                                    color: pal.surfaceLowest
                                    font.family: Tokens.font.display
                                    font.weight: Font.Black
                                    font.pixelSize: 22
                                }
                            }
                            ColumnLayout {
                                spacing: Tokens.space.xxs
                                Layout.fillWidth: true
                                Text {
                                    text: "Claude needs you"
                                    color: pal.red
                                    font.family: Tokens.font.ui
                                    font.weight: Font.Bold
                                    font.pixelSize: Tokens.size.body
                                }
                                Text {
                                    text: root.ask ? root.ask.msg : ""
                                    color: pal.fg
                                    font.family: Tokens.font.ui
                                    font.pixelSize: Tokens.size.body
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            Pill {
                                palette: pal
                                text: "Done"
                                accent: pal.red
                                onAccent: pal.surfaceLowest
                                onClicked: root.ackAsk()
                            }
                        }
                    }

                    // an important update (update-check.py): what it is, the care it needs, the full report
                    Rectangle {
                        visible: root.updating
                        Layout.fillWidth: true
                        implicitHeight: updateRow.implicitHeight + 2 * Tokens.space.md
                        radius: Tokens.radius.md
                        color: C.alpha(pal.green, 0.12)
                        border.width: 1
                        border.color: C.alpha(pal.green, 0.4)
                        RowLayout {
                            id: updateRow
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Tokens.space.md }
                            spacing: Tokens.space.md
                            Rectangle {
                                implicitWidth: 34; implicitHeight: 34
                                radius: Tokens.radius.sm
                                color: pal.green
                                Layout.alignment: Qt.AlignTop
                                Text {
                                    anchors.centerIn: parent
                                    text: "system_update_alt"
                                    color: pal.surfaceLowest
                                    font.family: Tokens.font.icons
                                    font.pixelSize: 22
                                }
                            }
                            ColumnLayout {
                                spacing: Tokens.space.xxs
                                Layout.fillWidth: true
                                Text {
                                    text: root.updateInfo ? String(root.updateInfo.title ?? "Important Cachy update!") : ""
                                    color: pal.green
                                    font.family: Tokens.font.ui
                                    font.weight: Font.Bold
                                    font.pixelSize: Tokens.size.body
                                }
                                Text {
                                    text: root.updateInfo ? root.updateInfo.msg : ""
                                    color: pal.fg
                                    font.family: Tokens.font.ui
                                    font.pixelSize: Tokens.size.body
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                                Text {
                                    visible: text !== ""
                                    text: root.updateInfo ? String(root.updateInfo.caveat ?? "") : ""
                                    color: pal.fgDim
                                    font.family: Tokens.font.ui
                                    font.pixelSize: Tokens.size.label
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                                RowLayout {
                                    spacing: Tokens.space.sm
                                    Layout.topMargin: Tokens.space.xs
                                    Pill {
                                        palette: pal
                                        text: "Got it"
                                        accent: pal.green
                                        onAccent: pal.surfaceLowest
                                        size: 28
                                        onClicked: root.updateDone()
                                    }
                                    Pill {
                                        palette: pal
                                        icon: "open_in_new"
                                        iconLast: true
                                        text: "Report"
                                        size: 28
                                        visible: !!(root.updateInfo && root.updateInfo.report)
                                        onClicked: { Qt.openUrlExternally("file://" + root.updateInfo.report); root.closePanel() }
                                    }
                                }
                            }
                        }
                    }

                    PopupHeader {
                        Layout.fillWidth: true
                        palette: pal
                        title: "Claude"
                        subtitle: root.moodText
                        leading: GlassCard {
                            implicitWidth: 132; implicitHeight: 92
                            palette: pal
                            accent: pal.claude
                            Clawd {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: 4
                                // it jumped here from the bar (root.place): lands from above
                                opacity: root.popupIn
                                transform: Translate { y: (1 - root.popupIn) * -16 }
                                px: 4.2
                                mood: root.mood
                                usage: root.peak
                                working: root.working
                                activity: root.activity
                                celebrate: root.celebrate
                                warm: root.warm
                                daypart: root.daypart
                                weekend: root.weekend
                                season: root.season
                                sand: root.sand
                                alert: root.asking
                                notice: root.updating
                                music: root.musicOn
                                weather: root.sky
                                pal: root.palValues
                                animate: root.panelOpen
                                onSummoned: root.summonClaude()
                            }
                        }
                        badge: Chip {
                            palette: pal
                            text: root.stale ? "idle" : "live"
                            dot: true
                            pulse: !root.stale && root.panelOpen
                            tint: root.stale ? pal.outline : pal.green
                            tooltip: root.hasData ? "Updated " + root.ago(root.updatedAgo) : "No usage data yet"
                        }
                    }

                    // gauges
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Repeater {
                            model: [
                                { key: "session", title: "Session", span: "5 hours" },
                                { key: "weekly",  title: "Weekly",  span: "7 days" },
                            ]
                            ColumnLayout {
                                id: gauge
                                required property var modelData
                                required property int index
                                readonly property var info: modelData.key === "session" ? root.session : root.weekly
                                readonly property bool hot: info.pct >= 90
                                Layout.fillWidth: true
                                spacing: Tokens.space.sm

                                Ring {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitWidth: 146; implicitHeight: 146
                                    value: gauge.info.pct
                                    pace: gauge.info.pace
                                    label: gauge.modelData.title
                                    from: root.ringFrom(gauge.index, gauge.hot)
                                    to: root.ringTo(gauge.index, gauge.hot)
                                    track: C.alpha(pal.fg, 0.08)
                                    paceColor: pal.fg
                                    textColor: pal.fg
                                    subColor: pal.fgDim
                                    active: root.panelOpen
                                }
                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: gauge.info.expired ? "window reset" : gauge.info.reset ? "resets in " + root.until(gauge.info.reset) : "–"
                                    color: pal.fg
                                    font.family: Tokens.font.ui
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Tokens.size.body
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    visible: gauge.info.reset > 0 && !gauge.info.expired
                                    text: root.at(gauge.info.reset) + "  ·  " + gauge.modelData.span
                                    color: pal.fgDim
                                    font.family: Tokens.font.ui
                                    font.pixelSize: Tokens.size.label
                                }
                                Chip {
                                    Layout.alignment: Qt.AlignHCenter
                                    visible: gauge.info.pace >= 0
                                    readonly property bool ahead: gauge.info.pct > gauge.info.pace + 5
                                    palette: pal
                                    text: ahead ? "ahead of pace" : "on track"
                                    tint: ahead ? pal.yellow : pal.green
                                }
                            }
                        }
                    }

                    // footer
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: C.alpha(pal.edge, Tokens.alpha.outline)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space.sm
                        Text {
                            text: root.hasData ? "Updated " + root.ago(root.updatedAgo) : "Waiting for a Claude Code session"
                            color: pal.fgDim
                            font.family: Tokens.font.ui
                            font.pixelSize: Tokens.size.label
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: "dot = even pace"
                            color: pal.muted
                            font.family: Tokens.font.ui
                            font.pixelSize: Tokens.size.small
                        }
                        Pill {
                            palette: pal
                            icon: "open_in_new"
                            iconLast: true
                            text: "Usage page"
                            size: 28
                            onClicked: { Qt.openUrlExternally("https://claude.ai/settings/usage"); root.closePanel() }
                        }
                    }
                }
            }

        }
    }
    // never shown (the popup is the shell's), but a panel applet draws nothing without one
    fullRepresentation: Item {}
}
