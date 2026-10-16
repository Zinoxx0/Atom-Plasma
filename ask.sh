#!/bin/sh
# Ask the user to check something: raises a big "!" over Clawd (the Claude usage widget on the bars),
# lights its island red and sends one notification. The user clicks "Done" in the widget's popup.
#
#   ask.sh "message"   raise a check-in (replaces any open one)
#   ask.sh --status    print the current request as JSON ("none" if there is none); ack > 0 = seen
#   ask.sh --wait      block until the user clicks Done
#   ask.sh --ack       mark it done (what the Done button runs)
#   ask.sh --clear     drop it
#   ask.sh --remind    for Claude Code's UserPromptSubmit hook: while one is open, remind Claude about it
#                      (so it clears it once the user has answered in chat instead of clicking Done)
#
# A check-in stays up until Done or --clear: no timeout, and it survives restarts (the file is in
# ~/.local/state). The bars and the desktop Clawd watch it (qml/Rice/ClaudeAsk.qml).
STATE="$HOME/.local/state/rice"
F="$STATE/ask.json"

case "$1" in
    --clear) rm -f "$F" ;;
    --remind)
        cat >/dev/null 2>&1
        [ -f "$F" ] || exit 0
        jq -c 'select((.ack // 0) == 0) | {hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext:
            ("An Atom Plasma check-in is still open (Clawd shows a \"!\" on the bars and the desktop; raised with ask.sh): \""
             + .msg + "\". If the user has answered or settled it, in chat or otherwise, clear it with ~/.config/plasma-rice/ask.sh --clear.")}}' \
            "$F" 2>/dev/null
        exit 0 ;;
    --status) if [ -f "$F" ]; then cat "$F"; else echo none; fi ;;
    --wait) while [ -f "$F" ] && [ "$(jq -r '.ack // 0' "$F")" = 0 ]; do sleep 3; done ;;
    --ack)
        [ -f "$F" ] || exit 0
        jq -c --argjson t "$(date +%s)" '.ack = $t' "$F" > "$F.tmp" && mv "$F.tmp" "$F" ;;
    "" | -h | --help) sed -n '2,14p' "$0" ;;
    *)
        mkdir -p "$STATE"
        now=$(date +%s)
        jq -nc --arg msg "$*" --argjson now "$now" '{id: $now, msg: $msg, since: $now, ack: 0}' > "$F.tmp" \
            && mv "$F.tmp" "$F"
        notify-send -a "Claude" -i dialog-information -h string:x-canonical-private-synchronous:claude-ask \
            "Claude needs you" "$*" ;;
esac
