#!/bin/sh
# glimpse-kwin.sh bring <window-uuid> <output>
# Moves a window to an output, unminimizes and focuses it, through a one-shot KWin script
# (the task model can activate windows but cannot send them to another screen).
set -eu
[ "${1:-}" = bring ] || exit 2
uuid=${2:-}; output=${3:-}
case "$uuid" in "" | *[!0-9a-fA-F{}-]*) exit 2 ;; esac
case "$output" in "" | *[!A-Za-z0-9_.-]*) exit 2 ;; esac

dir="${XDG_RUNTIME_DIR:-/tmp}/glimpse"
mkdir -p "$dir"
name="glimpse-$$"
file="$dir/$name.js"
# unload even if a step fails, so no one-shot script stays loaded in KWin
trap 'busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting unloadScript s "$name" >/dev/null 2>&1; rm -f "$file"' EXIT
cat > "$file" <<JS
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
id=$(busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting loadScript ss "$file" "$name" | awk '{print $2}')
busctl --user call org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script run >/dev/null
