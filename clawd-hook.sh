#!/bin/sh
# Claude Code hook: tells Clawd what Claude Code is doing. Writes ~/.cache/clawd/activity.json
# ({"event", "tool", "ts"}), which qml/Rice/ClaudeActivity.qml watches. Registered in
# ~/.claude/settings.json for UserPromptSubmit (prompt), PreToolUse (pre), PostToolUse (post),
# Notification (notify), PreCompact (compact), Stop (stop) and SessionEnd (end).
# It must never slow Claude Code down or fail it: no output, always exit 0.
ev=${1:-}
tool=
if [ "$ev" = pre ]; then
    tool=$(jq -r '.tool_name // ""' 2>/dev/null | tr -cd 'A-Za-z0-9_-')
else
    cat >/dev/null 2>&1
fi
d="$HOME/.cache/clawd"
mkdir -p "$d" 2>/dev/null
printf '{"event":"%s","tool":"%s","ts":%s}\n' "$ev" "$tool" "$(date +%s)" > "$d/activity.json.$$" 2>/dev/null \
    && mv -f "$d/activity.json.$$" "$d/activity.json" 2>/dev/null
exit 0
