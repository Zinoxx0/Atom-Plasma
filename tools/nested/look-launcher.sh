#!/bin/bash
# Look at the launcher as it is on the main screen: a nested Plasma (run.sh) the main screen's size and scale
# (2560x1440 @1.15 by default: ATOM_NESTED_W/H/SCALE), its real palette and wallpaper, the launcher's jewel
# on a bar, Shell.debug on (nothing on the Theme page is applied: dry runs). Then a list of steps:
#
#   tools/nested/look-launcher.sh OUTDIR step...   (env: ATOM_STYLE=atom a launcher style; ATOM_MYAPPS=1 your apps; ATOM_WALL=FILE its palette)
#     open | meta            open it (the jewel; meta = the launcher shortcut)
#     key:CODE               a key (evdev codes: 108 down, 103 up, 105 left, 106 right, 28 enter, 1 esc, 15 tab)
#     type:TEXT  wait:MS  move:X,Y  click  clickat:X,Y (a move, then the click: fresh surface)  rclick  wheel:N  drag:X1,Y1,X2,Y2  glide:X1,Y1,X2,Y2,MS (no button)
#     theme                  click the palette (Theme page);  shot:NAME   a screenshot (OUTDIR/NAME.png)
#     pad:BUTTONS            a pretend gamepad (tools/nested/pad.py: south east dpad-down ...), if built
#     log:WORDS              a mark in the log
# Coordinates are logical, on the nested screen. OUTDIR also gets plasmashell.log.
set -u
here=$(cd "$(dirname "$0")" && pwd)
out=$(realpath -m "$1"); shift
mkdir -p "$out"
state="$HOME/.local/state/rice"
pal="$state/palette-Virtual-0.json"
[ -e "$pal" ] && { echo "a palette-Virtual-0.json is already there: not touching it" >&2; exit 2; }
trap 'rm -f "$pal" "$HOME"/.cache/rice/glass/Virtual-0-* "$HOME"/.cache/rice/glass-full/Virtual-0-*; rm -rf "$t"' EXIT
if [ -n "${ATOM_WALL:-}" ]; then   # another wallpaper: the palette the theme engine makes for it (as the virtual screen)
    python3 -c '
import json, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from atom import screens, util
ss = screens.screens()
s = next((x for x in ss if x["main"]), ss[0])
p = screens.screen_palette(dict(s, name="Virtual-0"), Path(sys.argv[2]), util.settings(), desk={"media": True, "clawd": True, "theme": ""})
Path(sys.argv[3]).write_text(json.dumps(p, indent=2) + "\n")
' "$(cd "$(dirname "$0")/../.." && pwd)" "$(realpath "$ATOM_WALL")" "$pal" || exit 1
else
    cp "$state/palette-HDMI-A-1.json" "$pal"
fi
wall=$(python3 -c "import json; print(json.load(open('$pal'))['_wallpaper'])")
t=$(mktemp -d)
cat > "$t/appletsrc" <<A
[Containments][1]
activityId=
formfactor=2
immutability=1
lastScreen=0
location=4
plugin=org.kde.panel
wallpaperplugin=org.kde.image

[Containments][1][Applets][2]
immutability=1
plugin=com.zinoxx.launcher

[Containments][1][Applets][3]
immutability=1
plugin=org.kde.plasma.panelspacer

[Containments][1][Applets][4]
immutability=1
plugin=com.atom.test.islanda

[Containments][1][Applets][5]
immutability=1
plugin=com.zinoxx.shell

[Containments][1][General]
AppletOrder=2;3;4;5

[Containments][8]
activityId=
formfactor=0
immutability=1
lastScreen=0
location=0
plugin=org.kde.plasma.folder
wallpaperplugin=org.kde.image

[Containments][8][Wallpaper][org.kde.image][General]
Image=file://$wall
A
printf '%s\n' "$@" > "$t/steps"
cat > "$t/inner.sh" <<'I'
#!/bin/bash
source "$ATOM_NESTED/env.sh"
[ -n "$ATOM_STYLE" ] && printf '%s\n' "$ATOM_STYLE" > "$N/config/atom-test-style"     # the launcher style to look at (tests only)
if [ -n "$ATOM_MYAPPS" ]; then   # the user's own apps, icons and usage (Steam's games, pins, recents), as showcase.sh does
    mkdir -p "$N/data" "$N/config"
    ln -sfn "$HOME/.local/share/applications" "$N/data/applications"
    ln -sfn "$HOME/.local/share/icons" "$N/data/icons"
    cp -r "$HOME/.local/share/kactivitymanagerd" "$N/data/" 2>/dev/null
    cp "$HOME/.config/kactivitymanagerdrc" "$N/config/" 2>/dev/null
fi
start_plasma 8
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "desktops().forEach(d => { d.wallpaperPlugin = 'org.kde.image'; d.currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General']; d.writeConfig('Image', 'file://$WALL') })" >/dev/null
sleep 1
J=$(grep -o 'ATOM island launcher at [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $5, $6}')
while read -r s; do
    [ -z "$s" ] && continue
    mark "$s"
    case "$s" in
        open)    $F move ${J:-30 1230} click wait 1600 ;;
        meta)    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu; $F wait 1800 ;;
        theme)   T=$(grep -o 'ATOM home tabs at .* theme at [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $(NF-1), $NF}'); $F move ${T:-2000 50} click wait 1400 ;;
        key:*)   $F key "${s#key:}" wait 120 ;;
        type:*)  $F type "${s#type:}" wait 200 ;;
        wait:*)  $F wait "${s#wait:}" ;;
        move:*)  $F move $(echo "${s#move:}" | tr ',' ' ') ;;
        clickat:*) $F move $(echo "${s#clickat:}" | tr ',' ' ') click wait 120 ;;
        click)   $F click wait 120 ;;
        rclick)  $F click right wait 300 ;;
        wheel:*) $F wheel "${s#wheel:}" wait 100 ;;
        drag:*)  $F drag $(echo "${s#drag:}" | tr ',' ' ') ;;
        glide:*) $F glide $(echo "${s#glide:}" | tr ',' ' ') ;;
        pad:*)   python3 "$REPO/tools/nested/pad.py" ${s#pad:} ;;
        shot:*)  shot "${s#shot:}" ;;
        log:*)   ;;
    esac
    case "$s" in move:*) ;; *) $F wait 60 ;; esac
done < "$STEPS"
stop_plasma
I
chmod +x "$t/inner.sh"
N=$(STEPS="$t/steps" WALL="$wall" ATOM_NESTED_DIR="${XDG_RUNTIME_DIR:-/tmp}/atom-look" ATOM_NESTED_W=${ATOM_NESTED_W:-2560} ATOM_NESTED_H=${ATOM_NESTED_H:-1440} \
    ATOM_NESTED_SCALE=${ATOM_NESTED_SCALE:-1.15} "$here/run.sh" --plasma "$t/appletsrc" "$t/inner.sh" ${LOOK_SECS:-150} | tail -1)
cp "$N"/out/*.png "$N/out/plasmashell.log" "$out"/ 2>/dev/null
grep -E "launcher|Stage|Home|Theme|Atom|Jewel|TopButton|DeskMap|Pad" "$N/out/plasmashell.log" | grep -E "Error|error:|TypeError|ReferenceError|Cannot|Unable|not a type|is not defined|Invalid property" | sort -u | head -20
echo "out: $out"
