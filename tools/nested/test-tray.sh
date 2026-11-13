#!/bin/bash
# The status island's app icons (nested Plasma; pretend apps from trayapp.py, a bare watcher from
# sniwatcher.py since kded isn't running there). The quiet icons stand in one stack, which fans out under
# the pointer; a click on an app's icon brings its minimized window back and a second click (it has the
# focus) sends it down; an app with no window is asked to open; a notification slides its app out of the
# stack, and seeing it (its window gets the focus) puts it back. Exit 0 = all good.
# Not covered: the stack folding back once the pointer leaves. The nested fake pointer never sends a leave
# (not even to a plain window), so whatever it last hovered stays hovered here.
# ATOM_NESTED_QML=DIR tries an Atom.Native built there (pkg/atom-native/build.sh with ATOM_QML_DEST=DIR).
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
A="$N/out/app.log"
python3 "$REPO/tools/nested/sniwatcher.py" >> "$A" 2>&1 & watcher=$!
sleep 0.5
start_plasma 7
apps=""
for a in "trayalpha --window" traybeta traygamma; do
    python3 "$REPO/tools/nested/trayapp.py" $a >> "$A" 2>&1 & apps="$apps $!"
    sleep 0.4
done
sleep 3
step() { mark "$1"; echo "## $1" >> "$A"; }
kw() { python3 -c "import sys; sys.path.insert(0, sys.argv[2]); from atom import kwinscript; print(kwinscript.run(sys.argv[1], answer=True))" "$1" "$REPO"; }
alpha() { kw "for (const w of workspace.windowList()) if (w.resourceClass == 'trayalpha') answer('alpha minimized=' + w.minimized + ' active=' + (workspace.activeWindow === w))" >> "$A"; }
at() { grep -o "ATOM tray at $1 [0-9]* [0-9]* $2" "$L" | tail -1 | awk '{print $5, $6}'; }

step "stacked";  shot t-stacked
step "minimize"; kw "for (const w of workspace.windowList()) if (w.resourceClass == 'trayalpha') w.minimized = true" >/dev/null; sleep 0.5; alpha
S=$(at trayalpha "stack stacked")
step "hover";    $F move ${S:-1400 880} wait 900; shot t-open
P=$(at trayalpha "stack open")
step "restore";  $F move ${P:-1400 880} wait 300 click wait 800; alpha
step "down";     $F move ${P:-1400 880} wait 300 click wait 800; alpha
P=$(at traybeta "stack open")
step "no window"; $F move ${P:-1400 880} wait 700 click wait 800; alpha
step "news";     gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
                     --method org.freedesktop.Notifications.Notify trayalpha 0 "" "Hello" "something new" "[]" "{}" 4000 >/dev/null
                 $F wait 1500; shot t-news
P=$(at trayalpha "alone [a-z]*")
step "seen";     $F move ${P:-1400 880} wait 700 click wait 1500; alpha; shot t-seen
step end
kill $apps $watcher; stop_plasma
I
chmod +x "$t/inner.sh"
N=$("$here/run.sh" --plasma "$t/appletsrc" "$t/inner.sh" 90 | tail -1)
L="$N/out/plasmashell.log"
A="$N/out/app.log"
fail=0
check() { if grep -q -- "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
# PATTERN shows up in FILE after the step's mark (and before STOP, a pattern for the line that settles it)
after() { if awk -v m="## $2" -v p="$3" -v q="${5:-^$}" 'index($0, m) { on = 1; next } on && $0 ~ p { f = 1; exit } on && $0 ~ q { exit } END { exit !f }' "$4"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
check "the three quiet icons stand in one stack" "ATOM tray stack 3 alone 0" "$L"
check "the stack fans out under the pointer" "ATOM tray at trayalpha [0-9]* [0-9]* stack open" "$L"
after "a click brings the minimized window back" restore "alpha minimized=false active=true" "$A" "^alpha"
after "a second click sends it down" down "alpha minimized=true" "$A" "^alpha"
check "an app with no window is asked to open" "traybeta activated" "$A"
if grep -q "trayalpha activated" "$A"; then echo "FAIL the app with a window was asked to open too"; fail=1; else echo "ok   the app with a window was left to the shell"; fi
after "news slides the app out of the stack" news "ATOM tray stack 2 alone 1" "$L"
after "seen, it steps back into the stack" seen "ATOM tray stack 3 alone 0" "$L"
after "and the click on it brought its window back" seen "alpha minimized=false active=true" "$A" "^alpha"
errs=$(grep -E "status|Tray|Windows|Notify|Atom" "$L" | grep -E "Error|TypeError|ReferenceError|Cannot|Unable|not a type|is not defined|Could not set|Binding loop|Invalid property" | sort -u | head)
[ -n "$errs" ] && { echo "$errs"; fail=1; }
echo "logs: $N/out"
exit $fail
