#!/bin/bash
# The power overlay (nested Plasma): the session island opens it, a ripple of blur spreads from the island,
# the actions come up big; Esc closes it and the keyboard goes back; a click on the blur closes it too.
# Exit 0 = all good.
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
plugin=com.zinoxx.session

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
S=$(grep -o 'ATOM island session at [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $5, $6}')
[ -n "$S" ] || S="1570 877"
step() { mark "$1"; echo "## $1" >> "$N/out/app.log"; }
step "focus app";     $F move 800 450 click wait 300 type "a" wait 300
step "open power";    $F move $S click wait 250; shot p-ripple; $F wait 900; shot p-open
step "hover button";  $F move 800 560 wait 500; shot p-hover
step "esc";           $F key 1 wait 700; shot p-closed
step "type b";        $F type "b" wait 300
step "open again";    $F move $S click wait 1200
step "click blur";    $F move 300 200 click wait 800
step end
kill $app; stop_plasma
I
chmod +x "$t/inner.sh"
N=$("$here/run.sh" --plasma "$t/appletsrc" "$t/inner.sh" 90 | tail -1)
L="$N/out/plasmashell.log"
fail=0
check() { if grep -q -- "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
check "the island opened the power overlay"   'ATOM power Virtual-0 phase open lead true' "$L"
check "keyboard back to the app after Esc"   'app typed "ab"' "$N/out/app.log"
n=$(grep -c 'ATOM power Virtual-0 phase closed' "$L"); [ "$n" -ge 2 ] && echo "ok   a click on the blur closed it" || { echo "FAIL a click on the blur closed it"; fail=1; }
errs=$(grep -E "Power|power|Atom|Session" "$L" | grep -E "Error|TypeError|ReferenceError|Cannot|Unable|not a type|is not defined|Could not set|Invalid property|no panel for" | sort -u | head)
[ -n "$errs" ] && { echo "$errs"; fail=1; }
echo "logs: $N/out"
exit $fail
