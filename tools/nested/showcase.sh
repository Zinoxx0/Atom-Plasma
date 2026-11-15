#!/bin/bash
# The rice as it looks on a wallpaper, for showing it (the GitHub profile's Atom panel): the main screen at its
# size and scale (2560x1440 @1.15), its bar as the rice lays it out (the islands, Clawd, the meters) at its real
# thickness, the desk (clock, date, weather, Clawd), the launcher's Home and its Theme page, all in the palette
# the theme engine computes for WALLPAPER (atom.screens.screen_palette, as a re-theme would). Nothing of the real
# desktop changes: the palette is the virtual screen's, removed after. Nothing that acts is clicked (the bar's
# islands drive the real machine): the launcher opens by its D-Bus call, the Theme page with a pretend pad's Y.
#   tools/nested/showcase.sh WALLPAPER OUTDIR       -> OUTDIR/desk.png home.png game.png look.png (2560x1440; game = Home
#                                                      with the first game focused, look = the Theme
#                                                      page with its Look group open)
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
wall=$(realpath "$1")
out=$(realpath -m "$2")
mkdir -p "$out"
state="$HOME/.local/state/rice"
pal="$state/palette-Virtual-0.json"
[ -e "$pal" ] && { echo "a palette-Virtual-0.json is already there: not touching it" >&2; exit 2; }
t=$(mktemp -d)
trap 'rm -f "$pal"; rm -rf "$t"' EXIT
python3 - "$repo" "$wall" "$pal" <<'P' || exit 1
import json, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from atom import screens, util
ss = screens.screens()
s = next((x for x in ss if x["main"]), ss[0])
p = screens.screen_palette(s, Path(sys.argv[2]), util.settings(), desk={"media": True, "clawd": True, "theme": ""})
Path(sys.argv[3]).write_text(json.dumps(p, indent=2) + "\n")
print("palette", p.get("_mood"), p["primary"], p["secondary"], p["tertiary"])
P
pins="preferred://filemanager,applications:org.kde.konsole.desktop,applications:zen.desktop,applications:discord.desktop,applications:steam.desktop,applications:com.microsoft.VSCode.desktop"
source "$here/bar-applets.sh"
bar_applets 0 1 30 "$wall" "$pins" > "$t/appletsrc"
thick=$(kreadconfig6 --file plasmashellrc --group PlasmaViews --group "Panel 23" --group Defaults --key thickness)
cat > "$t/inner.sh" <<'I'
#!/bin/bash
source "$ATOM_NESTED/env.sh"
printf '[PlasmaViews][Panel 1]\nfloating=0\n\n[PlasmaViews][Panel 1][Defaults]\nthickness=%s\n' "${THICK:-64}" > "$N/config/plasmashellrc"
cp "$HOME/.cache/claude-usage.json" "$N/cache/" 2>/dev/null       # (the meters read it from the cache dir)
# the launcher as it is: the apps (the games' .desktop files and icons are the user's own), the pins and
# recents (the activity manager's database: a copy, the nested one writes to it)
mkdir -p "$N/data" "$N/config"
ln -sfn "$HOME/.local/share/applications" "$N/data/applications"
ln -sfn "$HOME/.local/share/icons" "$N/data/icons"
cp -r "$HOME/.local/share/kactivitymanagerd" "$N/data/" 2>/dev/null
cp "$HOME/.config/kactivitymanagerdrc" "$N/config/" 2>/dev/null
start_plasma 10
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "desktops().forEach(d => { d.wallpaperPlugin = 'org.kde.image'; d.currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General']; d.writeConfig('Image', 'file://$WALL') })" >/dev/null
# the desk, as the rice adds it (atom/js/desks.js: a 1 px applet; its windows are layer-shell)
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "desktops().forEach(d => { const g = screenGeometry(d.screen); if (!d.widgets('com.zinoxx.desk').length) d.addWidget('com.zinoxx.desk', g.width - 31, g.height - 31, 1, 1) })" >/dev/null
python3 "$REPO/tools/nested/bar_looks.py" "$REPO" 260 "$PAL" >> "$N/out/app.log" 2>&1
$F move 2200 700 wait 6000
shot desk
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu
$F wait 2600 move 2210 640 wait 1200
shot home
python3 "$REPO/tools/nested/pad.py" down; $F wait 2400            # (the Games row: a game's art fills the room)
shot game
python3 "$REPO/tools/nested/pad.py" north; $F wait 2200
python3 "$REPO/tools/nested/pad.py" down south; $F wait 2400
shot look
stop_plasma
I
chmod +x "$t/inner.sh"
N=$(WALL="$wall" PAL="$pal" THICK="${thick:-64}" ATOM_NESTED_DIR="${XDG_RUNTIME_DIR:-/tmp}/atom-show" ATOM_NESTED_W=2560 ATOM_NESTED_H=1440 \
    ATOM_NESTED_SCALE=1.15 "$here/run.sh" --plasma "$t/appletsrc" "$t/inner.sh" 120 | tail -1)
cp "$N"/out/*.png "$N/out/plasmashell.log" "$out"/ 2>/dev/null
grep -E "Error|TypeError|ReferenceError|Cannot|Unable|not a type|is not defined" "$N/out/plasmashell.log" | grep -iE "zinoxx|Atom|Rice" | sort -u | head -10
echo "out: $out"
