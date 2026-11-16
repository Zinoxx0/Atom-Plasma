#!/bin/bash
# Clawd's roof (ClawdRoof.qml, a layer surface) when its screen MOVES: nested on two screens with the real
# islands script (kwin/rice_islands), the islands on screen A (its roof mapped), then the two screens swap
# places in one output change, as when a monitor comes back after a power cut (2026-11-16: the 1440p went
# from x 0 to 2400 and its roof Clawd stayed at the old spot, floating on the 4K). The roof must stand on its
# own bar's screen, its bottom on that screen's bottom edge: before the swap, right after it, and after the
# islands leave and come back. Exit 0 = all good.
#   tools/nested/test-roof-move.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
state="$HOME/.local/state/rice"
for s in 0 1 2; do
    [ -e "$state/palette-Virtual-$s.json" ] && { echo "a palette-Virtual-$s.json is already there: not touching it" >&2; exit 2; }
done
for s in 0 1 2; do cp "$state/palette-HDMI-A-1.json" "$state/palette-Virtual-$s.json"; done
trap 'rm -f "$state/palette-Virtual-0.json" "$state/palette-Virtual-1.json" "$state/palette-Virtual-2.json"' EXIT

wall=$(python3 -c "import json; print(json.load(open('$state/palette-HDMI-A-1.json'))['_wallpaper'])")
pins="preferred://filemanager,applications:org.kde.konsole.desktop"
t=$(mktemp -d)
source "$here/bar-applets.sh"
{ bar_applets 0 1 30 "$wall" "$pins"; bar_applets 1 2 31 "$wall" "$pins"; bar_applets 2 3 32 "$wall" "$pins"; } > "$t/appletsrc"

cat > "$t/inner.sh" <<'I'
#!/bin/bash
source "$ATOM_NESTED/env.sh"
for p in 1 2 3; do printf '[PlasmaViews][Panel %s]\nfloating=0\n\n[PlasmaViews][Panel %s][Defaults]\nthickness=69\n\n' $p $p; done > "$N/config/plasmashellrc"
cp "$HOME/.cache/claude-usage.json" "$N/cache/" 2>/dev/null
# this machine's shape: A = the 4K (scale 1.6, last in priority, on the left), B = the 1440p (1.15, the main
# screen), C = the laptop (1.25); logical widths 1392 / 1937 / 1782
kscreen-doctor output.Virtual-0.scale.1.6 output.Virtual-1.scale.1.15 output.Virtual-2.scale.1.25 \
    output.Virtual-1.priority.1 output.Virtual-2.priority.2 output.Virtual-0.priority.3 \
    output.Virtual-0.position.0,0 output.Virtual-1.position.1392,0 output.Virtual-2.position.3329,0 >> "$N/out/app.log" 2>&1
sleep 1
start_plasma 12
kw() { python3 -c "import sys; sys.path.insert(0, sys.argv[2]); from atom import kwinscript; print(kwinscript.run(sys.argv[1], answer=True))" "$1" "$REPO"; }
python3 "$REPO/tools/nested/bar_looks.py" "$REPO" 260 >> "$N/out/app.log" 2>&1
cp "$REPO/kwin/rice_islands/contents/ui/main.qml" "$N/islands.qml"
sid=$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript "$N/islands.qml" rice_islands_test)
qdbus6 org.kde.KWin /Scripting/Script$sid org.kde.kwin.Script.run
# each output's geometry, each bar (output, opacity) and each roof window (a small plasmashell dock surface)
dump() {
    kw 'const sh = workspace.stackingOrder.filter(w => String(w.resourceClass).includes("plasmashell") && w.dock);
        const out = {}; for (const o of workspace.screens) { const g = o.geometry; out[o.name] = [g.x, g.y, g.width, g.height]; }
        const bars = sh.filter(w => w.width > 1000 && w.height > 40 && w.height < 120).map(w => [w.output.name, +w.opacity.toFixed(2)]);
        const roofs = sh.filter(w => w.width < 800 && w.height > 40).map(w => [w.output.name, Math.round(w.x), Math.round(w.y), Math.round(w.width), Math.round(w.height)]);
        answer(JSON.stringify({out, bars, roofs, cursor: [workspace.cursorPos.x, workspace.cursorPos.y]}))' | sed "s/^/STATE $1 /" >> "$N/out/app.log"
}
on() { $F move $1 600 wait 300 move $(( $1 + 10 )) 610 wait 2500; }
A=1392; B=1937; C=1782
on $(( A + 900 )); dump before; shot before
# a monitor leaves and comes back (2026-11-16, a power cut: the 4K went, the 1440p slid from x 2400 to 0,
# the 4K came back first as a 640x480 stand-in on the far right, then as itself on the left, pushing the
# 1440p back): screen B carries the islands throughout (the pointer follows it)
kscreen-doctor output.Virtual-0.disable output.Virtual-1.position.0,0 output.Virtual-2.position.$B,0 >> "$N/out/app.log" 2>&1
on 900; dump gone
kscreen-doctor output.Virtual-0.enable output.Virtual-0.position.$(( B + C )),0 >> "$N/out/app.log" 2>&1
on 900; dump standin
kscreen-doctor output.Virtual-0.disable >> "$N/out/app.log" 2>&1
on 900; dump off
kscreen-doctor output.Virtual-0.enable output.Virtual-0.position.0,0 output.Virtual-1.position.$A,0 output.Virtual-2.position.$(( A + B )),0 >> "$N/out/app.log" 2>&1
on $(( A + 900 )); dump back; shot back
# the islands leave B and come back (the roof is unmapped and mapped again)
on 900; on $(( A + 900 )); dump again; shot again
stop_plasma
I
chmod +x "$t/inner.sh"
N=$(WALL="$wall" ATOM_NESTED_OUTPUTS=3 ATOM_NESTED_W=2227 ATOM_NESTED_H=1253 "$here/run.sh" --plasma "$t/appletsrc" "$t/inner.sh" 150 | tail -1)
python3 - "$N/out/app.log" <<'PY'
import json, sys
fail = 0
states = {}
for line in open(sys.argv[1]):
    if line.startswith("STATE "):
        _, label, js = line.rstrip("\n").split(" ", 2)
        states[label] = json.loads(js)
for label in ("before", "gone", "standin", "off", "back", "again"):
    s = states.get(label)
    if not s:
        print(f"FAIL {label}: no state"); fail = 1; continue
    shown = [o for o, op in s["bars"] if op > 0.9]
    ok = len(shown) == 1 and len(s["roofs"]) == 1
    if ok:
        x, y, w, h = s["out"][shown[0]]
        _, rx, ry, rw, rh = s["roofs"][0]
        ok = x <= rx and rx + rw <= x + w and abs((ry + rh) - (y + h)) <= 1
    print(f"{'ok  ' if ok else 'FAIL'} {label}: bar shown on {shown}, roofs {s['roofs']}, outputs {s['out']}")
    fail |= not ok
sys.exit(fail)
PY
fail=$?
echo "$N"
exit $fail
