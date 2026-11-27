import QtQuick
import QtQuick.Effects
import QtCore
import Atom
import Atom.Native
import Rice
import "../theme"       // the Theme page's parts: Focusable (the lens walks them), StudioChip

// Atom Manager: the launcher's settings page (the gear at the bottom right; F1, a pad's View), the same in every
// launcher style, built like the Theme page: on the left who it is (the emblem, the version, whether it's up to
// date) and its sections, each with its value now; on the right the section, whole.
//   Updates   the version, the channel (stable, beta, alpha), whether a release waits (Check now: rice.py manager
//             check), Update (rice.py update start: a custom build asks first; the progress shows live from
//             update-progress.json), what's new (atom/updater.py is the engine)
//   Health    rice.py doctor's checks: what to fix (A copies the fix), then everything in place
//   Credits   the people (git history) and the projects it stands on (atom/data/credits.json: A opens one)
//   System    the machine as a bug report wants it, the features on here, copy it, report an issue
// Its data: `rice.py manager [check|doctor]` (atom/manager.py). One lens walks it all as on the Theme page: the keys
// and a pad's D-pad spatially, the pointer where it rests; A does, B goes back to the sections and then out (key()
// returns false), LB/RB (Tab) the section. Under Shell.debug what acts (opening a page, copying, updating) is logged.
Item {
    id: mp
    required property var launcher
    required property RicePalette rice
    required property RicePalette look
    required property string screenName
    required property real unit
    property real topInset: d(140)
    property bool active: true              // the keys are here (not on the host's top bar)
    property string inputMode: Gamepad.inUse ? "pad" : "keys"   // pointer | keys | pad (hints show only the input in use)
    property bool padHints: inputMode === "pad"                 // frozen while pointer fades hints out (no glyph flash)
    onInputModeChanged: if (inputMode !== "pointer") padHints = inputMode === "pad"
    readonly property string actKey: inputMode === "pad" ? "A" : inputMode === "keys" ? "Enter" : ""
    property real veil: 0.5
    property point origin: Qt.point(0, 0)
    property string wideFamily: wideFont.status === FontLoader.Ready ? wideFont.name : Tokens.font.display
    signal leave()                          // up past the top: the host's top bar
    signal giveKeys()
    FontLoader { id: wideFont; source: Qt.resolvedUrl("../../fonts/HubotSans.ttf") }
    function d(px) { return px * unit / 0.836 }
    function wideAxes(w, wt) { return { "wdth": w, "wght": wt } }
    readonly property real mainX: d(600)
    readonly property real mainWidth: Math.max(d(400), width - mainX - d(72))

    // ---------------------------------------------------------------- the data (rice.py manager)
    property var info: null
    property var health: null
    property string busy: ""                // "" | "info" | "check" | "doctor"
    property string checkError: ""
    readonly property var repo: info ? info.repo : ({})
    readonly property var upd: info ? info.update : ({})
    readonly property var sys: info ? info.system : ({})
    readonly property bool available: !!upd.available
    readonly property bool critical: !!upd.critical
    readonly property bool developer: upd.mode === "developer"
    readonly property var blockers: upd.blockers || []
    readonly property var custom: upd.custom || []
    readonly property string channel: upd.channel || "stable"
    // a running update (its own unit writes this as it goes; it outlives the launcher)
    readonly property string home: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "")
    WatchedJson { id: progW; path: mp.home + "/.local/state/rice/update-progress.json" }
    readonly property var prog: progW.value || ({})
    readonly property bool updating: prog.state === "running" && Date.now() / 1000 - (prog.started || 0) < 3 * 3600
    readonly property bool lastFailed: (prog.state === "failed" || prog.state === "rolledback") && Date.now() / 1000 - (prog.finished || 0) < 86400
    property bool confirming: false         // the custom build's warning is up
    onUpdatingChanged: if (!updating) load()
    readonly property string version: repo.version || ""
    function load() { busy = "info"; sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" manager #minfo') }
    function check() {
        if (busy === "check") return
        busy = "check"
        say("Asking for news…")
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" manager check #mcheck')
    }
    function runDoctor() {
        if (busy === "doctor") return
        busy = "doctor"
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" manager doctor #mdoctor')
    }
    RiceShell {
        id: sh
        onNewData: (source, data) => {
            const kind = (source.match(/#(\w+)(?: \d+)?$/) || [])[1], out = data["stdout"] ?? ""
            disconnectSource(source)
            if (kind === "copy" || kind === "open") return
            if (kind === "mstart") {
                let r = null
                try { r = JSON.parse(out) } catch (e) { r = null }
                mp.say(r && r.started ? "Updating: your desktop restarts at the end" : (r && r.message) || "The update didn't start")
                return
            }
            if (kind === "mchan") { mp.busy = ""; mp.load(); return }
            if (mp.busy === kind.slice(1)) mp.busy = ""
            let v = null
            try { v = JSON.parse(out) } catch (e) { v = null }
            if (!v) { if (kind !== "minfo") mp.say("That didn't work"); return }
            if (kind === "mdoctor") { mp.health = v; mp.relensSoon(); return }
            const first = !mp.info
            mp.info = v
            mp.checkError = (v.update && v.update.error) || ""
            if (first && (!mp.focused || !mp.focused.inSide)) { mp.lastKey = ({}); mp.enterTimer.restart() }
            if (kind === "mcheck") {
                mp.checkError = v.update.error || ""
                mp.say(mp.checkError ? "Couldn't reach GitHub" : v.update.available ? "Atom Plasma " + v.update.latest + " is out"
                       : v.update.mode === "developer" ? "Checked: your developer copy stays as it is" : "You're up to date")
            }
            mp.relensSoon()
            if (!mp.focused) mp.refocusTimer.restart()
        }
    }
    function ago(t) {
        if (!t) return "never"
        const s = Math.max(0, Date.now() / 1000 - t)
        if (s < 60) return "just now"
        if (s < 3600) return Math.round(s / 60) + " min ago"
        if (s < 86400) return Math.round(s / 3600) + " h ago"
        const dd = Math.round(s / 86400)
        return dd === 1 ? "yesterday" : dd + " days ago"
    }
    readonly property var status: {
        if (!info) return { icon: "progress_activity", text: "Looking…", tone: "dim" }
        if (updating) return { icon: "progress_activity", text: "Updating to " + (prog.target || "…"), tone: "accent" }
        if (busy === "check") return { icon: "progress_activity", text: "Checking…", tone: "dim" }
        if (developer) return { icon: "code", text: "Developer copy", tone: "dim" }
        if (blockers.length) return { icon: "block", text: "Not supported here", tone: "bad" }
        if (critical) return { icon: "gpp_maybe", text: "Critical update", tone: "bad" }
        if (available) return { icon: "system_update", text: upd.latest + " is out", tone: "accent" }
        if (!upd.checked) return { icon: "help", text: "Not checked yet", tone: "dim" }
        return { icon: "check_circle", text: "Up to date", tone: "ok" }
    }
    function toneColor(t) { return t === "bad" ? look.bad : t === "ok" ? look.ok : t === "accent" ? look.primary : look.fgDim }

    // ---------------------------------------------------------------- what it does (dry runs under Shell.debug)
    function openUrl(u, what) {
        if (!u) return
        if (Shell.debug) { console.warn("ATOM manager run open", u); return }
        say("Opening " + (what || "it") + "…")
        Qt.openUrlExternally(u)
        launcher.close()
    }
    function copy(text, what) {
        if (Shell.debug) { console.warn("ATOM manager run copy", what); say(what + " copied"); return }
        sh.exec("copy", ["wl-copy", "--", text])
        say(what + " copied")
    }
    // Update (or a developer copy's Switch to releases): a custom build asks first (confirming), then the update
    // runs in its own unit: rice.py update start [--force]
    function update() {
        if ((custom.length || developer) && !confirming) {
            confirming = true
            Qt.callLater(() => mp.focusKey("up:cancel", "key"))
            return
        }
        const force = confirming
        confirming = false
        if (Shell.debug) { console.warn("ATOM manager run update", force ? "--force" : ""); say("Updating (dry run)"); return }
        say("Starting the update…")
        sh.exec("mstart", ["python3", sh.home + "/.config/plasma-rice/rice.py", "update", "start"].concat(force ? ["--force"] : []))
    }
    function cancelUpdate() { confirming = false; Qt.callLater(() => mp.focusKey(mp.entryKey(), "key")) }
    function setChannel(c) {
        if (c === channel) return
        if (Shell.debug) { console.warn("ATOM manager run channel", c); return }
        busy = "chan"
        sh.exec("mchan", ["python3", sh.home + "/.config/plasma-rice/rice.py", "update", "channel", c])
    }
    readonly property var channels: [
        { id: "stable", name: "Stable", icon: "verified", what: "Finished releases and their fixes. The calm choice." },
        { id: "beta", name: "Beta", icon: "science", what: "The next features a little early, nearly ready." },
        { id: "alpha", name: "Alpha", icon: "bolt", what: "The newest work as it lands. Things may break." },
    ]
    function bugReport() {
        const s = sys, r = repo
        const lines = ["Atom Plasma " + version + (r.commit ? " (" + r.commit + (r.dirty ? ", local changes" : "") + (upd.mode === "developer" ? ", developer copy" : "") + ")" : ""),
                       "OS: " + s.os, "Plasma: " + s.plasma + (s.supported ? "" : " (not the supported " + s.supportedPlasma + ")"),
                       "Frameworks: " + s.frameworks, "Qt: " + s.qt, "Kernel: " + s.kernel, "Session: " + s.session]
            .concat((s.gpus || []).map((g, i) => "GPU " + (i + 1) + ": " + g))
            .concat(["Features on: " + ((info && info.features) || []).filter(f => f.on).map(f => f.id).join(", ")])
        if (health) lines.push("Health: " + (health.bad ? health.checks.filter(c => !c.ok).map(c => "FIX " + c.what).join("; ") : "all " + health.checks.length + " checks pass"))
        return lines.join("\n")
    }

    // ---------------------------------------------------------------- the sections
    readonly property var sections: [
        { id: "updates", icon: "system_update", name: "Updates" },
        { id: "health", icon: "health_and_safety", name: "Health" },
        { id: "credits", icon: "favorite", name: "Credits" },
        { id: "system", icon: "computer", name: "This machine" },
    ]
    property string section: "updates"
    property var lastKey: ({})
    function summary(id) {
        if (!info) return "…"
        if (id === "updates") return status.text + " · " + channel + " · checked " + ago(upd.checked)
        if (id === "health") return !health ? (busy === "doctor" ? "Checking…" : "Not run yet") : health.bad ? health.bad + (health.bad === 1 ? " thing" : " things") + " to fix" : "All " + health.checks.length + " checks pass"
        if (id === "credits") { const n = (info.credits || []).reduce((a, g) => a + g.items.length, 0); return (info.contributors || []).length + " people · " + n + " projects" }
        if (id === "system") return [sys.os, "Plasma " + sys.plasma].filter(Boolean).join(" · ")
        return ""
    }
    function setSection(id, enter) {
        if (id !== "updates") confirming = false
        if (id !== section) {
            section = id
            flick.contentY = 0
            if (Shell.debug) console.warn("ATOM manager section", id)
            if (id === "health" && !health && busy !== "doctor") runDoctor()
        }
        if (enter) enterTimer.restart()
        relensSoon()
    }
    function openSection(id) { setSection(id || "updates", true) }
    readonly property Timer enterTimer: Timer { interval: 0; onTriggered: mp.focusKey(mp.entryKey(), "key") }
    function stepSection(dir) {
        const i = sections.findIndex(s => s.id === section), n = sections[(i + dir + sections.length) % sections.length]
        const inSide = !!(focused && focused.inSide)
        setSection(n.id, !inSide)
        if (inSide) focusKey("sec:" + n.id, "key")
    }
    function entryKey() {
        const l = lastKey[section]
        if (l && findKey(l)) return l
        if (section === "updates") return confirming ? "up:cancel" : developer ? "up:switch" : available && !blockers.length ? "up:update" : "up:check"
        let best = null
        for (const f of regs) if (!f.inSide && f.visible) { const p = f.mapToItem(mp, 0, 0); if (!best || p.y < best.y - 1 || (Math.abs(p.y - best.y) <= 1 && p.x < best.x)) best = { f: f, x: p.x, y: p.y } }
        return best ? best.f.fkey : "sec:" + section
    }
    readonly property var head: {
        if (section === "updates") return { title: "Updates", sub: "Atom Plasma" + (version ? " " + version : "") + " · the " + channel + " channel" + (repo.url ? " · from " + repo.url.replace(/^https:\/\//, "") : "") }
        if (section === "health") return { title: "Health", sub: "Is every piece in place? The same checks as rice.py doctor" + (health ? " · run " + ago(health.now) : "") }
        if (section === "credits") return { title: "Credits", sub: "The people who made it and the projects it stands on" }
        return { title: "This machine", sub: "What a bug report needs · made for Plasma " + (sys.supportedPlasma || "") + " on Wayland" }
    }

    // ---------------------------------------------------------------- the focus: registered parts, one lens (as the Theme page)
    property var regs: []
    property Item focused: null
    function reg(f) { regs.push(f) }
    function unreg(f) { const i = regs.indexOf(f); if (i >= 0) regs.splice(i, 1); if (focused === f) { focused = null; refocusTimer.restart() } }
    function findKey(k) { return regs.find(f => f.fkey === k && f.visible) || null }
    function focusKey(k, from) { const f = findKey(k); if (f) focusItem(f, from) }
    readonly property Timer refocusTimer: Timer { interval: 0; onTriggered: if (!mp.focused) mp.focusKey(mp.entryKey(), "jump") }
    Timer { id: relensTimer; interval: 0; onTriggered: mp.relens(true) }
    function relensSoon() { relensTimer.restart() }
    function focusItem(f, from) {
        if (!f) return
        const was = focused
        focused = f
        if (!f.inSide && f.fkey) { const l = Object.assign({}, lastKey); l[section] = f.fkey; lastKey = l }
        if (from === "key" && f.rail && f.fkey.slice(4) !== section) setSection(f.fkey.slice(4), false)
        if (from === "key") { quietUntil = Date.now() + 450; ensureVisible(f) }
        relens(!was || from === "jump")
        if (Shell.debug && f !== was) console.warn("ATOM manager focus", f.fkey, "(" + from + ")")
    }
    function inBody(f) { let p = f; while (p) { if (p === flick.contentItem) return true; p = p.parent } return false }
    // the keys keep the focus in view: the body scrolls so it shows whole (a margin round it)
    function ensureVisible(f) {
        if (!inBody(f)) return
        const p = f.mapToItem(flick.contentItem, 0, 0), m = d(36)
        const now = scrollAnim.running ? scrollAnim.to : flick.contentY
        let to = now
        if (p.y - m < now) to = p.y - m
        else if (p.y + f.height + m > now + flick.height) to = p.y + f.height + m - flick.height
        to = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), to))
        if (Math.abs(to - flick.contentY) < 1) return
        scrollAnim.stop(); scrollAnim.from = flick.contentY; scrollAnim.to = to; scrollAnim.start()
    }
    NumberAnimation { id: scrollAnim; target: flick; property: "contentY"; duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn }
    function rectOf(f) {
        const t = f.lensItem || f
        const r = t.mapToItem(mp, 0, 0, t.width, t.height)
        if (scrollAnim.running && inBody(f)) r.y += flick.contentY - scrollAnim.to        // (where it will be)
        return r
    }
    function move(dx, dy) {
        const cur = focused
        if (!cur) { focusKey(entryKey(), "jump"); return }
        if (dx > 0 && cur.rail) { focusKey(entryKey(), "key"); return }
        const c = rectOf(cur), ccx = c.x + c.width / 2, ccy = c.y + c.height / 2
        let best = null, bs = 1e9
        for (const el of regs) {
            if (el === cur || !el.visible || el.opacity <= 0) continue
            if (dy && el.inSide !== cur.inSide) continue
            const r = rectOf(el), rcx = r.x + r.width / 2, rcy = r.y + r.height / 2
            if (!(dx ? (dx > 0 ? rcx > ccx + 2 : rcx < ccx - 2) : (dy > 0 ? rcy > ccy + 2 : rcy < ccy - 2))) continue
            const p = dx ? (dx > 0 ? r.x - (c.x + c.width) : c.x - (r.x + r.width)) : (dy > 0 ? r.y - (c.y + c.height) : c.y - (r.y + r.height))
            const ov = dx ? Math.min(c.y + c.height, r.y + r.height) - Math.max(c.y, r.y) : Math.min(c.x + c.width, r.x + r.width) - Math.max(c.x, r.x)
            const s = Math.max(p, 0) + (ov > 0 ? 0 : -ov * 3) + (dx ? Math.abs(rcy - ccy) : Math.abs(rcx - ccx)) * 0.05
            if (s < bs) { bs = s; best = el }
        }
        if (!best) { if (dy < 0) leave(); return }
        if (dx < 0 && best.inSide && !cur.inSide) best = findKey("sec:" + section) || best
        focusItem(best, "key")
    }
    function activate() {
        const f = focused
        if (!f) return
        if (Shell.debug) console.warn("ATOM manager activate", f.fkey)
        if (f.rail) setSection(f.fkey.slice(4), true)
        else f.activated()
    }
    property double movedAt: 0
    property double quietUntil: 0
    HoverHandler { id: pointer }
    readonly property point pointerAt: pointer.point.scenePosition
    onPointerAtChanged: movedAt = Date.now()
    function pointerFresh() { const t = Date.now(); return t - movedAt < 150 && t > quietUntil }
    function pointed(f) { if (f !== focused && pointerFresh()) focusItem(f, "mouse") }
    function clicked(f, focusOnly) {
        focusItem(f, "mouse")
        if (focusOnly) return
        if (f.rail) setSection(f.fkey.slice(4), false)
        else f.activated()
    }
    function wheel(dy) { flick.flick(0, dy * 6) }

    property real lx: 0
    property real ly: 0
    property real lw: 0
    property real lh: 0
    property real lr: 0
    property bool lensJump: true
    function relens(jump) {
        const f = focused
        if (!f) return
        const r = rectOf(f)
        lensJump = !!jump || lw === 0
        lx = r.x - f.lensGap; ly = r.y - f.lensGap; lw = r.width + 2 * f.lensGap; lh = r.height + 2 * f.lensGap; lr = f.lensRadius + f.lensGap
        lensJump = false
    }
    onWidthChanged: relensSoon()
    onHeightChanged: relensSoon()
    onUnitChanged: relensSoon()

    // ---------------------------------------------------------------- the keys (the host forwards them)
    function key(event) {
        const k = event.key
        if (k === Qt.Key_Left) move(-1, 0)
        else if (k === Qt.Key_Right) move(1, 0)
        else if (k === Qt.Key_Up) move(0, -1)
        else if (k === Qt.Key_Down) move(0, 1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) activate()
        else if (k === Qt.Key_Escape) {
            if (confirming) cancelUpdate()
            else if (focused && !focused.inSide) focusKey("sec:" + section, "key")
            else return false
        }
        else if (k === Qt.Key_Tab) stepSection(1)
        else if (k === Qt.Key_Backtab) stepSection(-1)
        else return false
        return true
    }

    property string news: ""
    function say(t) { news = t; newsTimer.restart() }
    Timer { id: newsTimer; interval: 2600; onTriggered: mp.news = "" }

    // ================================================================ the page
    Rectangle { anchors.fill: parent; color: C.alpha(mp.look.surfaceLowest, mp.look.light ? Math.max(mp.veil, 0.62) : mp.veil) }
    RectangularShadow {
        visible: mp.active && !!mp.focused && mp.lw > 0
        x: mp.lx; y: mp.ly; width: mp.lw; height: mp.lh
        radius: mp.lr; blur: mp.d(30); spread: mp.d(2)
        color: C.alpha(mp.look.primary, 0.55)
        Behavior on x { enabled: !mp.lensJump; NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Behavior on y { enabled: !mp.lensJump; NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Behavior on width { enabled: !mp.lensJump; NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Behavior on height { enabled: !mp.lensJump; NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
    }

    // ---------------------------------------------------------------- left: who it is, then the sections
    Column {
        id: sideCol
        x: mp.d(72)
        y: mp.topInset + mp.d(10)
        width: mp.d(460)
        spacing: mp.d(18)
        transformOrigin: Item.TopLeft
        scale: Math.min(1, (mp.height - y - mp.d(110)) / Math.max(1, implicitHeight))
        onScaleChanged: mp.relensSoon()
        Item {          // the identity panel: accent glass, as the Theme page's screen panel
            id: ident
            x: -mp.d(16)
            width: parent.width + mp.d(32)
            height: identCol.height + mp.d(44)
            RectangularShadow { anchors.fill: parent; radius: mp.d(26); blur: mp.d(40); offset.y: mp.d(16); spread: -mp.d(6); color: Qt.rgba(0, 0, 0, 0.22) }
            Rectangle {
                anchors.fill: parent
                radius: mp.d(26)
                color: C.alpha(C.mix(mp.look.surfaceLowest, mp.look.primary, 0.16), 0.66)
                border.width: mp.d(1.5)
                border.color: C.alpha(mp.critical ? mp.look.bad : mp.look.primary, 0.45)
            }
            Column {
                id: identCol
                x: mp.d(34); y: mp.d(22)
                width: parent.width - 2 * mp.d(34)
                spacing: mp.d(18)
                Row {
                    spacing: mp.d(18)
                    Rectangle {         // the jewel
                        width: mp.d(68); height: width; radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        gradient: Gradient { orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: mp.look.primary } GradientStop { position: 1; color: mp.look.tertiary } }
                        Emblem { anchors.centerIn: parent; scale: parent.width * 0.62 / 34
                                 c1: "#ffffff"; c2: C.mix(mp.look.tertiary, "#ffffff", 0.55); c3: C.mix(mp.look.red, "#ffffff", 0.15); c4: C.mix(mp.look.teal, "#ffffff", 0.15); glow: "#ffffff" }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: mp.d(4)
                        Text { text: "ATOM MANAGER"; color: mp.look.primary; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: mp.d(13); font.letterSpacing: mp.d(1.4) }
                        Text { text: "Atom Plasma"; color: mp.look.fg; font.family: mp.wideFamily; font.variableAxes: mp.wideAxes(118, 650); font.weight: Font.DemiBold; font.pixelSize: mp.d(32) }
                        Text { text: mp.version ? "Version " + mp.version + (mp.repo.commit ? " · " + mp.repo.commit : "") : " "; color: mp.look.fgDim; font.family: Tokens.font.ui; font.pixelSize: mp.d(15) }
                    }
                }
                Rectangle {     // where it stands
                    height: mp.d(40); width: stRow.width + mp.d(30); radius: height / 2
                    color: C.alpha(mp.toneColor(mp.status.tone), mp.status.tone === "dim" ? 0.10 : 0.18)
                    Behavior on color { ColorAnimation { duration: Tokens.ms(300) } }
                    Row {
                        id: stRow
                        anchors.centerIn: parent
                        spacing: mp.d(8)
                        Glyph { anchors.verticalCenter: parent.verticalCenter; icon: mp.status.icon; size: mp.d(21)
                                color: mp.status.tone === "dim" ? mp.look.fgDim : mp.toneColor(mp.status.tone) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: mp.status.text; color: mp.look.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: mp.d(15.5) }
                    }
                }
            }
        }
        Column {
            width: parent.width
            spacing: mp.d(4)
            Repeater {
                model: mp.sections
                Rail { required property var modelData; studio: mp; sec: modelData }
            }
        }
    }

    // ---------------------------------------------------------------- right: the section
    Item {
        id: mainCol
        x: mp.mainX
        y: mp.topInset
        width: mp.mainWidth
        height: mp.height - y - mp.d(96)
        Item {
            id: header
            width: parent.width
            height: mp.d(96)
            Column {
                anchors.bottom: parent.bottom
                spacing: mp.d(12)
                Text { text: mp.head.title; color: mp.look.fg; font.family: mp.wideFamily; font.variableAxes: mp.wideAxes(118, 650); font.pixelSize: mp.d(50) }
                Text { width: header.width; elide: Text.ElideRight; text: mp.head.sub; color: mp.look.fgDim; font.family: Tokens.font.ui; font.pixelSize: mp.d(17) }
            }
        }
        Flickable {
            id: flick
            y: header.height + mp.d(30)
            width: parent.width + mp.d(40)          // (room for the lens's glow at the right edge)
            x: -mp.d(20)
            height: parent.height - y
            clip: true
            contentWidth: width
            contentHeight: bodyLoader.item ? bodyLoader.item.height + mp.d(40) : 0
            boundsBehavior: Flickable.StopAtBounds
            onContentYChanged: if (!scrollAnim.running) mp.relensSoon()
            onContentHeightChanged: mp.relensSoon()         // (the layout moved under the focus: text came in)
            Loader {
                id: bodyLoader
                x: mp.d(20); y: mp.d(14)
                width: mainCol.width
                sourceComponent: mp.section === "updates" ? updatesC : mp.section === "health" ? healthC : mp.section === "credits" ? creditsC : systemC
                onLoaded: mp.relensSoon()
            }
            NumberAnimation on opacity { id: bodyIn; from: 0; to: 1; duration: Tokens.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn }
        }
    }
    onSectionChanged: bodyIn.restart()

    // ---------------------------------------------------------------- the parts
    // a section in the side column (as the Theme page's): its icon, its name, its value now
    component Rail: Focusable {
        id: ri
        required property var sec
        readonly property bool open: studio.section === sec.id
        width: studio.d(460); height: studio.d(74)
        rail: true; inSide: true
        fkey: "sec:" + sec.id
        lensRadius: studio.d(18)
        desc: "<b>" + sec.name + "</b> " + studio.summary(sec.id)
        act: "Open"
        Rectangle {
            anchors.fill: parent; radius: ri.studio.d(18)
            color: ri.open ? C.alpha(ri.studio.look.fg, 0.11) : ri.hovered ? C.alpha(ri.studio.look.fg, 0.06) : "transparent"
            Behavior on color { ColorAnimation { duration: Tokens.ms(300) } }
        }
        Text { x: ri.studio.d(18); width: ri.studio.d(36); anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignHCenter
               text: ri.sec.icon; color: ri.open ? ri.studio.look.primary : ri.studio.look.fgDim; font.family: Tokens.font.icons; font.pixelSize: ri.studio.d(27) }
        Column {
            x: ri.studio.d(72); anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - ri.studio.d(14)
            spacing: ri.studio.d(6)
            Text { text: ri.sec.name; color: ri.studio.look.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: ri.studio.d(19) }
            Text { width: parent.width; text: ri.studio.summary(ri.sec.id); elide: Text.ElideRight; color: ri.studio.look.fgDim; font.family: Tokens.font.ui; font.pixelSize: ri.studio.d(14.5) }
        }
    }
    // a glass card the lens can rest on (its children are its content: they sit inside its padding)
    component Card: Focusable {
        id: cd
        property real pad: studio.d(22)
        property color tint: "transparent"
        default property alias content: inner.data
        height: inner.childrenRect.height + 2 * pad
        lensRadius: studio.d(20)
        Rectangle {
            anchors.fill: parent; radius: cd.studio.d(20)
            color: cd.tint.a > 0 ? cd.tint : C.alpha(cd.studio.look.surfaceHigh, cd.hovered ? 0.62 : 0.44)
            Behavior on color { ColorAnimation { duration: Tokens.ms(220) } }
        }
        Item { id: inner; x: cd.pad; y: cd.pad; width: cd.width - 2 * cd.pad; height: childrenRect.height }
    }
    // an icon that spins while it's "progress_activity" (a separate glyph: a stopped animator leaves its angle)
    component Glyph: Item {
        id: gl
        property string icon: ""
        property color color: "white"
        property real size: 20
        implicitWidth: size; implicitHeight: size
        Text { anchors.centerIn: parent; visible: gl.icon !== "progress_activity"; text: gl.icon; color: gl.color; font.family: Tokens.font.icons; font.pixelSize: gl.size }
        Text {
            anchors.centerIn: parent; visible: gl.icon === "progress_activity"; text: "progress_activity"; color: gl.color; font.family: Tokens.font.icons; font.pixelSize: gl.size
            RotationAnimator on rotation { running: gl.icon === "progress_activity" && gl.visible; from: 0; to: 360; duration: 1100; loops: Animation.Infinite }
        }
    }
    component Heading: Text {
        property Item studio
        color: studio.look.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: studio.d(13); font.letterSpacing: studio.d(1.3)
        topPadding: studio.d(14)
    }

    // ---- Updates
    Component {
        id: updatesC
        Column {
            width: bodyLoader.width
            spacing: mp.d(18)
            Item {          // where it stands, and what to do about it
                id: upCard
                width: Math.min(parent.width, mp.d(940))
                height: upRow.height + mp.d(56)
                readonly property string tone: mp.status.tone
                Rectangle {
                    anchors.fill: parent; radius: mp.d(26)
                    color: C.alpha(C.mix(mp.look.surfaceLowest, mp.toneColor(upCard.tone), upCard.tone === "dim" ? 0.05 : 0.14), 0.7)
                    border.width: mp.d(1.5); border.color: C.alpha(mp.toneColor(upCard.tone), upCard.tone === "dim" ? 0.18 : 0.42)
                    Behavior on color { ColorAnimation { duration: Tokens.ms(400) } }
                }
                Row {
                    id: upRow
                    x: mp.d(30); y: mp.d(28)
                    spacing: mp.d(26)
                    Rectangle {
                        width: mp.d(84); height: width; radius: width / 2
                        color: C.alpha(mp.toneColor(upCard.tone), 0.18)
                        Glyph { anchors.centerIn: parent; icon: mp.status.icon; size: mp.d(44); color: upCard.tone === "dim" ? mp.look.fg : mp.toneColor(upCard.tone) }
                    }
                    Column {
                        id: upText
                        spacing: mp.d(10)
                        width: upCard.width - mp.d(84) - mp.d(26) - 2 * mp.d(30)
                        Text {
                            width: parent.width; wrapMode: Text.WordWrap
                            text: !mp.info ? "Looking…" : mp.updating ? "Updating to " + mp.prog.target + "…" : mp.busy === "check" ? "Asking GitHub for news…"
                                : mp.developer ? "Developer copy" : mp.blockers.length ? "This system isn't supported"
                                : mp.critical ? "A critical update is waiting" : mp.available ? "Atom Plasma " + mp.upd.latest + " is out" : "You're up to date"
                            color: mp.look.fg; font.family: mp.wideFamily; font.variableAxes: mp.wideAxes(112, 600); font.pixelSize: mp.d(30)
                        }
                        Text {
                            width: parent.width; wrapMode: Text.WordWrap
                            visible: text !== ""
                            text: !mp.info ? ""
                                : mp.updating ? (mp.prog.message || "")
                                : mp.developer ? "You're working on " + (mp.upd.branch || "a branch") + ": the updater leaves your copy alone."
                                  + (mp.upd.latest ? " The newest " + mp.channel + " release is " + mp.upd.latest + "." : "")
                                : mp.blockers.length ? mp.blockers.join(". ") + "."
                                : mp.critical ? (mp.upd.summary || "It fixes a security problem: update as soon as you can.")
                                : mp.available ? (mp.upd.summary || "A new " + mp.channel + " release is ready.")
                                : "Atom Plasma " + mp.version + " is the newest on the " + mp.channel + " channel."
                            color: mp.look.fg; opacity: 0.86; font.family: Tokens.font.ui; font.pixelSize: mp.d(16.5)
                        }
                        Text {      // what else the update does
                            width: parent.width; wrapMode: Text.WordWrap
                            readonly property var inst: mp.upd.install || ({})
                            readonly property var all: (inst.repo || []).concat((inst.aur || []).map(x => x + " (AUR)"))
                            visible: mp.available && !mp.updating && !mp.blockers.length && all.length > 0
                            text: "It also installs " + all.join(", ") + "."
                            color: mp.look.fgDim; font.family: Tokens.font.ui; font.pixelSize: mp.d(14.5)
                        }
                        Text {
                            width: parent.width; wrapMode: Text.WordWrap
                            visible: mp.lastFailed && !mp.updating
                            text: (mp.prog.state === "rolledback" ? "The last update was undone: " : "The last update didn't finish: ") + (mp.prog.message || "") + " (details in " + String(mp.prog.log || "").replace(mp.home, "~") + ")"
                            color: mp.look.bad; font.family: Tokens.font.ui; font.pixelSize: mp.d(14.5)
                        }
                        Text {
                            visible: !!mp.info && !mp.updating
                            text: ["Checked " + mp.ago(mp.upd.checked), mp.repo.commit ? "commit " + mp.repo.commit : "", mp.developer && mp.upd.devBehind ? "main has " + mp.upd.devBehind + " new commits" : "",
                                   mp.checkError ? "couldn't reach GitHub" : ""].filter(Boolean).join(" · ")
                            color: mp.look.fgDim; font.family: Tokens.font.ui; font.pixelSize: mp.d(14.5)
                        }
                        Column {    // the update's steps as it goes: a slim bar of segments, then where it is
                            visible: mp.updating
                            width: parent.width
                            spacing: mp.d(10)
                            topPadding: mp.d(4)
                            readonly property var steps: mp.prog.steps || []
                            readonly property int at: Math.max(0, steps.indexOf(mp.prog.step))
                            Row {
                                spacing: mp.d(6)
                                Repeater {
                                    model: parent.parent.steps
                                    Rectangle {
                                        required property string modelData
                                        required property int index
                                        readonly property bool done: (mp.prog.done || []).indexOf(modelData) >= 0
                                        readonly property bool now: mp.prog.step === modelData
                                        width: (upText.width - mp.d(6) * (parent.parent.steps.length - 1)) / Math.max(1, parent.parent.steps.length)
                                        height: mp.d(6); radius: height / 2
                                        color: done ? mp.look.primary : now ? C.alpha(mp.look.primary, 0.55) : C.alpha(mp.look.fg, 0.14)
                                        Behavior on color { ColorAnimation { duration: Tokens.ms(400) } }
                                        SequentialAnimation on opacity {     // the step under way breathes, slowly
                                            running: now && mp.updating; loops: Animation.Infinite
                                            NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutSine }
                                            NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                                        }
                                        onNowChanged: if (!now) opacity = 1
                                    }
                                }
                            }
                            Text {
                                readonly property string name: mp.prog.step || ""
                                text: "Step " + (parent.at + 1) + " of " + parent.steps.length + " · " + name.charAt(0).toUpperCase() + name.slice(1)
                                color: mp.look.fgDim; font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: mp.d(14.5)
                            }
                        }
                        Row {       // what to do
                            visible: !mp.updating && !mp.confirming
                            topPadding: mp.d(8)
                            spacing: mp.d(12)
                            StudioChip {
                                studio: mp
                                fkey: "up:update"
                                visible: mp.available && !mp.blockers.length && !mp.confirming
                                chosen: true
                                icon: "download"
                                text: mp.critical ? "Update now" : "Update to " + mp.upd.latest
                                act: "Update"
                                desc: "<b>Update</b> Atom Plasma " + mp.upd.latest + ": your build is kept as a backup first, the desktop restarts at the end, and it goes back by itself if anything breaks."
                                onActivated: mp.update()
                            }
                            StudioChip {
                                studio: mp
                                fkey: "up:switch"
                                visible: mp.developer && !!mp.upd.latestTag && !mp.blockers.length && !mp.confirming
                                icon: "swap_horiz"
                                text: "Switch to releases"
                                act: "Switch"
                                desc: "<b>Switch to releases</b> Make this copy follow the " + mp.channel + " releases (" + mp.upd.latest + "). Your work is kept as a backup branch."
                                onActivated: mp.update()
                            }
                            StudioChip {
                                studio: mp
                                fkey: "up:check"
                                visible: !mp.confirming
                                icon: "refresh"
                                text: mp.busy === "check" ? "Checking…" : "Check now"
                                act: "Check"
                                desc: "<b>Check now</b> Ask GitHub for releases on the " + mp.channel + " channel. Nothing changes on your desktop."
                                onActivated: mp.check()
                            }
                        }
                        Rectangle {     // the custom build's warning (the user's words, 2026-11-23)
                            visible: mp.confirming
                            width: parent.width
                            height: warnCol.height + mp.d(36)
                            radius: mp.d(18)
                            color: C.alpha(mp.look.bad, 0.12)
                            border.width: mp.d(1.5); border.color: C.alpha(mp.look.bad, 0.5)
                            Column {
                                id: warnCol
                                x: mp.d(20); y: mp.d(18)
                                width: parent.width - 2 * mp.d(20)
                                spacing: mp.d(12)
                                Row {
                                    spacing: mp.d(10)
                                    Text { text: "warning"; color: mp.look.bad; font.family: Tokens.font.icons; font.pixelSize: mp.d(24) }
                                    Text { width: warnCol.width - mp.d(34); wrapMode: Text.WordWrap
                                           text: "Your Atom build seems custom, updating it will rewrite your personal code, proceed anyways?"
                                           color: mp.look.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: mp.d(17) }
                                }
                                Text { width: parent.width; wrapMode: Text.WordWrap
                                       text: "Found: " + mp.custom.join(", ") + ". Your code is saved as a backup branch first (git branch --list 'backup/*'), so nothing is lost for good."
                                       color: mp.look.fgDim; font.family: Tokens.font.ui; font.pixelSize: mp.d(14.5) }
                                Row {
                                    spacing: mp.d(12)
                                    StudioChip { studio: mp; fkey: "up:cancel"; visible: mp.confirming; icon: "close"; text: "Cancel"; act: "Cancel"
                                                 desc: "<b>Cancel</b> Keep your build as it is."; onActivated: mp.cancelUpdate() }
                                    StudioChip { studio: mp; fkey: "up:force"; visible: mp.confirming; icon: "download"; text: "Update anyway"; act: "Update"
                                                 desc: "<b>Update anyway</b> Back up your build, then replace it with " + mp.upd.latest + "."; onActivated: mp.update() }
                                }
                            }
                        }
                    }
                }
            }
            // the channel: which releases come
            Heading { studio: mp; text: "CHANNEL" }
            Row {
                spacing: mp.d(12)
                Repeater {
                    model: mp.channels
                    StudioChip {
                        required property var modelData
                        studio: mp
                        fkey: "chan:" + modelData.id
                        icon: modelData.icon
                        text: modelData.name
                        chosen: mp.channel === modelData.id
                        act: chosen ? "Choose" : "Switch to " + modelData.name
                        desc: "<b>" + modelData.name + "</b> " + modelData.what
                        onActivated: mp.setChannel(modelData.id)
                    }
                }
            }
            Text {
                width: Math.min(parent.width, mp.d(940)); wrapMode: Text.WordWrap
                text: (mp.channels.find(c => c.id === mp.channel) || mp.channels[0]).what + " A channel takes its own releases and every steadier one."
                color: mp.look.fgDim; font.family: Tokens.font.ui; font.pixelSize: mp.d(14.5)
            }
            // what's new: CHANGELOG.md (the waiting release's), a card per part, A opens it whole
            Heading { studio: mp; text: mp.upd.newer ? "WHAT " + mp.upd.latest + " BRINGS" : "WHAT'S NEW"; visible: changes.count > 0 }
            Repeater {
                id: changes
                model: {
                    const out = []
                    const log = (mp.info && mp.info.changelog) || []
                    for (const s of log.slice(0, mp.upd.newer ? 1 : 2))
                        for (const g of s.groups) out.push({ version: s.version, title: g.title || s.version, note: g.note, items: g.items })
                    return out
                }
                Card {
                    id: chg
                    required property var modelData
                    required property int index
                    property bool whole: false
                    studio: mp
                    width: Math.min(bodyLoader.width, mp.d(940))
                    fkey: "chg:" + index
                    act: whole ? "Show less" : "Read all"
                    desc: "<b>" + modelData.title + "</b> " + modelData.items.length + (modelData.items.length === 1 ? " change" : " changes") + " · " + (modelData.version === "Unreleased" ? "not in a release yet" : "in " + modelData.version)
                    onActivated: { whole = !whole; mp.relensSoon(); Qt.callLater(() => mp.ensureVisible(chg)) }
                    Column {
                        width: parent.width
                        spacing: mp.d(10)
                        Row {
                            spacing: mp.d(10)
                            Text { text: chg.modelData.title; color: mp.look.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: mp.d(18) }
                            Text { anchors.baseline: parent.children[0].baseline; text: chg.modelData.version === "Unreleased" ? "next version" : chg.modelData.version; color: mp.look.primary; font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: mp.d(13.5) }
                        }
                        Repeater {
                            model: chg.whole ? chg.modelData.items : chg.modelData.items.slice(0, 2)
                            Row {
                                required property string modelData
                                spacing: mp.d(10)
                                Rectangle { y: mp.d(9); width: mp.d(5); height: width; radius: width / 2; color: mp.look.primary }
                                Text { width: chg.width - 2 * chg.pad - mp.d(15); text: modelData; wrapMode: Text.WordWrap; maximumLineCount: chg.whole ? 40 : 2; elide: Text.ElideRight
                                       color: mp.look.fg; opacity: 0.86; font.family: Tokens.font.ui; font.pixelSize: mp.d(15); lineHeight: 1.12 }
                            }
                        }
                        Text { visible: !chg.whole && chg.modelData.items.length > 2; text: "+ " + (chg.modelData.items.length - 2) + " more"; color: mp.look.fgDim; font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: mp.d(14) }
                    }
                }
            }
        }
    }

    // ---- Health
    Component {
        id: healthC
        Column {
            width: bodyLoader.width
            spacing: mp.d(18)
            readonly property var fails: mp.health ? mp.health.checks.filter(c => !c.ok) : []
            readonly property var passes: mp.health ? mp.health.checks.filter(c => c.ok) : []
            Card {
                studio: mp
                width: Math.min(parent.width, mp.d(940))
                fkey: "hl:run"
                act: "Run again"
                desc: "<b>Run the checks again</b> Every piece the rice puts outside its folder, the units, the shell, the bars."
                tint: C.alpha(C.mix(mp.look.surfaceLowest, !mp.health ? mp.look.fgDim : mp.health.bad ? mp.look.bad : mp.look.ok, 0.14), 0.7)
                onActivated: mp.runDoctor()
                Row {
                    spacing: mp.d(24)
                    Rectangle {
                        width: mp.d(72); height: width; radius: width / 2
                        color: C.alpha(!mp.health ? mp.look.fg : mp.health.bad ? mp.look.bad : mp.look.ok, 0.16)
                        Glyph { anchors.centerIn: parent; icon: mp.busy === "doctor" ? "progress_activity" : !mp.health ? "health_and_safety" : mp.health.bad ? "build" : "verified"
                                size: mp.d(38); color: !mp.health ? mp.look.fg : mp.health.bad ? mp.look.bad : mp.look.ok }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: mp.d(8)
                        Text { text: mp.busy === "doctor" ? "Checking every piece…" : !mp.health ? "Not checked yet" : mp.health.bad ? (mp.health.bad === 1 ? "One thing to fix" : mp.health.bad + " things to fix") : "Everything's in place"
                               color: mp.look.fg; font.family: mp.wideFamily; font.variableAxes: mp.wideAxes(112, 600); font.pixelSize: mp.d(28) }
                        Text { text: mp.health ? mp.health.checks.length + " checks · run " + mp.ago(mp.health.now) + (mp.actKey ? " · " + mp.actKey + " runs them again" : "") : mp.actKey ? mp.actKey + " runs them" : "Run the checks"
                               color: mp.look.fgDim; font.family: Tokens.font.ui; font.pixelSize: mp.d(15) }
                    }
                }
            }
            Heading { studio: mp; text: "TO FIX"; visible: parent.fails.length > 0 }
            Repeater {
                model: parent.fails
                Card {
                    id: fc
                    required property var modelData
                    required property int index
                    studio: mp
                    width: Math.min(bodyLoader.width, mp.d(940))
                    fkey: "fix:" + index
                    act: "Copy the fix"
                    desc: "<b>Copy the fix</b> Paste it in a terminal."
                    onActivated: mp.copy(modelData.fix, "The fix")
                    Column {
                        width: parent.width
                        spacing: mp.d(10)
                        Row {
                            spacing: mp.d(10)
                            Text { text: "error"; color: mp.look.bad; font.family: Tokens.font.icons; font.pixelSize: mp.d(22) }
                            Text { width: fc.width - 2 * fc.pad - mp.d(32); text: fc.modelData.what; wrapMode: Text.WordWrap; color: mp.look.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: mp.d(17) }
                        }
                        Rectangle {
                            width: parent.width; height: fixT.height + mp.d(20); radius: mp.d(12)
                            color: C.alpha(mp.look.surfaceLowest, 0.6)
                            Text { id: fixT; x: mp.d(14); y: mp.d(10); width: parent.width - mp.d(28); text: fc.modelData.fix; wrapMode: Text.WrapAnywhere
                                   color: mp.look.fg; opacity: 0.9; font.family: Tokens.font.mono; font.pixelSize: mp.d(14) }
                        }
                    }
                }
            }
            Heading { studio: mp; text: "IN PLACE"; visible: parent.passes.length > 0 }
            Card {
                id: okCard
                visible: parent.passes.length > 0
                studio: mp
                width: Math.min(parent.width, mp.d(940))
                fkey: "hl:ok"
                act: "Run again"
                desc: "<b>In place</b> " + parent.passes.length + " checks pass."
                onActivated: mp.runDoctor()
                readonly property var list: parent.passes
                Grid {
                    columns: 2
                    columnSpacing: mp.d(24); rowSpacing: mp.d(10)
                    Repeater {
                        model: okCard.list
                        Row {
                            required property var modelData
                            spacing: mp.d(8)
                            Text { text: "check"; color: mp.look.ok; font.family: Tokens.font.icons; font.pixelSize: mp.d(18) }
                            Text { width: (okCard.width - 2 * okCard.pad - mp.d(24)) / 2 - mp.d(26); text: modelData.what; elide: Text.ElideRight; color: mp.look.fg; opacity: 0.82; font.family: Tokens.font.ui; font.pixelSize: mp.d(14) }
                        }
                    }
                }
            }
        }
    }

    // ---- Credits
    Component {
        id: creditsC
        Column {
            id: cr
            width: bodyLoader.width
            spacing: mp.d(16)
            readonly property real cardW: Math.floor((width - 2 * mp.d(16)) / 3)
            Heading { studio: mp; text: "PEOPLE"; topPadding: 0 }
            Flow {
                width: parent.width
                spacing: mp.d(16)
                Repeater {
                    model: (mp.info && mp.info.contributors) || []
                    Card {
                        id: pc
                        required property var modelData
                        required property int index
                        readonly property string link: modelData.name === "Claude" ? "https://claude.com/claude-code"
                                                       : modelData.name === "Gemini" ? "https://gemini.google.com"
                                                       : modelData.name === "zinoxx" ? "https://github.com/Zinoxx0"
                                                       : modelData.role === "Author" && mp.repo.url ? mp.repo.url.replace(/\/[^\/]+$/, "") : ""
                        studio: mp
                        width: cr.cardW
                        fkey: "who:" + index
                        act: link ? "Open their page" : "Choose"
                        desc: "<b>" + modelData.name + "</b> " + modelData.role + " · in " + modelData.commits + " commits"
                        onActivated: mp.openUrl(link, modelData.name + "'s page")
                        Row {
                            spacing: mp.d(16)
                            Rectangle {
                                width: mp.d(54); height: width; radius: width / 2
                                gradient: Gradient { orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: pc.index === 0 ? mp.look.primary : mp.look.secondary }
                                    GradientStop { position: 1; color: pc.index === 0 ? mp.look.tertiary : mp.look.primary } }
                                Text { anchors.centerIn: parent; text: pc.modelData.name.slice(0, 1).toUpperCase(); color: "#ffffff"; font.family: mp.wideFamily; font.variableAxes: mp.wideAxes(112, 700); font.pixelSize: mp.d(24) }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: mp.d(5)
                                Text { text: pc.modelData.name; color: mp.look.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: mp.d(18) }
                                Text { width: pc.width - 2 * pc.pad - mp.d(70); elide: Text.ElideRight; text: pc.modelData.role + " · " + pc.modelData.commits + " commits"; color: mp.look.fgDim; font.family: Tokens.font.ui; font.pixelSize: mp.d(14) }
                            }
                        }
                    }
                }
            }
            Repeater {
                model: (mp.info && mp.info.credits) || []
                Column {
                    id: grp
                    required property var modelData
                    required property int index
                    width: cr.width
                    spacing: mp.d(16)
                    Heading { studio: mp; text: grp.modelData.name.toUpperCase() }
                    Flow {
                        width: parent.width
                        spacing: mp.d(16)
                        Repeater {
                            model: grp.modelData.items
                            Card {
                                id: pk
                                required property var modelData
                                required property int index
                                studio: mp
                                width: cr.cardW
                                pad: mp.d(18)
                                fkey: "pkg:" + grp.index + ":" + index
                                act: "Open its page"
                                desc: "<b>" + modelData.name + "</b> " + modelData.what + (modelData.by ? " · by " + modelData.by : "") + " · " + modelData.license
                                onActivated: mp.openUrl(modelData.url, modelData.name + "'s page")
                                Column {
                                    width: parent.width
                                    spacing: mp.d(6)
                                    Item {
                                        width: parent.width; height: nm.height
                                        Text { id: nm; width: parent.width - vr.width - mp.d(8); elide: Text.ElideRight; text: pk.modelData.name; color: mp.look.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: mp.d(16.5) }
                                        Text { id: vr; anchors.right: parent.right; anchors.baseline: nm.baseline
                                               text: pk.modelData.version || (pk.modelData.installed === false ? "not installed" : "")
                                               color: pk.modelData.installed === false ? mp.look.fgDim : mp.look.primary; font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: mp.d(13); font.features: { "tnum": 1 } }
                                    }
                                    Text { width: parent.width; text: pk.modelData.what; elide: Text.ElideRight; color: mp.look.fg; opacity: 0.78; font.family: Tokens.font.ui; font.pixelSize: mp.d(14) }
                                    Text { width: parent.width; elide: Text.ElideRight; text: [pk.modelData.license, pk.modelData.by || "", pk.modelData.optional ? "optional" : ""].filter(Boolean).join(" · ")
                                           color: mp.look.fgDim; font.family: Tokens.font.ui; font.pixelSize: mp.d(12.5) }
                                }
                            }
                        }
                    }
                }
            }
            Text {
                topPadding: mp.d(10)
                width: parent.width; wrapMode: Text.WordWrap
                text: "Atom Plasma by ViVia Technologies is free software under the " + ((mp.info && mp.info.license) || "GPL-3.0-or-later") + ". Every project above keeps its own license."
                color: mp.look.fgDim; font.family: Tokens.font.ui; font.pixelSize: mp.d(14)
            }
        }
    }

    // ---- This machine
    Component {
        id: systemC
        Column {
            width: bodyLoader.width
            spacing: mp.d(18)
            Row {
                spacing: mp.d(12)
                StudioChip { studio: mp; fkey: "sys:copy"; icon: "content_copy"; text: "Copy for a bug report"; act: "Copy"
                             desc: "<b>Copy for a bug report</b> The version, the machine, the features on and anything Health found."
                             onActivated: mp.copy(mp.bugReport(), "The report") }
                StudioChip { studio: mp; fkey: "sys:issue"; icon: "bug_report"; text: "Report an issue"; act: "Open"; visible: !!mp.repo.url
                             desc: "<b>Report an issue</b> Opens a new issue on GitHub (paste the report in it)."
                             onActivated: mp.openUrl(mp.repo.url + "/issues/new", "GitHub") }
                StudioChip { studio: mp; fkey: "sys:repo"; icon: "code"; text: "Source"; act: "Open"; visible: !!mp.repo.url
                             desc: "<b>Source</b> Atom Plasma on GitHub (ViVia Technologies)."
                             onActivated: mp.openUrl(mp.repo.url, "GitHub") }
                StudioChip { studio: mp; fkey: "sys:site"; icon: "language"; text: "Website"; act: "Open"
                             desc: "<b>Website</b> Atom Plasma on viviatechnologies.com."
                             onActivated: mp.openUrl("https://viviatechnologies.com/atomplasma/", "viviatechnologies.com") }
                StudioChip { studio: mp; fkey: "sys:folder"; icon: "folder_open"; text: "Its folder"; act: "Open"
                             desc: "<b>Its folder</b> Where Atom Plasma lives: ~/.config/plasma-rice."
                             onActivated: mp.openUrl("file://" + sh.home + "/.config/plasma-rice", "the folder") }
            }
            Card {
                id: facts
                studio: mp
                width: Math.min(parent.width, mp.d(940))
                fkey: "sys:facts"
                act: "Copy"
                desc: "<b>This machine</b>" + (mp.actKey ? " " + mp.actKey + " copies it all for a bug report." : " Version, hardware and environment.")
                onActivated: mp.copy(mp.bugReport(), "The report")
                readonly property var rows: [
                    ["Atom Plasma", mp.version + (mp.repo.commit ? "  ·  " + mp.repo.commit + (mp.repo.dirty ? ", local changes" : "") : ""), ""],
                    ["Plasma", mp.sys.plasma || "?", mp.sys.supported ? "ok" : "warn"],
                    ["Frameworks", mp.sys.frameworks || "?", ""],
                    ["Qt", mp.sys.qt || "?", ""],
                    ["Session", mp.sys.session || "?", mp.sys.session && mp.sys.session !== "Wayland" ? "warn" : ""],
                    ["System", mp.sys.os || "?", ""],
                    ["Kernel", mp.sys.kernel || "?", ""],
                    ["Processor", mp.sys.cpu || "", ""],
                    ["Memory", mp.sys.memory || "", ""],
                ].concat((mp.sys.gpus || []).map((g, i) => [mp.sys.gpus.length > 1 ? "Graphics " + (i + 1) : "Graphics", g, ""])).filter(r => r[1])
                Column {
                    width: parent.width
                    spacing: mp.d(12)
                    Repeater {
                        model: facts.rows
                        Row {
                            required property var modelData
                            spacing: mp.d(18)
                            Text { width: mp.d(150); text: modelData[0]; color: mp.look.fgDim; font.family: Tokens.font.ui; font.pixelSize: mp.d(15) }
                            Text { text: modelData[1]; color: mp.look.fg; font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: mp.d(15) }
                            Text { visible: modelData[2] !== ""; text: modelData[2] === "ok" ? "check_circle" : "warning"; color: modelData[2] === "ok" ? mp.look.ok : mp.look.bad
                                   font.family: Tokens.font.icons; font.pixelSize: mp.d(18) }
                            Text { visible: modelData[2] === "warn"; text: modelData[0] === "Plasma" ? "made for " + mp.sys.supportedPlasma + ": parts may break" : "made for Wayland"
                                   color: mp.look.bad; font.family: Tokens.font.ui; font.pixelSize: mp.d(14) }
                        }
                    }
                }
            }
            Heading { studio: mp; text: "FEATURES ON THIS MACHINE" }
            Card {
                id: feats
                studio: mp
                width: Math.min(parent.width, mp.d(940))
                fkey: "sys:features"
                act: "Choose"
                readonly property var list: (mp.info && mp.info.features) || []
                desc: "<b>Features</b> " + list.filter(f => f.on).length + " of " + list.length + " on · each is auto, on or off under features in ~/.config/atom-plasma/settings.json"
                Grid {
                    columns: 2
                    columnSpacing: mp.d(24); rowSpacing: mp.d(14)
                    Repeater {
                        model: feats.list
                        Row {
                            required property var modelData
                            spacing: mp.d(10)
                            Rectangle { y: mp.d(6); width: mp.d(10); height: width; radius: width / 2; color: modelData.on ? mp.look.primary : "transparent"
                                        border.width: modelData.on ? 0 : mp.d(1.5); border.color: mp.look.fgDim }
                            Column {
                                spacing: mp.d(3)
                                width: (feats.width - 2 * feats.pad - mp.d(24)) / 2 - mp.d(20)
                                Text { text: modelData.id.replace(/_/g, " ").replace(/^./, c => c.toUpperCase()) + (modelData.setting !== "auto" ? "  (set " + modelData.setting + ")" : "")
                                       color: modelData.on ? mp.look.fg : mp.look.fgDim; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: mp.d(15) }
                                Text { width: parent.width; elide: Text.ElideRight
                                       text: modelData.on || !modelData.missing.length ? modelData.what : "needs " + modelData.missing.join(", ").replace(/_/g, " ")
                                       color: mp.look.fgDim; font.family: Tokens.font.ui; font.pixelSize: mp.d(13) }
                            }
                        }
                    }
                }
            }
        }
    }

    // the lens's ring (over everything)
    Rectangle {
        visible: mp.active && !!mp.focused && mp.lw > 0
        x: mp.lx; y: mp.ly; width: mp.lw; height: mp.lh
        radius: mp.lr
        color: "transparent"
        border.width: mp.d(2.5)
        border.color: mp.look.fg
        Behavior on x { enabled: !mp.lensJump; NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Behavior on y { enabled: !mp.lensJump; NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Behavior on width { enabled: !mp.lensJump; NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Behavior on height { enabled: !mp.lensJump; NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
    }

    // the footer: what the focus is, and the keys (a pad's buttons when it's the one in use)
    Item {
        opacity: mp.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.ms(250) } }
        x: mp.d(72)
        width: mp.width - 2 * mp.d(72)
        y: mp.height - mp.d(34) - height
        height: mp.d(40)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - (hintsRow.visible ? hintsRow.width + mp.d(40) : 0)
            elide: Text.ElideRight
            text: mp.focused ? mp.focused.desc : ""
            textFormat: Text.StyledText
            color: mp.look.fgDim
            font.family: Tokens.font.ui; font.pixelSize: mp.d(15.5)
        }
        Row {
            id: hintsRow
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            spacing: mp.d(26)
            opacity: mp.inputMode === "pointer" ? 0 : 1
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Tokens.ms(260) } }
            Repeater {
                model: {
                    const f = mp.focused, pad = mp.padHints
                    return [[pad ? ["A"] : ["Enter"], f ? f.act : "Choose"], [pad ? ["LB", "RB"] : ["Tab"], "Section"], [pad ? ["B"] : ["Esc"], f && !f.inSide ? "Back" : "Close"]]
                }
                Row {
                    required property var modelData
                    spacing: mp.d(9)
                    Repeater {
                        model: modelData[0]
                        Rectangle {
                            required property var modelData
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property bool face: modelData.length === 1
                            width: Math.max(mp.d(28), kt.implicitWidth + mp.d(14)); height: mp.d(28)
                            radius: face ? height / 2 : mp.d(8)
                            color: "transparent"
                            border.width: mp.d(1.5); border.color: C.alpha(mp.look.fg, 0.38)
                            Text { id: kt; anchors.centerIn: parent; text: modelData; color: mp.look.fg; font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: mp.d(12.5) }
                        }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; color: mp.look.fgDim; font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: mp.d(15) }
                }
            }
        }
    }

    // news (checked, copied, ...)
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: mp.height - mp.d(100) - height - (mp.news ? 0 : mp.d(16))
        width: newsT.width + mp.d(44); height: mp.d(46); radius: mp.d(16)
        color: mp.look.fg
        opacity: mp.news ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.ms(300) } }
        Behavior on y { NumberAnimation { duration: Tokens.ms(400); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Text { id: newsT; anchors.centerIn: parent; text: mp.news || " "; color: mp.look.surfaceLowest; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: mp.d(16) }
    }

    Component.onCompleted: load()
}
