#!/bin/bash
# The launcher (Atom Home) in a nested Plasma (tools/nested/run.sh): it opens out of the jewel, the arrows
# walk the rows, Tab switches pages, typing searches; Esc clears the query, leaves the search, then closes
# it and the keyboard goes back to the app; Meta (plasmashell's activateLauncherMenu) opens it on the
# active window's screen; the palette opens the Theme page (a page of rows: the arrows walk it, a hero action
# opens the detailed panels, Esc leaves them, then the page). Nothing on the Theme page is APPLIED here: rice.py
# and rgb.py would change the user's real theme and keyboards. Screenshots in the logs folder. Exit 0 = all good.
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
plugin=com.zinoxx.launcher

[Containments][1][Applets][3]
immutability=1
plugin=org.kde.plasma.panelspacer

[Containments][1][Applets][4]
immutability=1
plugin=com.atom.test.islanda

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
J=$(grep -o 'ATOM island launcher at [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $5, $6}')
[ -n "$J" ] || J="40 877"
step() { mark "$1"; echo "## $1" >> "$N/out/app.log"; }
step "focus app";       $F move 800 450 click wait 300 type "a" wait 300
step "click jewel";     $F move $J click wait 120; shot l-grow-1; $F wait 250; shot l-grow-2; $F wait 1500; shot l-open
step "down";            $F key 108 wait 900; shot l-down
step "right";           $F key 106 wait 600
step "tab";             $F key 15 wait 1100; shot l-games
step "type";            $F type "fire" wait 1500; shot l-search
step "esc clears";      $F key 1 wait 500
step "esc leaves search"; $F key 1 wait 600
step "esc closes";      $F key 1 wait 200; shot l-closing; $F wait 900; shot l-closed
step "type x (app?)";   $F type "x" wait 300
step "meta";            qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu; $F wait 2200; shot l-meta
T=$(grep -o 'ATOM home tabs at .* theme at [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $(NF-1), $NF}')
step "theme [$T]";      $F move ${T:-1470 50} click wait 1400; shot l-theme
step "theme down";      $F move 800 20 key 108 wait 1200; shot l-theme-walls
X=$(grep -o 'ATOM theme action fine:walls at [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $(NF-1), $NF}')
step "fine-tune [$X]";  $F move ${X:-400 390} click wait 1400; shot l-fine
step "fine-tune back";  $F key 1 wait 900
step "theme back";      $F key 1 wait 1200; shot l-theme-back
step "meta closes";     qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu; $F wait 1200; shot l-meta-closed
step "type y (app?)";   $F type "y" wait 300
step end
kill $app; stop_plasma
I
chmod +x "$t/inner.sh"
N=$("$here/run.sh" --plasma "$t/appletsrc" "$t/inner.sh" 120 | tail -1)
L="$N/out/plasmashell.log"
fail=0
check() { if grep -q -- "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
check "the jewel opened the launcher"   'shell kind "launcher"' "$L"
check "keyboard back to the app after Esc"  'app typed "ax"' "$N/out/app.log"
check "Meta closed it and the keyboard came back" 'app typed "axy"' "$N/out/app.log"
check "opening cleared the desk (the app was minimized)" 'app active false' "$N/out/app.log"
check "down moved the focus a row"  'ATOM home tab 0 row 1' "$L"
check "tab switched to Games"       'ATOM home tab 1' "$L"
check "typing opened the search"    'ATOM home search "f"' "$L"
check "the palette opened the Theme page" 'ATOM home tab 3 row 0' "$L"
check "down walked the Theme page"  'ATOM home tab 3 row 1' "$L"
check "Fine-tune opened the panels" 'ATOM stage view walls' "$L"
after() { sed -n "/ATOM ## $2/,\$p" "$L" | grep -q -- "$3" && echo "ok   $1" || { echo "FAIL $1"; fail=1; }; }
after "Esc left the Theme page"     "theme back" 'ATOM home tab 0 row'
grep -q "ATOM home apply" "$L" && { echo "FAIL something was applied"; fail=1; }
errs=$(grep -E "launcher|Stage|Home|Theme|Atom|Jewel|TopButton|DeskMap" "$L" | grep -E "Error|error:|TypeError|ReferenceError|Cannot|Unable|not a type|is not defined|Invalid property|no panel for" | sort -u | head -20)
[ -n "$errs" ] && { echo "$errs"; fail=1; }
echo "logs: $N/out"
exit $fail
