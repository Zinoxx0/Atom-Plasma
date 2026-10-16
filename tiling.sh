#!/bin/sh
# Meta+Alt+T: toggle auto-tiling on the focused screen.
#
# Krohnkite must never be unloaded/reloaded inside a running session: a second
# load comes up broken ("Qt.createQmlObject(): Missing parent object") until
# KWin restarts. So it stays loaded and this flips the screen between
# Krohnkite's Tile and Floating layouts instead. Which screens float is kept in
# Krohnkite's own screenDefaultLayout setting, which it reads when it loads at
# login, so the choice survives a reboot. Entries name the layout by its index
# ("DP-3:8"): Krohnkite 0.9.9.2's FloatingLayout id has a trailing space
# ("FloatingLayout "), so "DP-3:floating" never matches and the screen comes
# up tiled.
kwin() { qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "$1"; }
note() { notify-send -a "Tiling" -i "$1" -h string:x-canonical-private-synchronous:tiling "$2" "$3"; }
entries() { kreadconfig6 --file kwinrc --group Script-krohnkite --key screenDefaultLayout | tr ',' '\n' | grep -v '^$'; }

# FloatingLayout's index in Krohnkite's layout list: the enabled layouts (order > 0) sorted by their
# order setting, as Krohnkite builds it
float_index() {
    for kd in tile:1 monocle:2 threeColumn:3 spiral:4 quarter:5 stacked:6 columns:7 spread:8 \
              floating:9 stair:10 binaryTree:11 cascade:12; do
        k=${kd%%:*}; d=${kd#*:}
        echo "$(kreadconfig6 --file kwinrc --group Script-krohnkite --key "${k}LayoutOrder" --default "$d") $k"
    done | awk '$1 > 0' | sort -s -n -k1,1 | awk '$2 == "floating" { print NR - 1; exit }'
}

# the screen Krohnkite acts on: the focused window's (KWin's activeOutputName follows the mouse instead)
focused_output() {
    tag="tiling-$$-$(date +%s%N)"; js="${XDG_RUNTIME_DIR:-/tmp}/$tag.js"; since="$(date +%s.%N)"
    printf 'print("%s " + (workspace.activeWindow ? workspace.activeWindow.output.name : workspace.activeScreen.name));\n' "$tag" > "$js"
    qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$js" "$tag" >/dev/null
    qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null
    o=""
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        o="$(journalctl --user --since "@$since" -o cat 2>/dev/null | grep -m1 "$tag " | awk '{ print $NF }')"
        [ -n "$o" ] && break
        sleep 0.05
    done
    qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$tag" >/dev/null
    rm -f "$js"
    [ -n "$o" ] || o="$(qdbus6 org.kde.KWin /KWin org.kde.KWin.activeOutputName)"
    echo "$o"
}

save() {  # floating outputs, one per line
    idx="$(float_index)"
    v="$(printf '%s\n' "$1" | grep -v '^$' | sed "s/\$/:${idx:-8}/" | paste -sd, -)"
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

out="$(focused_output)"
floating="$(entries | cut -d: -f1)"
others="$(printf '%s\n' "$floating" | grep -vxF "$out")"
if printf '%s\n' "$floating" | grep -qxF "$out"; then
    kwin KrohnkiteTileLayout
    save "$others"
    note view-grid "Auto-tiling on" "$out"
else
    kwin KrohnkiteFloatingLayout
    save "$others
$out"
    note window "Auto-tiling off" "$out · windows float freely"
fi
