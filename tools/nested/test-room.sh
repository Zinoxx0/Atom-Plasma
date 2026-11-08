#!/bin/bash
# The room's lights in a nested Plasma: the status island's light button (shown while the Room light
# service says home) opens the Room panel on the sheet; the control center has the Room row. It only
# opens, looks and closes: the lamp and the strip are the REAL ones (their services are on localhost), so
# this never clicks a light's control. Needs `roomlight serve` running. Exit 0 = all good.
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
plugin=com.zinoxx.status

[Containments][1][Applets][5]
immutability=1
plugin=com.zinoxx.shell

[Containments][1][General]
AppletOrder=2;3;4;5
A
cat > "$t/inner.sh" <<'I'
#!/bin/bash
source "$ATOM_NESTED/env.sh"
start_plasma 7
qml6 "$REPO/tools/nested/app.qml" >> "$N/out/app.log" 2>&1 & app=$!
for i in $(seq 40); do grep -q "island room at" "$L" && break; sleep 0.3; done
R=$(grep -o 'ATOM island room at [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $5, $6}')
C=$(grep -o 'ATOM island control at [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $5, $6}')
step() { mark "$1"; echo "## $1" >> "$N/out/app.log"; }
step "focus app";      $F move 800 450 click wait 300 type "a" wait 300
step "open control";   $F move $C click wait 1500; shot r-control
step "esc";            $F key 1 wait 800
step "room button [$R]"; [ -n "$R" ] && { $F move $R click wait 1800; shot r-room; }
step "esc";            $F key 1 wait 800
step "type b";         $F type "b" wait 300
step end
kill $app; stop_plasma
I
chmod +x "$t/inner.sh"
N=$("$here/run.sh" --plasma "$t/appletsrc" "$t/inner.sh" 90 | tail -1)
L="$N/out/plasmashell.log"
fail=0
check() { if grep -q -- "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
check "the light button is on the island (home)" 'ATOM island room at' "$L"
check "it opened the Room panel" 'shell kind "room"' "$L"
check "keyboard back to the app after Esc" 'app typed "ab"' "$N/out/app.log"
errs=$(grep -E "Room|RoomLight|status|Control|Chip|Spectrum|HueField|Atom" "$L" | grep -E "Error|error:|TypeError|ReferenceError|Cannot|Unable|not a type|is not defined|Invalid property|no panel for" | sort -u | head -20)
[ -n "$errs" ] && { echo "$errs"; fail=1; }
echo "logs: $N/out"
exit $fail
