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
    property var fullscreen: ({})               // screen name -> true while a fullscreen window covers it
    function isFullscreen(name) { return fullscreen[name] === true }

    property TaskManager.TasksModel tasks: TaskManager.TasksModel {
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortLastActivated
        filterByScreen: false
        filterByVirtualDesktop: false
        filterByActivity: false
        filterHidden: false
        onDataChanged: (topLeft, bottomRight, roles) => { if (w.relevant(roles)) w.schedule() }
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
        const seen = {}, fs = {}
        let act = "", app = ""
        // most recent first: the first window met on a screen is the one on top there
        for (let i = 0; i < tasks.count; i++) {
            const idx = tasks.index(i, 0)
            if (tasks.data(idx, R.IsWindow) !== true || tasks.data(idx, R.IsMinimized) === true) continue
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
    }
    Component.onCompleted: schedule()

    // ------------------------------------------------------------------ clearing the desk (the launcher)
    // The launcher presents itself on the bare desktop: every window is minimized (KWin's magic lamp sends
    // them into their Glimpse pins) and, when it closes, exactly those come back. KWin's own show-desktop
    // can't do this: it ends the moment the launcher takes the keyboard.
    property var cleared: []                    // window ids it minimized, most recently used first
    function idsAt(idx) {
        return Array.prototype.slice.call(tasks.data(idx, TaskManager.AbstractTasksModel.WinIdList) || []).map(String)
    }
    function clear() {
        const R = TaskManager.AbstractTasksModel
        const out = []
        for (let i = 0; i < tasks.count; i++) {
            const idx = tasks.index(i, 0)
            if (tasks.data(idx, R.IsWindow) !== true || tasks.data(idx, R.IsMinimized) === true) continue
            if (tasks.data(idx, R.SkipTaskbar) === true) continue
            const ids = idsAt(idx)
            if (!ids.length) continue
            out.push(ids[0])
            tasks.requestToggleMinimized(idx)
        }
        cleared = cleared.concat(out)
    }
    function restore() {
        const R = TaskManager.AbstractTasksModel
        const ids = cleared.slice().reverse()   // least recently used first: the most recent ends on top
        cleared = []
        for (const id of ids) {
            for (let i = 0; i < tasks.count; i++) {
                const idx = tasks.index(i, 0)
                if (tasks.data(idx, R.IsMinimized) !== true) continue
                if (idsAt(idx).indexOf(id) >= 0) { tasks.requestToggleMinimized(idx); break }
            }
        }
    }
}
