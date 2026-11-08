#!/bin/bash
# The shell's sheet in a nested Plasma (tools/nested/run.sh): it opens from its island, follows the
# pointer to another island, takes typing while open, closes on Esc, a click elsewhere or its island
# clicked again, and every time hands the keyboard back to the window that had it. Exit 0 = all good.
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
cat > "$t/appletsrc" <<'A'
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
plugin=com.atom.test.islanda

[Containments][1][Applets][3]
immutability=1
plugin=org.kde.plasma.panelspacer

[Containments][1][Applets][4]
immutability=1
plugin=com.atom.test.islandb

[Containments][1][Applets][5]
immutability=1
plugin=com.zinoxx.shell

[Containments][1][General]
AppletOrder=2;3;4;5
A
cat > "$t/inner.sh" <<'I'
#!/bin/bash
source "$ATOM_NESTED/env.sh"
start_plasma 6
qml6 "$REPO/tools/nested/app.qml" >> "$N/out/app.log" 2>&1 & app=$!
# the islands report where they are a few seconds in
for i in $(seq 30); do grep -q "island b at" "$L" && break; sleep 0.3; done
at() { grep "island $1 at" "$L" | tail -1 | sed -E 's/.*"x":([0-9.]+),"y":([0-9.]+),"width":([0-9.]+),"height":([0-9.]+).*/\1 \2 \3 \4/' | awk '{ printf "%d %d", $1 + $3 / 2, $2 + $4 / 2 }'; }
A=$(at a); B=$(at b)
step() { mark "$1"; echo "## $1" >> "$N/out/app.log"; }
step "focus app";        $F move 800 450 click wait 300 type "a" wait 300
step "open a";           $F move $A click wait 600; shot open
step "type in panel";    $F type "hello" wait 300
step "hover b";          $F move $B wait 700; shot switched
step "esc";              $F key 1 wait 700
step "type b";           $F type "b" wait 400
step "open a";           $F move $A click wait 700
step "click desktop";    $F move 300 150 click wait 700
step "focus app";        $F move 800 450 click wait 300
step "open a";           $F move $A click wait 700
step "click app";        $F move 800 450 click wait 700
step "type c";           $F type "c" wait 300
step "open a";           $F move $A click wait 700
step "click a again";    $F move $A click wait 700
step "type d";           $F type "d" wait 300
step end
kill $app; stop_plasma
I
chmod +x "$t/inner.sh"
N=$("$here/run.sh" --plasma "$t/appletsrc" "$t/inner.sh" 90 | tail -1)
L="$N/out/plasmashell.log"
fail=0
check() { if grep -q -- "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
check "panel opened from island a"        'shell kind "demo"' "$L"
check "typing reached the panel"          'demo typed "hello"' "$L"
check "hover moved it to island b"        'shell kind "demo2"' "$L"
check "keyboard back to the app after Esc"            'app typed "ab"' "$N/out/app.log"
check "a click on the app closes it and keeps focus"  'app typed "abc"' "$N/out/app.log"
check "keyboard back after its island closed it"      'app typed "abcd"' "$N/out/app.log"
if grep -q "surface tapped" "$L"; then echo "FAIL a click landed on the transparent surface"; fail=1; else echo "ok   no stray clicks on the surface"; fi
if grep -E "^(qml: )?.*(Error|TypeError|ReferenceError)" "$L" | grep -v -i portal | grep -i -E "atom|shell|sheet" ; then fail=1; fi
echo "logs: $N/out"
exit $fail
