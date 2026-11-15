pragma Singleton
import QtQuick
import org.kde.taskmanager as TaskManager

// What the windows are doing, for the shell: which screen holds the active window (notifications go
// there), the active app (its unread notifications count as seen), and the screens a fullscreen window
// covers (the shell's surfaces step aside there, so games keep direct scan-out). One model for every
// widget; it re-reads only when a role it cares about changes.
QtObject {
    id: w

    readonly property var screens: Array.prototype.slice.call(Qt.application.screens)
    property string activeScreen: ""            // screen name of the active window ("" = none)
    property string activeApp: ""               // its app id, lower case
    // the screens a fullscreen window covers: KWin's own answer when its rice_islands script is running (a
    // fullscreen window IN FRONT of the bar, Shell.bar.covered; the same answer that moves the islands), else
    // this model's guess (`fullscreen`: the top window there is fullscreen or covers the whole screen)
    property var fullscreen: ({})               // screen name -> true (the guess)
    function isFullscreen(name) {
        const b = Shell.bar
        return b && b.covered ? b.covered.indexOf(name) >= 0 : fullscreen[name] === true
    }
    // where the windows are (not minimized), global logical rects: what sits over a spot of the desktop
    property var rects: []
    function occupied(r) {
        if (!r) return false
        return rects.some(g => g.x < r.x + r.width && r.x < g.x + g.width && g.y < r.y + r.height && r.y < g.y + g.height)
    }

    property TaskManager.TasksModel tasks: TaskManager.TasksModel {
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortLastActivated
        filterByScreen: false
        filterByVirtualDesktop: false
        filterByActivity: false
        filterHidden: false
        onDataChanged: (topLeft, bottomRight, roles) => { if (w.relevant(roles)) w.schedule() }     // qmllint disable signal-handler-parameters
        onRowsInserted: w.schedule()
        onRowsRemoved: w.schedule()
        onModelReset: w.schedule()
        onActiveTaskChanged: w.schedule()
    }
    readonly property var roles: {
        const R = TaskManager.AbstractTasksModel
        return [R.IsWindow, R.IsMinimized, R.IsActive, R.AppId, R.ScreenGeometry, R.Geometry, R.IsFullScreen, R.IsMaximized]
    }
    function relevant(r) { return !r || r.length === 0 || r.some(x => roles.indexOf(x) >= 0) }
    function schedule() { Qt.callLater(scan) }

    function screenAt(g) {
        if (!g) return null
        return screens.find(s => Math.abs(g.x - s.virtualX) < 2 && Math.abs(g.y - s.virtualY) < 2
                                 && Math.abs(g.width - s.width) < 2 && Math.abs(g.height - s.height) < 2) ?? null
    }
    function covers(g, s) {
        return !!g && g.x <= s.virtualX + 1 && g.y <= s.virtualY + 1
            && g.x + g.width >= s.virtualX + s.width - 1 && g.y + g.height >= s.virtualY + s.height - 1
    }
    function scan() {
        const R = TaskManager.AbstractTasksModel
        const seen = {}, fs = {}, rs = []
        let act = "", app = ""
        // most recent first: the first window met on a screen is the one on top there
        for (let i = 0; i < tasks.count; i++) {
            const idx = tasks.index(i, 0)
            if (tasks.data(idx, R.IsWindow) !== true || tasks.data(idx, R.IsMinimized) === true) continue
            const g = tasks.data(idx, R.Geometry)
            if (g && g.width > 0) rs.push({ x: g.x, y: g.y, width: g.width, height: g.height })
            const s = screenAt(tasks.data(idx, R.ScreenGeometry))
            if (!s) continue
            if (tasks.data(idx, R.IsActive) === true && !act) {
                act = s.name
                app = String(tasks.data(idx, R.AppId) || "").toLowerCase()
            }
            if (seen[s.name]) continue
            seen[s.name] = true
            fs[s.name] = tasks.data(idx, R.IsFullScreen) === true
                || (tasks.data(idx, R.IsMaximized) !== true && covers(tasks.data(idx, R.Geometry), s))
        }
        if (act !== activeScreen) activeScreen = act
        if (app !== activeApp) activeApp = app
        if (JSON.stringify(fs) !== JSON.stringify(fullscreen)) fullscreen = fs
        if (JSON.stringify(rs) !== JSON.stringify(rects)) rects = rs
    }
    Component.onCompleted: schedule()

    // ------------------------------------------------------------------ clearing the desk (the launcher)
    // The launcher presents itself on the bare desktop of ITS screen: the windows there are minimized
    // (KWin's magic lamp sends them into their Glimpse pins) and, when it closes or moves to another
    // screen, exactly those come back. The other screens keep their windows. KWin's own show-desktop
    // can't do this: it's for every screen, and it ends the moment the launcher takes the keyboard.
    property var cleared: ({})                  // screen name -> window ids minimized there, most recently used first
    // Who holds a screen cleared (the launcher, the power page: "owner"): its windows come back only when the
    // last one lets go, and a moment later, so one handing the screen to another (the launcher's power button
    // opens the power page) doesn't bring them back in between.
    property var holders: ({})                  // screen name -> { owner: true }
    property var pending: ({})                  // screen name -> true: coming back once the grace is over
    function hold(scr, owner) {
        const h = Object.assign({}, holders); h[scr] = Object.assign({}, h[scr] || {}); h[scr][owner || "launcher"] = true; holders = h
        if (pending[scr]) { const p = Object.assign({}, pending); delete p[scr]; pending = p }
    }
    function idsAt(idx) {
        return Array.prototype.slice.call(tasks.data(idx, TaskManager.AbstractTasksModel.WinIdList) || []).map(String)
    }
    function clear(scr, owner) {
        hold(scr, owner)
        const R = TaskManager.AbstractTasksModel
        const out = []
        for (let i = 0; i < tasks.count; i++) {
            const idx = tasks.index(i, 0)
            if (tasks.data(idx, R.IsWindow) !== true || tasks.data(idx, R.IsMinimized) === true) continue
            if (tasks.data(idx, R.SkipTaskbar) === true) continue
            const s = screenAt(tasks.data(idx, R.ScreenGeometry))
            if (!s || s.name !== scr) continue
            const ids = idsAt(idx)
            if (!ids.length) continue
            out.push(ids[0])
            tasks.requestToggleMinimized(idx)
        }
        const next = Object.assign({}, cleared)
        next[scr] = (next[scr] || []).concat(out)
        cleared = next
        if (Shell.debug) console.warn("ATOM windows cleared", scr, out.length, "for", owner || "launcher")
    }
    function restore(scr, owner) {
        const h = Object.assign({}, holders)
        if (h[scr]) { h[scr] = Object.assign({}, h[scr]); delete h[scr][owner || "launcher"]; if (!Object.keys(h[scr]).length) delete h[scr] }
        holders = h
        if (h[scr]) return                      // another still holds it
        const p = Object.assign({}, pending); p[scr] = true; pending = p
        graceTimer.restart()
    }
    property Timer graceTimer: Timer { interval: 140; onTriggered: { for (const scr in w.pending) w.bringBack(scr); w.pending = ({}) } }
    function bringBack(scr) {
        const R = TaskManager.AbstractTasksModel
        const ids = (cleared[scr] || []).slice().reverse()   // least recently used first: the most recent ends on top
        const next = Object.assign({}, cleared)
        delete next[scr]
        cleared = next
        if (Shell.debug) console.warn("ATOM windows restored", scr, ids.length)
        let last = null
        for (const id of ids) {
            for (let i = 0; i < tasks.count; i++) {
                const idx = tasks.index(i, 0)
                if (tasks.data(idx, R.IsMinimized) !== true) continue
                if (idsAt(idx).indexOf(id) >= 0) { tasks.requestToggleMinimized(idx); last = idx; break }
            }
        }
        // the one used most recently gets the keyboard back (it had it before): a window brought back after
        // the shell's surface is gone isn't activated by KWin on its own
        if (last) tasks.requestActivate(last)
    }
    // ------------------------------------------------------------------ an app's window, from its tray icon
    // A tray icon knows its app's process; the app's window has the same one (else it goes by app id).
    // Its row, most recently used first, or -1 when the app has no window (closed to the tray).
    function windowOf(pid, names) {
        const R = TaskManager.AbstractTasksModel
        const ids = (names || []).map(n => String(n || "").toLowerCase()).filter(n => n.length > 1)
        let byName = -1
        for (let i = 0; i < tasks.count; i++) {
            const idx = tasks.index(i, 0)
            if (tasks.data(idx, R.IsWindow) !== true || tasks.data(idx, R.SkipTaskbar) === true) continue
            if (pid > 0 && tasks.data(idx, R.AppPid) === pid) return i
            if (byName < 0 && ids.indexOf(String(tasks.data(idx, R.AppId) || "").toLowerCase()) >= 0) byName = i
        }
        return byName
    }
    // its app id, lower case ("" when it has no window)
    function appIdOf(pid, names) {
        const r = windowOf(pid, names)
        return r < 0 ? "" : String(tasks.data(tasks.index(r, 0), TaskManager.AbstractTasksModel.AppId) || "").toLowerCase()
    }
    // "minimized", "active", "open", or "" when it has no window
    function stateOf(pid, names) {
        const R = TaskManager.AbstractTasksModel
        const r = windowOf(pid, names)
        if (r < 0) return ""
        const idx = tasks.index(r, 0)
        return tasks.data(idx, R.IsMinimized) === true ? "minimized" : tasks.data(idx, R.IsActive) === true ? "active" : "open"
    }
    // a tray icon's click, by Glimpse's rules: a minimized or covered window comes back (activating
    // un-minimizes), the focused one goes down. false when there's no window: the app decides (it opens one)
    function summon(pid, names) {
        const R = TaskManager.AbstractTasksModel
        const r = windowOf(pid, names)
        if (r < 0) return false
        const idx = tasks.index(r, 0)
        if (tasks.data(idx, R.IsMinimized) !== true && tasks.data(idx, R.IsActive) === true) tasks.requestToggleMinimized(idx)
        else tasks.requestActivate(idx)
        return true
    }

    // windows something else is bringing back (a click in Glimpse while the launcher is open): the
    // launcher's restore leaves them alone, so they come back once, on top
    function release(ids) {
        const drop = Array.prototype.slice.call(ids || []).map(String)
        if (!drop.length) return
        const next = {}
        for (const scr in cleared) next[scr] = cleared[scr].filter(id => drop.indexOf(id) < 0)
        cleared = next
    }
}
