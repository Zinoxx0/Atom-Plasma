#!/usr/bin/env bash
# Claude Code's status line for Atom Plasma: shows the model and the usage limits, and keeps the limits in
# ~/.cache/claude-usage.json for the bar's Claude island (its rings and Clawd's tiredness watch that file).
# When the numbers move, the island's alerts.py sends the 80% / 95% notifications, in the background.
#
# `rice.py install` sets it as Claude Code's statusLine when you have none. With your own status line, have
# it write the same file: {"updated": <epoch seconds>, <Claude Code's rate_limits object, unwrapped>}.
#
# It runs on every status update (several a second while Claude answers), so it is one jq and nothing else:
# the cache is only rewritten when the numbers change, or every 20 s to say the session is alive (the island
# calls a session live for 3 minutes after the last write).
cache="$HOME/.cache/claude-usage.json"
alerts="${BASH_SOURCE[0]%/*}/../plasmoids/com.zinoxx.claudeusage/contents/code/alerts.py"

# line 1: the status text; line 2: the limits, compact ("" when there are none)
{ IFS= read -r text; IFS= read -r limits; } < <(jq -r '
  def pct(x): if x == null then "–" else "\(x | floor)%" end;
  ([ .model.display_name // "Claude",
     "5h " + pct(.rate_limits.five_hour.used_percentage),
     "7d " + pct(.rate_limits.seven_day.used_percentage) ] | join(" · ")),
  (.rate_limits // {} | if type != "object" or . == {} then "" else tojson end)' 2>/dev/null)

if [ -n "$limits" ]; then
  # the cache is {"updated":<when>,<the limits>}: what it holds now, read without a process
  old=""; [ -r "$cache" ] && IFS= read -r old < "$cache"
  was="{${old#*,}"; when=${old#\{\"updated\":}; when=${when%%,*}
  case $when in ''|*[!0-9]*) when=0 ;; esac
  if [ "$was" != "$limits" ] || [ $((EPOCHSECONDS - when)) -ge 20 ]; then
    mkdir -p "${cache%/*}"
    printf '{"updated":%s,%s\n' "$EPOCHSECONDS" "${limits#\{}" > "$cache.tmp" && mv "$cache.tmp" "$cache"
    if [ "$was" != "$limits" ] && [ -f "$alerts" ]; then
      ( python3 "$alerts" >/dev/null 2>&1 & )
    fi
  fi
fi

printf '%s\n' "${text:-Claude}"
