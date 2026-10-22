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
here=$(dirname "$(readlink -f "$0")")
kwin() { qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "$1"; }
note() { notify-send -a "Tiling" -i "$1" -h string:x-canonical-private-synchronous:tiling "$2" "$3"; }
entries() { kreadconfig6 --file kwinrc --group Script-krohnkite --key screenDefaultLayout | tr ',' '\n' | grep -v '^$'; }

# FloatingLayout's index in Krohnkite's layout list: the enabled layouts (order > 0) sorted by their order
# setting, as Krohnkite builds it. The layouts and their default orders come from Krohnkite's own config
# file, so an update that adds or reorders layouts is followed; kwinrc holds the user's changes.
float_index() {
    python3 - <<'PY' 2>/dev/null
import subprocess, xml.etree.ElementTree as ET
from pathlib import Path
xml = Path.home() / ".local/share/kwin/scripts/krohnkite/contents/config/main.xml"
ns = "{http://www.kde.org/standards/kcfg/1.0}"
layouts = []
for e in ET.parse(xml).getroot().iter(ns + "entry"):
    name = e.get("name", "")
    if name.endswith("LayoutOrder"):
        default = e.findtext(ns + "default", "0").strip()
        order = subprocess.run(["kreadconfig6", "--file", "kwinrc", "--group", "Script-krohnkite", "--key", name,
                                "--default", default], capture_output=True, text=True).stdout.strip()
        if int(order or 0) > 0:
            layouts.append((int(order), name))
names = [n for _, n in sorted(layouts, key=lambda t: t[0])]       # stable, like Krohnkite's sort
print(names.index("floatingLayoutOrder"))
PY
}

# the screen Krohnkite acts on: the focused window's (KWin's activeOutputName follows the mouse instead),
# asked of KWin with a one-shot script that answers over D-Bus (kwin-run.py)
focused_output() {
    o=$(printf 'answer(workspace.activeWindow ? workspace.activeWindow.output.name : workspace.activeScreen.name);\n' \
        | python3 "$here/kwin-run.py" --answer 2>/dev/null)
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
