#!/bin/bash
# The launcher (Atom Home) in a nested Plasma (tools/nested/run.sh): it opens out of the jewel, the arrows
# walk the rows, Tab switches pages, typing searches; Esc clears the query, leaves the search, then closes
# it and the keyboard goes back to the app; Meta (plasmashell's activateLauncherMenu) opens it on the
# active window's screen; the palette opens the Theme page (the themes, then its groups, all closed whenever it
# opens: Enter on a header opens it; the arrows walk it, up reaches a row's own tools in its header, "Find more
# online" opens the detailed panels, Esc leaves them, then the page; a size slider takes left and right and
# applies once the keys pause); a left click on bare space keeps it open, a right click closes it; a pretend
# game controller (pad.py) walks and opens it too. Nothing on the Theme page is APPLIED here: rice.py
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
printf 'simplified\n' > "$N/config/atom-test-style"     # this tests the simplified style, whatever the user picked
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
step "theme down";      $F move 800 20 key 108 wait 900                        # down: the Look group's header (row 1, under the themes)
step "open Look";       $F key 28 wait 1200
step "down to the walls"; $F key 108 wait 1200; shot l-tools                    # down: the wallpapers' header tools first
step "tools right";     $F key 106 wait 900; shot l-theme-walls
W=$(grep -o 'ATOM home focus at [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $NF}')      # the walls row (it has the focus)
step "drag the page [$W]"; $F drag 800 ${W:-550} 800 $(( ${W:-550} - 200 )) wait 1200; shot l-drag      # (dragging moves the page up)
step "back up";         $F move 800 300 wait 200 drag 800 300 800 700 wait 900 key 103 wait 300 key 103 wait 1200    # (a swipe on the hero: never a click; then to the tools)
X=$(grep -o 'ATOM theme tool walls:discover at [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $(NF-1), $NF}')
step "find more [$X]";  $F move ${X:-400 390} click wait 1400; shot l-fine
step "fine-tune back";  $F key 1 wait 600 key 1 wait 900      # the search it opened on, then the panel
step "theme back";      $F key 1 wait 1200; shot l-theme-back
step "theme again";     $F move ${T:-1470 50} click wait 1400 move 800 20 key 108 wait 700 key 108 wait 900     # (Look closed again: down, down = Launcher)
step "open Launcher";   $F key 28 wait 1200 key 108 wait 900; shot l-slider                                     # its first row: the size slider
step "slide";           $F key 106 wait 150 key 106 wait 1500; shot l-slid                                     # two steps up, applied after the pause
step "theme back again"; $F key 1 wait 1200
step "wheel down";      $F move 800 620 wait 300 wheel 15 wait 1000; shot l-wheel     # (the wheel scrolls the page)
step "wheel up";        $F move 802 620 wait 300 wheel -15 wait 1000
step "keys first";      $F key 106 wait 1300
P=$(grep -o 'ATOM home focus at [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $(NF-1) + 110, $NF}')    # the next tile along
step "pointer on a tile [$P]"; $F move 900 300 wait 100 glide 900 300 ${P:-640 700} 250 wait 700; shot l-hover
step "pointer still, keys"; $F key 106 wait 600 key 105 wait 600
step "pad";             python3 "$REPO/tools/nested/pad.py" down right north; $F wait 1200; shot l-pad
step "pad back";        python3 "$REPO/tools/nested/pad.py" east; $F wait 900
step "left click, bare"; $F move 1450 760 click wait 900; shot l-left-click     # (bare space: a left click keeps it open)
step "right click, bare"; $F move 1452 760 click right wait 1300                # (a right click closes it)
step "meta reopens";    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu; $F wait 2200
step "meta closes";     qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu; $F wait 1200; shot l-meta-closed
step "type y (app?)";   $F type "y" wait 300
step "meta again";      qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu; $F wait 2200
step "pad closes";      python3 "$REPO/tools/nested/pad.py" east; $F wait 1200      # B at Home: the launcher closes from inside the pad's read
step "type z (app?)";   $F type "z" wait 300
step "meta after the pad"; qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu; $F wait 1500
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
check "opening cleared the desk (the app was minimized)" 'ATOM windows cleared Virtual-0 [1-9]' "$L"
check "down moved the focus a row"  'ATOM home tab 0 row 1' "$L"
check "tab switched to Games"       'ATOM home tab 1' "$L"
check "typing opened the search"    'ATOM home search "f"' "$L"
check "the palette opened the Theme page" 'ATOM home tab 3 row 0' "$L"
check "down walked the Theme page"  'ATOM theme line tiles row 1' "$L"
check "down reached the row's tools" 'ATOM theme line tools row 2 tool walls:random' "$L"
check "right walked the tools"      'ATOM theme line tools row 2 tool walls:folder' "$L"
check "the page opened on the themes, every group closed" 'ATOM home tab 3 row 1 item Look (key)' "$L"
check "Enter opened the Look group" 'ATOM theme group look open' "$L"
check "Find more opened the panels" 'ATOM stage view walls' "$L"
after() { sed -n "/ATOM ## $2/,\$p" "$L" | grep -q -- "$3" && echo "ok   $1" || { echo "FAIL $1"; fail=1; }; }
after "Esc left the Theme page"     "theme back" 'ATOM home tab 0 row'
after "dragging moved the page"       "drag the page" 'ATOM page dragged to [1-9]'
after "the page opened again with Look closed" "theme again" 'ATOM home tab 3 row 2 item Launcher (key)'
after "the slider took the keys"      "slide" 'ATOM theme slide lsize [0-9.]*$'
after "...and applied once they paused (a dry run)" "slide" 'ATOM theme run .*rice.py launcher size [0-9.]*$'
notbetween() { sed -n "/ATOM ## $2/,/ATOM ## $3/p" "$L" | grep -q -- "$4" && { echo "FAIL $1"; fail=1; } || echo "ok   $1"; }
notbetween "the wheel scrolled, it didn't walk the focus" "wheel down" "keys first" 'ATOM home tab 0 row 1'
after "the pointer moving took over"  "pointer on a tile" 'ATOM home input pointer'
after "...and focused what it rested on" "pointer on a tile" '(mouse)'
after "a key took it back"            "pointer still, keys" 'ATOM home input keys'
notbetween "...and the still pointer didn't grab it back" "pointer still, keys" "pad" '(mouse)'
after "the pad walked down"           "pad" 'ATOM home tab 0 row 1 .*(key)'
after "...and its Y opened the Theme page" "pad" 'ATOM home tab 3'
after "...and its B left it"          "pad back" 'ATOM home tab 0 row'
between() { sed -n "/ATOM ## $2/,/ATOM ## $3/p" "$L" | grep -q -- "$4" && echo "ok   $1" || { echo "FAIL $1"; fail=1; }; }
between "a left click on bare space was seen" "left click, bare" "right click, bare" 'ATOM stage bare click left'
notbetween "...and didn't close the launcher" "left click, bare" "right click, bare" 'shell kind ""'
between "a right click there closed it"  "right click, bare" "meta reopens" 'shell kind ""'
after "the pad's B closed the launcher"  "pad closes" 'shell kind ""'
check "...and the keyboard came back"     'app typed "axyz"' "$N/out/app.log"
after "...and plasmashell lived on (it crashed here once)" "meta after the pad" 'shell kind "launcher"'
swap=$(grep -o 'ATOM home tab swap [0-9]*' "$L" | awk '{print $NF}' | sort -n | tail -1)
[ "${swap:-999}" -lt 200 ] && echo "ok   page switches are quick (slowest ${swap} ms)" || { echo "FAIL a page switch took ${swap} ms"; fail=1; }
grep -q "ATOM home apply" "$L" && { echo "FAIL something was applied"; fail=1; }
errs=$(grep -E "launcher|Stage|Home|Theme|Atom|Jewel|TopButton|DeskMap" "$L" | grep -E "Error|error:|TypeError|ReferenceError|Cannot|Unable|not a type|is not defined|Invalid property|no panel for" | sort -u | head -20)
[ -n "$errs" ] && { echo "$errs"; fail=1; }
echo "logs: $N/out"
exit $fail
