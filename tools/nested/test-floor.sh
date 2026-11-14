#!/bin/bash
# The docked bar's floor (Atom FloorWindow), nested on two screens with the real islands script
# (kwin/rice_islands): a window maximized on screen 1 docks its bar; the pointer takes the islands to screen 2,
# and screen 1 must keep the floor under the window instead of a strip of bare wallpaper; the islands come back
# over it; with the islands away again the window is restored and the floor goes. Both screens are the main
# screen's logical size (2227x1253) in its palette (copied as the virtual screens', removed after).
# Screenshots in $N/out: docked, away, back, freed. Exit 0 = all good.
#   tools/nested/test-floor.sh [OUT_DIR]      (copies the shots there too)
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
copy_to=${1:-}
state="$HOME/.local/state/rice"
for s in 0 1; do
    [ -e "$state/palette-Virtual-$s.json" ] && { echo "a palette-Virtual-$s.json is already there: not touching it" >&2; exit 2; }
done
# (with the floor's colours as rice.py writes them now, in case the main screen's palette predates them)
python3 - "$repo" "$state" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
from atom import panel
p = json.load(open(f"{sys.argv[2]}/palette-HDMI-A-1.json"))
p.setdefault("_floor", panel.floor(p))
for s in (0, 1):
    open(f"{sys.argv[2]}/palette-Virtual-{s}.json", "w").write(json.dumps(p, indent=2) + "\n")
PY
trap 'rm -f "$state/palette-Virtual-0.json" "$state/palette-Virtual-1.json"' EXIT

wall=$(python3 -c "import json; print(json.load(open('$state/palette-HDMI-A-1.json'))['_wallpaper'])")
pins="preferred://filemanager,applications:org.kde.konsole.desktop,applications:zen.desktop"
t=$(mktemp -d)
source "$here/bar-applets.sh"
{ bar_applets 0 1 30 "$wall" "$pins"; bar_applets 1 2 31 "$wall" "$pins"; } > "$t/appletsrc"

cat > "$t/inner.sh" <<'I'
#!/bin/bash
source "$ATOM_NESTED/env.sh"
for p in 1 2; do printf '[PlasmaViews][Panel %s]\nfloating=0\n\n[PlasmaViews][Panel %s][Defaults]\nthickness=69\n\n' $p $p; done > "$N/config/plasmashellrc"
cp "$HOME/.cache/claude-usage.json" "$N/cache/" 2>/dev/null
start_plasma 12
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "desktops().forEach(d => { d.currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General']; d.writeConfig('Image', 'file://$WALL') })" >/dev/null
kw() { python3 -c "import sys; sys.path.insert(0, sys.argv[2]); from atom import kwinscript; print(kwinscript.run(sys.argv[1], answer=True))" "$1" "$REPO"; }
python3 "$REPO/tools/nested/bar_looks.py" "$REPO" 260 >> "$N/out/app.log" 2>&1
# the islands on one screen at a time: the rice's own KWin script, from a fresh path (KWin caches by path)
cp "$REPO/kwin/rice_islands/contents/ui/main.qml" "$N/islands.qml"
sid=$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript "$N/islands.qml" rice_islands_test)
qdbus6 org.kde.KWin /Scripting/Script$sid org.kde.kwin.Script.run
echo "islands script $sid" >> "$N/out/app.log"
$F move 1100 600 wait 300 move 1110 610 wait 1500
qml6 "$REPO/tools/nested/app.qml" >> "$N/out/app.log" 2>&1 & app=$!
sleep 2
kw 'workspace.windowList().filter(w => w.caption === "user app").forEach(w => w.setMaximize(true, true)); answer(workspace.windowList().filter(w => w.caption === "user app").map(w => w.output.name + " " + Math.round(w.y + w.height)).join(","))' | sed 's/^/app at /' >> "$N/out/app.log"
sleep 2; mark "docked"; shot docked
$F move 3300 600 wait 300 move 3310 610 wait 1500; mark "away"; shot away
[ -n "${FLOOR_DEBUG:-}" ] && kw 'answer(workspace.stackingOrder.map(w => [w.resourceClass, w.caption, w.layer, w.output ? w.output.name : "?", Math.round(w.x), Math.round(w.y), Math.round(w.width), Math.round(w.height), w.opacity.toFixed(2)].join(":")).join(" | "))' | sed 's/^/stack /' >> "$N/out/app.log"
$F move 1100 600 wait 300 move 1110 610 wait 1500; mark "back"; shot back
$F move 3300 600 wait 300 move 3310 610 wait 1200
kw 'workspace.windowList().filter(w => w.caption === "user app").forEach(w => w.setMaximize(false, false)); answer("ok")' >> "$N/out/app.log"
sleep 1.5; mark "freed"; shot freed
kill $app; stop_plasma
I
chmod +x "$t/inner.sh"
N=$(WALL="$wall" ATOM_NESTED_OUTPUTS=2 ATOM_NESTED_W=2227 ATOM_NESTED_H=1253 "$here/run.sh" --plasma "$t/appletsrc" "$t/inner.sh" 150 | tail -1)
L="$N/out/plasmashell.log"
fail=0
check() { if grep -q -- "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
check "the rice's looks applied" 'applied True' "$N/out/app.log"
check "the window maximized on screen 1" 'app at Virtual-0' "$N/out/app.log"
# screen 1's strip, between the pins and the meters (the stretch: floor or wallpaper, never an island): the
# docked shot's is the floor in the bar; away must match it, freed must not (bare wallpaper again)
python3 - "$N/out" <<'PY' || fail=1
import sys
from PIL import Image, ImageStat
out = sys.argv[1]
def strip(name):
    im = Image.open(f"{out}/{name}.png").convert("RGB")
    return im.crop((780, 1253 - 60, 980, 1253 - 8))
def diff(a, b):
    return sum(abs(x - y) for x, y in zip(ImageStat.Stat(a).mean, ImageStat.Stat(b).mean)) / 3
def rough(a):           # the floor is smooth glass; bare wallpaper has detail
    return sum(ImageStat.Stat(a).stddev) / 3
docked, away, back, freed = (strip(n) for n in ("docked", "away", "back", "freed"))
floorish = lambda s: rough(s) < 6 and diff(docked, s) < 10
ok = True
for label, s, want in (("docked is the floor", docked, True), ("away keeps the floor", away, True),
                       ("back looks docked", back, True), ("freed shows the wallpaper", freed, False)):
    good = floorish(s) == want
    ok &= good
    print(("ok  " if good else "FAIL"), f"{label} (roughness {rough(s):.1f}, difference {diff(docked, s):.1f})")
sys.exit(0 if ok else 1)
PY
[ -n "$copy_to" ] && mkdir -p "$copy_to" && cp "$N"/out/*.png "$L" "$N/out/app.log" "$copy_to"/ 2>/dev/null
echo "shots: $N/out"
exit $fail
