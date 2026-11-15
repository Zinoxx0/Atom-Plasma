#!/bin/sh
# Claude Code hook: tells Clawd what Claude Code is doing. Writes ~/.cache/clawd/activity.json
# ({"event", "tool", "kind", "ts"}), which qml/Rice/ClaudeActivity.qml watches. Registered in
# ~/.claude/settings.json for UserPromptSubmit (prompt), PreToolUse (pre), PostToolUse (post),
# Notification (notify), PreCompact (compact), Stop (stop) and SessionEnd (end).
#   pre     tool = the tool about to run
#   notify  kind = permission, only when Claude Code asks for a permission or a form answer; the
#           "waiting for your input" reminder (idle_prompt) leaves Clawd as it is
#   stop    kind = what the answer was about (clawd-intent.py): running | question | stuck | fixed |
#           done | found | chat
# It must never slow Claude Code down or fail it: no output, always exit 0.
ev=${1:-}
tool=
kind=
case $ev in
    pre)
        tool=$(jq -r '.tool_name // ""' 2>/dev/null | tr -cd 'A-Za-z0-9_-') ;;
    notify)
        case $(jq -r '.notification_type // ""' 2>/dev/null) in
            permission_prompt|elicitation_dialog) kind=permission ;;
            *) exit 0 ;;
        esac ;;
    stop)
        kind=$(python3 -I "$(dirname "$0")/clawd-intent.py" 2>/dev/null | tr -cd 'a-z') ;;
    *)
        cat >/dev/null 2>&1 ;;
esac
d="$HOME/.cache/clawd"
mkdir -p "$d" 2>/dev/null
printf '{"event":"%s","tool":"%s","kind":"%s","ts":%s}\n' "$ev" "$tool" "$kind" "$(date +%s)" > "$d/activity.json.$$" 2>/dev/null \
    && mv -f "$d/activity.json.$$" "$d/activity.json" 2>/dev/null
exit 0
