#!/bin/bash
# The bar, free and docked (nested Plasma): the main screen's bar as panel.TEMPLATE lays it out (launcher, pins,
# meters, status, clock), at the main screen's size and scale (2560x1440 @1.15, UI 1.4), on its wallpaper,
# in its palette (palette-HDMI-A-1.json, copied as the virtual screen's and removed after). The islands get
# the rice's two looks (panel.bar_looks, dock_presets); then a window is maximized and restored. Colorizer
# must read the docked preset when the window touches the bar and the free one again after it lets go.
# Screenshots in $N/out: free, window (floating), dock-early/-mid/-end, undock-mid/-end. The morph runs
# slowed down (DOCK_MS_TEST, default 2400) so the shots catch it halfway. Exit 0 = all good.
#   tools/nested/test-bar.sh [OUT_DIR]      (copies the shots there too)
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
copy_to=${1:-}
state="$HOME/.local/state/rice"
pal="$state/palette-Virtual-0.json"
[ -e "$pal" ] && { echo "a palette-Virtual-0.json is already there: not touching it" >&2; exit 2; }
cp "$state/palette-HDMI-A-1.json" "$pal"
trap 'rm -f "$pal"' EXIT

wall=$(python3 -c "import json; print(json.load(open('$state/palette-HDMI-A-1.json'))['_wallpaper'])")
pins="preferred://filemanager,applications:org.kde.konsole.desktop,applications:zen.desktop,applications:discord.desktop,applications:steam.desktop,applications:com.microsoft.VSCode.desktop"
t=$(mktemp -d)
{
cat <<A
[Containments][1]
activityId=
formfactor=2
immutability=1
lastScreen=0
location=4
plugin=org.kde.panel
wallpaperplugin=org.kde.image

[Containments][1][General]
AppletOrder=2;3;4;5;6;7;8;9;10;11;12;13;14;15;16

[Containments][30]
activityId=
formfactor=0
immutability=1
lastScreen=0
location=0
plugin=org.kde.plasma.folder
wallpaperplugin=org.kde.image

[Containments][30][Wallpaper][org.kde.image][General]
Image=file://$wall

[Containments][1][Applets][4][Configuration][General]
launchers=$pins
A
n=2
for p in com.zinoxx.launcher S com.zinoxx.glimpse E com.zinoxx.shell luisbocanegra.panel.colorizer S \
         com.zinoxx.claudeusage com.zinoxx.sysstats S com.zinoxx.status com.zinoxx.tiling com.zinoxx.session S com.zinoxx.clock; do
    case $p in
        S) printf '\n[Containments][1][Applets][%s]\nimmutability=1\nplugin=org.kde.plasma.panelspacer\n\n[Containments][1][Applets][%s][Configuration][General]\nexpanding=false\nlength=4\n' $n $n ;;
        E) printf '\n[Containments][1][Applets][%s]\nimmutability=1\nplugin=org.kde.plasma.panelspacer\n\n[Containments][1][Applets][%s][Configuration][General]\nexpanding=true\n' $n $n ;;
        *) printf '\n[Containments][1][Applets][%s]\nimmutability=1\nplugin=%s\n' $n "$p" ;;
    esac
    n=$((n + 1))
done
} > "$t/appletsrc"

cat > "$t/inner.sh" <<'I'
#!/bin/bash
source "$ATOM_NESTED/env.sh"
printf '[PlasmaViews][Panel 1]\nfloating=0\n\n[PlasmaViews][Panel 1][Defaults]\nthickness=69\n' > "$N/config/plasmashellrc"
cp "$HOME/.cache/claude-usage.json" "$N/cache/" 2>/dev/null       # (the meters read it from the cache dir)
start_plasma 10
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "desktops().forEach(d => { d.currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General']; d.writeConfig('Image', 'file://$WALL') })" >/dev/null
kw() { python3 -c "import sys; sys.path.insert(0, sys.argv[2]); from atom import kwinscript; print(kwinscript.run(sys.argv[1], answer=True))" "$1" "$REPO"; }
# the rice's settings and both looks, as rice.py gives them to a bar (slowed down to be seen)
python3 - "$REPO" "${DOCK_MS_TEST:-2400}" >> "$N/out/app.log" 2>&1 <<'PY'
import hashlib, json, sys
sys.path.insert(0, sys.argv[1])
from atom import panel, util
p = json.load(open(util.STATE / "palette-HDMI-A-1.json"))
print("configured", json.dumps(panel.configure()))
for bar in panel.panels():
    looks = panel.bar_looks(p, bar)
    key = hashlib.sha1(json.dumps(looks, sort_keys=True).encode()).hexdigest()
    cfg = {"presetAutoloading": panel.dock_presets(bar, looks, key), "animatePropertyChanges": True,
           "animationDuration": int(sys.argv[2])}
    print("islands", [[w.split(".")[-1] for _, w in g] for g in panel.islands(bar)])
    print("applied", panel.colorizer_apply(bar, looks[0], cfg))
PY
sleep 4
mark "free"; shot free
qml6 "$REPO/tools/nested/app.qml" >> "$N/out/app.log" 2>&1 & app=$!
sleep 2
mark "window"; shot window
mark "maximize"
kw 'workspace.windowList().filter(w => w.caption === "user app").forEach(w => w.setMaximize(true, true)); answer("ok")' >> "$N/out/app.log"
shot dock-early; sleep 0.5; shot dock-mid; sleep 3; mark "docked"; shot dock-end
mark "restore"
kw 'workspace.windowList().filter(w => w.caption === "user app").forEach(w => w.setMaximize(false, false)); answer("ok")' >> "$N/out/app.log"
sleep 0.4; shot undock-mid; sleep 3; mark "freed"; shot undock-end
kill $app; stop_plasma
I
chmod +x "$t/inner.sh"
N=$(WALL="$wall" ATOM_NESTED_W=2560 ATOM_NESTED_H=1440 ATOM_NESTED_SCALE=1.15 "$here/run.sh" --plasma "$t/appletsrc" "$t/inner.sh" 150 | tail -1)
L="$N/out/plasmashell.log"
fail=0
check() { if grep -q -- "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
check "the rice's looks applied" 'applied True' "$N/out/app.log"
check "meters share one island" "'claudeusage', 'sysstats'" "$N/out/app.log"
check "status, tiling and power share one" "'status', 'tiling', 'session'" "$N/out/app.log"
# (Colorizer logs each preset it reads, in order)
seq=$(grep -o 'Reading preset: [^ ]*' "$L" | sed 's/.*-//' | tr '\n' ' ')
echo "     presets read: $seq"
case "$seq" in *"docked free"*) echo "ok   docked while maximized, free after";; *) echo "FAIL docked while maximized, free after"; fail=1;; esac
[ -n "$copy_to" ] && mkdir -p "$copy_to" && cp "$N"/out/*.png "$L" "$copy_to"/ 2>/dev/null
echo "shots: $N/out"
exit $fail
