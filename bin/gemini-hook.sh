#!/usr/bin/env bash
# Antigravity lifecycle hook for Atom Plasma's Gemini module: writes ~/.cache/gemini/activity.json
# ({"event", "tool", "model", "ts"}), which qml/Rice/GeminiActivity.qml watches to trigger the
# soft gravity waves around the Gemini star.
#
# Registered in ~/.gemini/config/hooks.json under "atom-plasma-gemini" for:
#   SessionStart (start), PreInvocation (pre), PostToolUse (post), PostInvocation (post), Stop (stop).
# Deliberately skips PreToolUse so it can never alter Antigravity's tool permission decisions.
#
# Antigravity hooks expect valid JSON on stdout and exit 0; always fast, silent on stderr.
ev=${1:-}
payload=$(cat 2>/dev/null || true)
tool=""
model=""
if [ -n "$payload" ]; then
  if command -v jq >/dev/null 2>&1; then
    { IFS= read -r tool; IFS= read -r model; } < <(
      printf '%s' "$payload" | jq -r '
        (.toolCall.name // .tool_name // "" | gsub("[^A-Za-z0-9_.-]"; "")),
        (.modelName // .model // "" | gsub("[^A-Za-z0-9_.: -]"; ""))
      ' 2>/dev/null
    )
  elif command -v python3 >/dev/null 2>&1; then
    { IFS= read -r tool; IFS= read -r model; } < <(
      printf '%s' "$payload" | python3 -c '
import json, re, sys
try:
    d = json.load(sys.stdin)
    if not isinstance(d, dict):
        d = {}
except Exception:
    d = {}
tc = d.get("toolCall") if isinstance(d.get("toolCall"), dict) else {}
tool = re.sub(r"[^A-Za-z0-9_.-]", "", str(tc.get("name") or d.get("tool_name") or ""))
model = re.sub(r"[^A-Za-z0-9_.: -]", "", str(d.get("modelName") or d.get("model") or ""))
print(tool)
print(model)
' 2>/dev/null
    )
  fi
fi
d="$HOME/.cache/gemini"
mkdir -p "$d" 2>/dev/null
now=$(date +%s 2>/dev/null || printf '0')
printf '{"event":"%s","tool":"%s","model":"%s","ts":%s}\n' "$ev" "$tool" "$model" "$now" > "$d/activity.json.$$" 2>/dev/null \
  && mv -f "$d/activity.json.$$" "$d/activity.json" 2>/dev/null
printf '{}\n'
exit 0
