import QtQuick
import QtCore

// Claude Code's usage limits (~/.cache/claude-usage.json, which ~/.claude/statusline.sh writes while a
// session runs) and what they mean for Clawd: how full each window is, its pace, whether it's live,
// and how tired Clawd looks (`peak` -> Clawd.usage; `mood` is only happy | sleep | limited). Watched,
// not polled (WatchedJson); `now` ticks every 30 s, every second while `fast` (a popup with countdowns).
//
//   ClaudeUsage { id: claude }      Clawd { mood: claude.mood; usage: claude.peak; working: claude.working }
Item {
    id: cu
    visible: false

    property bool active: true
    property bool fast: false
    readonly property var usage: file.value
    property real now: Date.now() / 1000

    WatchedJson {
        id: file
        path: String(StandardPaths.writableLocation(StandardPaths.GenericCacheLocation)).replace(/^file:\/\//, "") + "/claude-usage.json"
        active: cu.active
        onChanged: cu.now = Date.now() / 1000
    }
    Timer { interval: cu.fast ? 1000 : 30000; running: cu.active; repeat: true; onTriggered: cu.now = Date.now() / 1000 }

    // one limit window: % used (0 once it has reset), when it resets, and the even pace (% of the window gone)
    function windowInfo(key, length) {
        const w = usage?.[key] ?? {}
        const reset = Number(w.resets_at ?? 0)
        const expired = reset > 0 && reset <= now
        const pct = expired ? 0 : Number(w.used_percentage ?? 0)
        const start = reset - length
        const pace = reset > 0 && !expired ? Math.max(0, Math.min(100, (now - start) / length * 100)) : -1
        return { pct: pct, reset: reset, expired: expired, pace: pace }
    }
    readonly property var session: windowInfo("five_hour", 5 * 3600)
    readonly property var weekly: windowInfo("seven_day", 7 * 86400)
    readonly property bool hasData: usage !== null
    readonly property real updatedAgo: hasData ? now - Number(usage.updated ?? 0) : 1e9
    readonly property bool stale: updatedAgo > 30 * 60
    readonly property real peak: Math.max(session.pct, weekly.pct)
    // how full the usage is shows as how tired Clawd looks (Clawd.usage), not as a mood
    readonly property string mood: peak >= 100 ? "limited" : (stale || !hasData) ? "sleep" : "happy"
    readonly property bool working: hasData && updatedAgo < 180
    // using the session faster than its even pace: a blush
    readonly property bool warm: session.pace >= 0 && session.pct >= 25 && session.pct > session.pace + 15
    // a window that was half used or more just reset: a party for 15 minutes
    property real lastSession: -1
    property real lastWeekly: -1
    property real partyUntil: 0
    onSessionChanged: { if (lastSession >= 50 && session.pct < 5) partyUntil = now + 900; lastSession = session.pct }
    onWeeklyChanged: { if (lastWeekly >= 50 && weekly.pct < 5) partyUntil = now + 900; lastWeekly = weekly.pct }
    readonly property bool celebrate: now < partyUntil && mood !== "limited"
    // limited: the window that ran out, and how much of its wait is still to go (Clawd's hourglass)
    readonly property var limitWin: session.pct >= 100 ? session : weekly
    readonly property real sand: Math.max(0, Math.min(1, (limitWin.reset - now) / (session.pct >= 100 ? 5 * 3600 : 7 * 86400)))
}
