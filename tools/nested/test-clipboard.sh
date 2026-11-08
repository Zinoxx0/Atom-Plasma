#!/bin/bash
# The clipboard's history panel (nested Plasma; Meta+V opens it live, here a test island does): Klipper runs
# without the stock clipboard applet, copies show up, a click makes one the clipboard again. Exit 0 = all good.
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
plugin=com.atom.test.islandc

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
C=$(grep -o 'ATOM island clipboard at [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $5, $6}')
[ -n "$C" ] || C="1540 877"
step() { mark "$1"; echo "## $1" >> "$N/out/app.log"; }
step "copy";           echo -n "first copy" | wl-copy; sleep 0.6; echo -n "https://example.org/second" | wl-copy; sleep 0.6; echo -n "third: the latest" | wl-copy; sleep 0.8
step "focus app";      $F move 800 450 click wait 300 type "a" wait 300
step "open clipboard"; $F move $C click wait 1200; shot cb-open
step "search";         $F type "first" wait 600; shot cb-search
step "take it";        $F key 28 wait 700
echo "pasted: $(timeout 2 wl-paste 2>&1)" >> "$N/out/app.log"
step "type b";         $F move 800 450 click wait 300 type "b" wait 300
step end
kill $app; stop_plasma
I
chmod +x "$t/inner.sh"
N=$("$here/run.sh" --plasma "$t/appletsrc" "$t/inner.sh" 90 | tail -1)
L="$N/out/plasmashell.log"
fail=0
check() { if grep -q -- "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
check "the island opened the clipboard"     'shell kind "clipboard"' "$L"
check "Enter made the match the clipboard"  'pasted: first copy' "$N/out/app.log"
check "keyboard back to the app"           'app typed "ab"' "$N/out/app.log"
errs=$(grep -E "Clipboard|clipboard|Notify|Atom" "$L" | grep -E "Error|TypeError|ReferenceError|Cannot|Unable|not a type|is not defined|Could not set|Binding loop|Invalid property|no panel for" | sort -u | head)
[ -n "$errs" ] && { echo "$errs"; fail=1; }
echo "logs: $N/out"
exit $fail
