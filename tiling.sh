#!/bin/sh
# Meta+Alt+T: toggle auto-tiling on the focused screen.
#
# Krohnkite must never be unloaded/reloaded inside a running session: a second
# load comes up broken ("Qt.createQmlObject(): Missing parent object") until
# KWin restarts. So it stays loaded and this flips the screen between
# Krohnkite's Tile and Floating layouts instead. Which screens float is kept in
# Krohnkite's own screenDefaultLayout setting ("DP-3:floating,eDP-1:floating"),
# which it reads when it loads at login, so the choice survives a reboot.
kwin() { qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "$1"; }
note() { notify-send -a "Tiling" -i "$1" -h string:x-canonical-private-synchronous:tiling "$2" "$3"; }
entries() { kreadconfig6 --file kwinrc --group Script-krohnkite --key screenDefaultLayout | tr ',' '\n'; }
save() {  # one entry per line
    v="$(printf '%s\n' "$1" | grep -v '^$' | paste -sd, -)"
    if [ -n "$v" ]; then kwriteconfig6 --file kwinrc --group Script-krohnkite --key screenDefaultLayout "$v"
    else kwriteconfig6 --file kwinrc --group Script-krohnkite --key screenDefaultLayout --delete; fi
}

if [ "$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded krohnkite)" != "true" ]; then
    # first load of the session works fine; every screen starts tiled
    save ""
    kwriteconfig6 --file kwinrc --group Plugins --key krohnkiteEnabled true
    qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null
    note view-grid "Auto-tiling on" "Meta+Alt+T toggles it per screen"
    exit 0
fi

out="$(qdbus6 org.kde.KWin /KWin org.kde.KWin.activeOutputName)"
others="$(entries | awk -F: -v o="$out" 'NF && $1 != o')"
if entries | grep -qxF "$out:floating"; then
    kwin KrohnkiteTileLayout
    save "$others"
    note view-grid "Auto-tiling on" "$out"
else
    kwin KrohnkiteFloatingLayout
    save "$others
$out:floating"
    note window "Auto-tiling off" "$out · windows float freely"
fi
