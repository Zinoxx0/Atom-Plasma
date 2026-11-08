pragma Singleton
import QtQuick
import org.kde.notificationmanager as NM
import org.kde.plasma.private.clipboard as Clip

// The notifications' memory, for the whole shell: the history (every notification still around, newest
// first) grouped by app, and which apps have news you haven't seen: an app's notifications count as seen
// once its window has the focus, or once you've opened its group. The status island draws the unseen
// ones as beads; the control center lists the history. Holding a Notifications model also keeps
// plasmashell the session's notification server (the stock tray's notifications applet is gone), and it
// keeps Klipper running (below).
QtObject {
    id: n

    property NM.Notifications history: NM.Notifications {
        showNotifications: true
        showJobs: false
        showExpired: true
        showDismissed: true
        groupMode: NM.Notifications.GroupDisabled
        sortMode: NM.Notifications.SortByDate
        sortOrder: Qt.DescendingOrder
        onCountChanged: n.schedule()
        onDataChanged: n.schedule()
        onModelReset: n.schedule()
    }

    // Klipper (the clipboard's history, Meta+V) lives as long as something holds its model: with the stock
    // tray (and its clipboard applet) gone, this is it
    property Clip.HistoryModel clipboard: Clip.HistoryModel {}

    // app key -> when it was last seen (ms)
    property var seen: ({})
    // [{ key, name, icon, entry, count, unread, items: [{ row, id, summary, body, created, icon, image, hasDefault }] }], newest app first
    property var groups: []
    readonly property var unseen: groups.filter(g => g.unread > 0)
    readonly property int unreadTotal: unseen.reduce((s, g) => s + g.unread, 0)

    function role(r, name) { return history.data(history.index(r, 0), NM.Notifications[name + "Role"]) }
    function keyOf(entry, app) { return String(entry || app || "").toLowerCase() }
    function schedule() { Qt.callLater(scan) }
    function scan() {
        const by = {}, order = []
        for (let r = 0; r < history.count; r++) {
            if (role(r, "Type") !== NM.Notifications.NotificationType) continue
            const entry = role(r, "DesktopEntry"), app = role(r, "ApplicationName")
            const key = keyOf(entry, app)
            if (!key) continue
            let g = by[key]
            if (!g) {
                g = by[key] = { key: key, name: app || entry, icon: role(r, "ApplicationIconName") || role(r, "IconName") || entry || "", entry: entry || "",
                                count: 0, unread: 0, items: [] }
                order.push(g)
            }
            const created = role(r, "Created")
            g.count++
            if (!(created <= (seen[key] || 0))) g.unread++
            if (g.items.length < 6)
                g.items.push({ row: r, id: role(r, "Id"), summary: role(r, "Summary") || "", body: role(r, "Body") || "",
                               created: created, icon: role(r, "IconName") || "", hasDefault: role(r, "HasDefaultAction") === true })
        }
        groups = order
    }
    function markSeen(key) {
        if (!key) return
        const next = Object.assign({}, seen)
        next[key] = Date.now()
        seen = next
        scan()
    }
    function close(row) { history.close(history.index(row, 0)) }
    function activate(row) {
        const idx = history.index(row, 0)
        if (role(row, "HasDefaultAction") === true) history.invokeDefaultAction(idx)
        history.expire(idx)
    }
    function clearApp(key) {
        for (let r = history.count - 1; r >= 0; r--)
            if (keyOf(role(r, "DesktopEntry"), role(r, "ApplicationName")) === key) history.close(history.index(r, 0))
        markSeen(key)
    }
    function clearAll() {
        for (let r = history.count - 1; r >= 0; r--)
            if (role(r, "Type") === NM.Notifications.NotificationType) history.close(history.index(r, 0))
    }

    // its window has the focus: its news has been seen
    property Connections focus: Connections {
        target: Windows
        function onActiveAppChanged() {
            const a = Windows.activeApp
            if (!a) return
            for (const g of n.groups)
                if (g.unread > 0 && (a === g.key || a.indexOf(g.key) >= 0 || g.key.indexOf(a) >= 0 || a === String(g.name).toLowerCase()))
                    n.markSeen(g.key)
        }
    }
    Component.onCompleted: schedule()
}
