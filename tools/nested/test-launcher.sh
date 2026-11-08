#!/bin/bash
# The fullscreen launcher in a nested Plasma (tools/nested/run.sh): it grows out of the jewel, takes typing
# (search), Esc clears then closes it and the keyboard goes back to the app; Meta (plasmashell's
# activateLauncherMenu) opens it on the active window's screen; the power orb blooms; the Theme page
# opens. Screenshots in the logs folder. Exit 0 = all good.
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
step "click jewel";     $F move $J click wait 200; shot l-grow-1; $F wait 300; shot l-grow-2; $F wait 1600; shot l-open
step "type";            $F type "fire" wait 1500; shot l-search
step "esc clears";      $F key 1 wait 700; shot l-cleared
step "esc closes";      $F key 1 wait 200; shot l-closing; $F wait 900; shot l-closed
step "type x (app?)";   $F type "x" wait 300
step "meta";            qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu; $F wait 2200; shot l-meta
S0=$(grep -o 'ATOM stage stack0 at [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $5, $6}')
step "hover stack at [$S0]"; $F move $S0 wait 600; shot l-hover
step "open folder";     $F move $S0 click wait 900; shot l-folder
step "esc folds";       $F key 1 wait 600; shot l-folded
step "theme";           $F move 1470 835 click wait 1200; shot l-theme
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
check "a stack opened as a folder, Esc folded it" 'ATOM stage folder' "$L"
errs=$(grep -E "launcher|Stage|Atom|PowerOrb" "$L" | grep -E "Error|error:|TypeError|ReferenceError|Cannot|Unable|not a type|is not defined" | sort -u | head -20)
[ -n "$errs" ] && { echo "$errs"; fail=1; }
echo "logs: $N/out"
exit $fail
