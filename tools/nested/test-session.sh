#!/bin/bash
# The session island's panel on the shell's sheet (nested Plasma): it grows out of the island, its actions
# come in, Esc closes it and the keyboard goes back. Exit 0 = all good.
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
step "open session";  $F move $S click wait 120; shot s-grow; $F wait 800; shot s-open
step "hover tile";    $F move 1400 780 wait 400; shot s-hover
step "esc";           $F key 1 wait 600; shot s-closed
step "type b";        $F type "b" wait 300
step end
kill $app; stop_plasma
I
chmod +x "$t/inner.sh"
N=$("$here/run.sh" --plasma "$t/appletsrc" "$t/inner.sh" 90 | tail -1)
L="$N/out/plasmashell.log"
fail=0
check() { if grep -q -- "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
check "the island opened the session panel"  'shell kind "session"' "$L"
check "keyboard back to the app after Esc"   'app typed "ab"' "$N/out/app.log"
errs=$(grep -E "Session|session|Atom" "$L" | grep -E "Error|TypeError|ReferenceError|Cannot|Unable|not a type|is not defined|Could not set" | sort -u | head)
[ -n "$errs" ] && { echo "$errs"; fail=1; }
echo "logs: $N/out"
exit $fail
