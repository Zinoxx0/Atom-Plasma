#!/bin/sh
# glimpse-kwin.sh bring <window-uuid> <output>
# Moves a window to an output, unminimizes and focuses it, through a one-shot KWin script
# (the task model can activate windows but cannot send them to another screen). The script is run and
# unloaded by Atom Plasma's kwin-run.py, the one helper for one-shot KWin scripts.
set -eu
[ "${1:-}" = bring ] || exit 2
uuid=${2:-}; output=${3:-}
case "$uuid" in "" | *[!0-9a-fA-F{}-]*) exit 2 ;; esac
case "$output" in "" | *[!A-Za-z0-9_.-]*) exit 2 ;; esac

python3 "$HOME/.config/plasma-rice/kwin-run.py" <<JS
(function () {
    const want = "$uuid".replace(/[{}]/g, "").toLowerCase();
    const w = workspace.windowList().find(x => String(x.internalId).replace(/[{}]/g, "").toLowerCase() === want);
    if (!w) return;
    const out = workspace.screens.find(o => o.name === "$output");
    if (out && w.output !== out) workspace.sendClientToScreen(w, out);
    if (w.minimized) w.minimized = false;
    workspace.activeWindow = w;
})();
JS
