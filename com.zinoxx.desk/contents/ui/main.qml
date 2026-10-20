import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import "Rice"

// Rice Desk: the desktop's information layer, one per screen. A clock with the date and a status
// line (weather · theme · music) on every screen, the music card under it and Clawd on top of it on
// one screen (palette `_desk`). Everything is drawn in layer-shell windows on the bottom layer (over
// the wallpaper, under every window), placed by rice.py in the wallpaper's quiet zone (layout.py ->
// palette `_layout`; never the upper-left quadrant) in light or dark ink. The applet itself is an
// invisible speck on the desktop (the bar covers it).
//
// Cost: nothing moves while idle. The clock changes once a minute, the weather every 15, Clawd in
// stepped frames, the music's progress every 2 s while it plays.
PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation
    fullRepresentation: Item {
        Layout.minimumWidth: 1
        Layout.minimumHeight: 1
        Layout.preferredWidth: 1
        Layout.preferredHeight: 1
    }

    RicePalette { id: rp; output: Screen.name }
    readonly property RicePalette pal: rp
    readonly property string screenName: Screen.name
    readonly property var qscreen: {
        const all = Qt.application.screens
        for (let i = 0; i < all.length; i++) if (all[i].name === screenName) return all[i]
        return null
    }
    readonly property var lay: pal.values._layout ?? null
    readonly property var desk: pal.values._desk ?? ({})
    readonly property bool ready: pal.loaded && lay !== null && qscreen !== null

    // ---- time, to the minute
    property date now: new Date()
    Timer {
        id: tick
        interval: 60000 - (new Date().getSeconds() * 1000 + new Date().getMilliseconds()) + 50
        running: true
        repeat: true
        onTriggered: {
            root.now = new Date()
            interval = 60000 - (root.now.getSeconds() * 1000 + root.now.getMilliseconds()) + 50
        }
    }

    // ---- weather (weather.py caches and throttles: three desktops asking cost one fetch)
    property var weather: null
    // ---- Claude usage, for Clawd
    property var usage: null
    RiceShell {
        id: sh
        onNewData: (source, data) => {
            const out = data["stdout"] ?? ""
            if (source.indexOf("#weather") >= 0) { try { root.weather = JSON.parse(out) } catch (e) {} }
            else if (source.indexOf("#usage") >= 0) { try { root.usage = JSON.parse(out) } catch (e) { root.usage = null } }
            disconnectSource(source)
        }
    }
    Timer {
        interval: 15 * 60 * 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: sh.connectSource('python3 "$HOME/.config/plasma-rice/weather.py" #weather')
    }
    Timer {
        interval: 30000; running: root.desk.clawd === true; repeat: true; triggeredOnStart: true
        onTriggered: sh.connectSource('cat "$HOME/.cache/claude-usage.json" 2>/dev/null #usage')
    }

    // ---- Clawd's situation (the bar's Claude widget, in short)
    readonly property real nowSec: now.getTime() / 1000
    function pctOf(key) {
        const w = usage?.[key] ?? {}
        const reset = Number(w.resets_at ?? 0)
        return reset > 0 && reset <= nowSec ? 0 : Number(w.used_percentage ?? 0)
    }
    readonly property real updatedAgo: usage ? nowSec - Number(usage.updated ?? 0) : 1e9
    readonly property real peak: Math.max(pctOf("five_hour"), pctOf("seven_day"))
    // how full the usage is shows as how tired Clawd looks (Clawd.usage), not as a mood
    readonly property string mood: peak >= 100 ? "limited" : (!usage || updatedAgo > 30 * 60) ? "sleep" : "happy"
    readonly property bool working: usage !== null && updatedAgo < 180
    // what Claude Code is doing (its hooks), watched only where Clawd is shown
    ClaudeActivity { id: claude; active: root.desk.clawd === true }
    // a check-in from Claude (ask.sh): the "!" over the desktop Clawd and its message under the clock,
    // until it's marked done (a click on Clawd, or the bar's popup) or Claude clears it
    ClaudeAsk { id: checkIn; active: root.desk.clawd === true }
    readonly property bool asking: checkIn.asking
    readonly property string askMsg: checkIn.msg
    function askDone() { checkIn.done() }
    // an important update the update check found (update-check.py): Clawd holds a bubble and the
    // message sits under the clock, until a click on the bubble or the update is installed
    ClaudeAsk {
        id: cachy
        active: root.desk.clawd === true
        file: "update.json"
        ackCommand: 'python3 "$HOME/.config/plasma-rice/update-check.py" --ack'
    }
    readonly property bool updating: cachy.asking
    readonly property string updateTitle: updating ? String(cachy.ask.title ?? "Important Cachy update!") : ""
    readonly property string updateMsg: cachy.msg
    function updateDone() { cachy.done() }
    // a double click on Clawd: Claude Code in a new terminal (KIO starts it in its own scope)
    function summonClaude() { sh.connectSource("kstart --application net.local.claude #claude") }
    readonly property string activity: claude.activity
    // rain or snow outside (Open-Meteo / WMO weather codes): an umbrella, a scarf
    readonly property string sky: {
        const c = Number(weather?.now?.code ?? -1)
        return (c >= 51 && c <= 67) || (c >= 80 && c <= 82) || c >= 95 ? "rain"
             : (c >= 71 && c <= 77) || c === 85 || c === 86 ? "snow" : ""
    }
    readonly property int hour: now.getHours()
    readonly property string daypart: hour < 5 || hour >= 22 ? "night" : hour < 10 ? "morning" : hour < 18 ? "day" : "evening"
    readonly property string season: now.getMonth() === 9 && now.getDate() >= 24 ? "halloween"
        : now.getMonth() === 11 && now.getDate() <= 26 ? "xmas"
        : (now.getMonth() === 11 && now.getDate() === 31) || (now.getMonth() === 0 && now.getDate() === 1) ? "newyear" : ""

    // ---- screens plugged in or out: rice.py moves the music card and Clawd (`_desk`), gives each bar its
    // new screen's colours and clock size and re-borders the windows. Only the main screen's desktop asks,
    // once the screens have settled; also once at start (the screens may differ from the last session).
    readonly property string screenSetup: {
        const all = Qt.application.screens
        let out = []
        for (let i = 0; i < all.length; i++) out.push(all[i].name + "@" + all[i].virtualX + "," + all[i].virtualY)
        return screenName + " " + out.join(" ")
    }
    onScreenSetupChanged: rescreen.restart()
    Timer {
        id: rescreen
        interval: 3000
        running: true
        onTriggered: if (Plasmoid.containment?.screen === 0)
            sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" screens-changed #screens')
    }

    // ---- the desktop icons start under Glimpse's strip: Plasma only keeps them clear of its own panels, and
    // the strip (a layer-shell window with an exclusive zone) clipped their top. This applet shares the
    // containment's layout with the icon layer (the desktop's FolderViewLayerLoader), so it moves that layer
    // down by the strip (Glimpse's stripHeight, 8 by default, x top_scale) and a small gap. The opened band
    // may still cover them.
    readonly property int iconInset: Math.round(8 * pal.topScale) + Tokens.space.xs
    property Item iconLayer: null
    function findIconLayer() {
        for (let p = root.parent; p; p = p.parent) {
            for (let i = 0; i < p.children.length; i++) {
                const c = p.children[i]
                if (c.view !== undefined && c.model !== undefined && c.ready !== undefined) return c
            }
        }
        return null
    }
    Timer {
        // the applet is put into the layout after it loads, so look until it's there
        interval: 500; running: root.iconLayer === null; repeat: true; triggeredOnStart: true
        onTriggered: {
            root.iconLayer = root.findIconLayer()
            if (root.iconLayer) root.iconLayer.anchors.topMargin = Qt.binding(() => root.iconInset)
        }
    }

    // ---- music: the card on one screen, the status line on the others
    Music { id: music }
    readonly property var player: music

    // the windows, made once this desktop's screen is known (and again if it changes)
    Instantiator {
        model: root.qscreen ? [root.qscreen] : []
        delegate: ClockWindow { d: root }
    }
    Instantiator {
        model: root.qscreen ? [root.qscreen] : []
        delegate: MediaWindow { d: root }
    }
}
