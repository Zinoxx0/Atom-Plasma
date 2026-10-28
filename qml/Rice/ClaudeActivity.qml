import QtQuick
import QtCore

// What Claude Code is doing right now, for Clawd: ~/.cache/clawd/activity.json, written by Claude
// Code's hooks (~/.config/plasma-rice/clawd-hook.sh), watched and re-read on every write (WatchedJson).
//
//   ClaudeActivity { id: claude }      Clawd { activity: claude.activity }
//
// activity, while Claude works: thinking | typing | building | reading | web | juggling | sweeping;
// when it needs you: attention (a permission prompt, a question form, a plan to approve; until it goes
// on) | waiting (its answer asked you something; up to 3 h); after an answer (what it was about, from
// clawd-intent.py): running (background work going; up to 45 min) | fixed | done | found | stuck (for
// 10 min) | chat (20 s); "idle" once the hooks have reported and nothing is going on (Clawd then
// ignores the status line's `working`), "" with no hook data at all.
Item {
    id: ca
    visible: false

    property bool active: true
    property var last: null                     // {event, tool, ts}
    property real now: Date.now() / 1000
    readonly property real age: last ? now - Number(last.ts || 0) : 1e9

    readonly property string activity: {
        if (!last || age > 6 * 3600) return ""
        const e = last.event, t = String(last.tool || ""), k = String(last.kind || "")
        if (e === "stop") {
            if (k === "running") return age < 45 * 60 ? "running" : "idle"
            if (k === "question") return age < 3 * 3600 ? "waiting" : "idle"
            if (k === "chat") return age < 20 ? "chat" : "idle"
            if (k === "fixed" || k === "done" || k === "found" || k === "stuck") return age < 600 ? k : "idle"
            return age < 8 ? "done" : "idle"                // an older hook, with no kind
        }
        // Claude Code waits on the user: a permission prompt, a question form (AskUserQuestion), a plan
        if (e === "notify" || (e === "pre" && (t === "AskUserQuestion" || t === "ExitPlanMode")))
            return age < 3 * 3600 ? "attention" : "idle"
        if (e === "end" || age > 180) return "idle"         // ended, or a session that died mid-way
        if (e === "compact") return "sweeping"
        if (e === "prompt" || e === "post") return "thinking"
        if (e !== "pre") return "idle"
        if (/^(Edit|Write|MultiEdit|NotebookEdit)$/.test(t)) return "typing"
        if (/^(Bash|BashOutput|KillShell|KillBash)$/.test(t)) return "building"
        if (/^(Read|Grep|Glob|LS|NotebookRead)$/.test(t)) return "reading"
        if (/^(WebSearch|WebFetch)$/.test(t) || t.startsWith("mcp__")) return "web"
        if (/^(Task|Agent)$/.test(t)) return "juggling"
        if (t === "TodoWrite" || t === "ExitPlanMode") return "thinking"
        return "typing"
    }

    WatchedJson {
        id: file
        path: String(StandardPaths.writableLocation(StandardPaths.GenericCacheLocation)).replace(/^file:\/\//, "") + "/clawd/activity.json"
        active: ca.active
        onChanged: if (file.value && file.value.ts) { ca.now = Date.now() / 1000; ca.last = file.value }
    }
    // the clock only ticks while something is going on (to let the after-answer states expire)
    Timer {
        interval: ca.age < 30 ? 2000 : 20000
        running: ca.active && ca.activity !== "" && ca.activity !== "idle"
        repeat: true
        onTriggered: ca.now = Date.now() / 1000
    }
}
