import QtQuick
import QtCore

// Gemini / Antigravity usage limits: watches T3 Code's live cache (~/.t3/caches/antigravity.json)
// and a standalone local cache (~/.cache/gemini-usage.json) — whichever was updated more recently
// wins. Zero extra network requests or polling; `now` ticks every 30 s (1 s while popup is open).
Item {
    id: gu
    visible: false

    property bool active: true
    property bool fast: false
    property bool busy: false
    readonly property string homeDir: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "")
    readonly property string cacheDir: String(StandardPaths.writableLocation(StandardPaths.GenericCacheLocation)).replace(/^file:\/\//, "")
    property real now: Date.now() / 1000

    function parseEpoch(v) {
        if (v === undefined || v === null || v === "") return 0
        if (typeof v === "number") return isFinite(v) ? (v > 1e12 ? v / 1000 : v) : 0
        const ms = Date.parse(String(v))
        return isFinite(ms) ? ms / 1000 : 0
    }

    function timestampOf(obj) {
        if (!obj || typeof obj !== "object") return 0
        const ul = obj.usageLimits && typeof obj.usageLimits === "object" ? obj.usageLimits : obj
        return Math.max(
            parseEpoch(ul.checkedAt),
            parseEpoch(ul.updated),
            parseEpoch(ul.checked),
            parseEpoch(obj.checkedAt)
        )
    }

    WatchedJson {
        id: t3File
        path: gu.homeDir + "/.t3/caches/antigravity.json"
        active: gu.active
        onChanged: gu.now = Date.now() / 1000
    }
    WatchedJson {
        id: localFile
        path: gu.cacheDir + "/gemini-usage.json"
        active: gu.active
        onChanged: gu.now = Date.now() / 1000
    }
    // WatchedJson updates immediately when the cache file changes; this timer only advances `now`
    // for minute countdowns and pace ticks (5 s while popup is open & active, 15 s when idle, 30 s closed).
    Timer { interval: gu.fast ? (gu.busy ? 5000 : 15000) : 30000; running: gu.active; repeat: true; onTriggered: gu.now = Date.now() / 1000 }
    onActiveChanged: if (active) now = Date.now() / 1000

    readonly property real t3At: timestampOf(t3File.value)
    readonly property real localAt: timestampOf(localFile.value)
    readonly property bool usingLocal: localFile.value !== null && (t3File.value === null || localAt > t3At)
    readonly property var raw: usingLocal ? localFile.value : t3File.value
    readonly property string sourceName: !hasData ? "" : usingLocal ? "Local cache" : "T3 Code"

    function extractWindow(obj, targetId, altKey, defaultLen, defaultLabel) {
        const empty = { pct: 0, reset: 0, expired: false, pace: -1, label: defaultLabel, length: defaultLen, present: false }
        if (!obj || typeof obj !== "object") return empty
        const ul = obj.usageLimits && typeof obj.usageLimits === "object" ? obj.usageLimits : obj
        let w = null
        if (Array.isArray(ul.windows)) {
            for (let i = 0; i < ul.windows.length; i++) {
                if (ul.windows[i] && ul.windows[i].id === targetId) { w = ul.windows[i]; break }
            }
        } else if (altKey && ul[altKey] && typeof ul[altKey] === "object") {
            w = ul[altKey]
        }
        if (!w) return empty
        const len = Number(w.windowDurationMins) > 0 ? Number(w.windowDurationMins) * 60 : defaultLen
        const reset = parseEpoch(w.resetsAt !== undefined ? w.resetsAt : w.resets_at)
        const expired = reset > 0 && reset <= now
        const rawPct = w.usedPercent !== undefined ? w.usedPercent : w.used_percentage
        const pct = expired ? 0 : Math.max(0, Math.min(100, Number(rawPct ?? 0)))
        const start = reset - len
        const pace = reset > 0 && !expired ? Math.max(0, Math.min(100, (now - start) / len * 100)) : -1
        return {
            pct: isFinite(pct) ? pct : 0,
            reset: reset,
            expired: expired,
            pace: pace,
            label: String(w.label || defaultLabel),
            length: len,
            present: true,
        }
    }

    readonly property var session: extractWindow(raw, "gemini-5h", "five_hour", 5 * 3600, "Gemini · 5-hour")
    readonly property var weekly: extractWindow(raw, "gemini-weekly", "seven_day", 7 * 86400, "Gemini · Weekly")
    readonly property var sharedSession: extractWindow(raw, "3p-5h", "", 5 * 3600, "Claude & GPT · 5-hour")
    readonly property var sharedWeekly: extractWindow(raw, "3p-weekly", "", 7 * 86400, "Claude & GPT · Weekly")
    readonly property bool hasData: session.present || weekly.present
    readonly property bool hasShared: sharedSession.present || sharedWeekly.present
    readonly property real updatedAgo: hasData ? Math.max(0, now - Math.max(t3At, localAt)) : 1e9
    readonly property bool stale: updatedAgo > 30 * 60
    readonly property real peak: Math.max(session.pct, weekly.pct)
    readonly property bool limited: peak >= 100
    readonly property bool warm: session.pace >= 0 && session.pct >= 25 && session.pct > session.pace + 15
    readonly property var limitWin: session.pct >= 100 ? session : weekly

    property real lastSession: -1
    property real lastWeekly: -1
    property real partyUntil: 0
    onSessionChanged: { if (lastSession >= 50 && session.pct < 5) partyUntil = now + 900; lastSession = session.pct }
    onWeeklyChanged: { if (lastWeekly >= 50 && weekly.pct < 5) partyUntil = now + 900; lastWeekly = weekly.pct }
    readonly property bool celebrate: now < partyUntil && !limited
}
