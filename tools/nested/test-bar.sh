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
source "$here/bar-applets.sh"
bar_applets 0 1 30 "$wall" "$pins" > "$t/appletsrc"

cat > "$t/inner.sh" <<'I'
#!/bin/bash
source "$ATOM_NESTED/env.sh"
printf '[PlasmaViews][Panel 1]\nfloating=0\n\n[PlasmaViews][Panel 1][Defaults]\nthickness=%s\n' "${BAR_THICK:-69}" > "$N/config/plasmashellrc"
cp "$HOME/.cache/claude-usage.json" "$N/cache/" 2>/dev/null       # (the meters read it from the cache dir)
start_plasma 10
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "desktops().forEach(d => { d.currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General']; d.writeConfig('Image', 'file://$WALL') })" >/dev/null
kw() { python3 -c "import sys; sys.path.insert(0, sys.argv[2]); from atom import kwinscript; print(kwinscript.run(sys.argv[1], answer=True))" "$1" "$REPO"; }
# the rice's settings and both looks, as rice.py gives them to a bar (slowed down to be seen)
python3 "$REPO/tools/nested/bar_looks.py" "$REPO" "${DOCK_MS_TEST:-2400}" >> "$N/out/app.log" 2>&1
sleep 4
mark "free"; shot free; spectacle -b -n -m -o "$N/out/free-native.png" >/dev/null 2>&1
qml6 "$REPO/tools/nested/app.qml" >> "$N/out/app.log" 2>&1 & app=$!
sleep 2
mark "window"; shot window
mark "maximize"
kw 'workspace.windowList().filter(w => w.caption === "user app").forEach(w => w.setMaximize(true, true)); answer("ok")' >> "$N/out/app.log"
shot dock-early; sleep 0.5; shot dock-mid; sleep 3; mark "docked"; shot dock-end; spectacle -b -n -m -o "$N/out/docked-native.png" >/dev/null 2>&1
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
