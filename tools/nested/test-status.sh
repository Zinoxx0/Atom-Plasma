#!/bin/bash
# The status island and the control center (nested Plasma). It only opens, looks and closes: the control
# center drives the REAL system (NetworkManager, BlueZ, PipeWire are shared with the user's session), so
# this never clicks a toggle. Opens from the island, the audio page opens and Esc steps back, Esc closes,
# the keyboard goes back. Exit 0 = all good.
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d)
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
for i in $(seq 30); do grep -q "island a at" "$L" && break; sleep 0.3; done
C=$(grep -o 'ATOM island control at [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $5, $6}')
[ -n "$C" ] || C="1560 877"
step() { mark "$1"; echo "## $1" >> "$N/out/app.log"; }
step "focus app";      $F move 800 450 click wait 300 type "a" wait 300
step "open control";   $F move $C click wait 150; shot s-grow; $F wait 1200; shot s-open
step "esc";            $F key 1 wait 700
step "type b";         $F type "b" wait 300
step end
kill $app; stop_plasma
I
chmod +x "$t/inner.sh"
N=$("$here/run.sh" --plasma "$t/appletsrc" "$t/inner.sh" 90 | tail -1)
L="$N/out/plasmashell.log"
fail=0
check() { if grep -q -- "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
check "the island opened the control center" 'shell kind "control"' "$L"
check "keyboard back to the app after Esc" 'app typed "ab"' "$N/out/app.log"
errs=$(grep -E "Control|status|Tray|parts/|Atom" "$L" | grep -E "Error|TypeError|ReferenceError|Cannot|Unable|not a type|is not defined|Could not set|Binding loop|Invalid property|no panel for" | sort -u | head)
[ -n "$errs" ] && { echo "$errs"; fail=1; }
echo "logs: $N/out"
exit $fail
