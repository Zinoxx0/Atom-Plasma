#!/bin/bash
# The status island's app icons (nested Plasma; pretend apps from trayapp.py, a bare watcher from
# sniwatcher.py since kded isn't running there). The quiet icons rest in one stack, an island whose click
# opens their panel on the sheet; a row's click brings its app's minimized window back (and closes the
# panel), and an app with no window is asked to open; a notification slides its app out of the stack, a
# click on it there brings its window back, and seeing it (the window gets the focus) puts it back in the
# stack. Exit 0 = all good.
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
row() { grep -o "ATOM apps row $1 [0-9]* [0-9]*" "$L" | tail -1 | awk '{print $5, $6}'; }
minimize() { kw "for (const w of workspace.windowList()) if (w.resourceClass == 'trayalpha') w.minimized = true" >/dev/null; sleep 0.5; alpha; }

step "stacked";  shot t-stacked
step "minimize"; minimize
I=$(grep -o 'ATOM island apps at [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $5, $6}')
step "open";     $F move ${I:-1400 880} wait 300 click wait 1300; shot t-panel
R=$(row trayalpha)
step "pick";     $F move ${R:-800 700} wait 300 click wait 1000; alpha
step "open2";    $F move ${I:-1400 880} wait 300 click wait 1300
R=$(row traybeta)
step "no window"; $F move ${R:-800 700} wait 300 click wait 1000
step "news";     minimize; gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
                     --method org.freedesktop.Notifications.Notify trayalpha 0 "" "Hello" "something new" "[]" "{}" 4000 >/dev/null
                 $F wait 1500; shot t-news
P=$(at trayalpha alone)
step "seen";     $F move ${P:-1400 880} wait 300 click wait 1500; alpha; shot t-seen
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
check "the three quiet icons rest in one stack" "ATOM tray stack 3 alone 0" "$L"
after "the stack's click opens its panel" open 'shell kind "apps"' "$L" "ATOM ##"
after "the panel lists the three" open "ATOM apps row traygamma" "$L" "ATOM ##"
after "a row brings the minimized window back" pick "alpha minimized=false active=true" "$A" "^alpha"
after "and the panel closes" pick 'shell kind ""' "$L" "ATOM ##"
after "an app with no window is asked to open" "no window" "traybeta activated" "$A" "^##"
if grep -q "trayalpha activated" "$A"; then echo "FAIL the app with a window was asked to open too"; fail=1; else echo "ok   the app with a window was left to the shell"; fi
after "news slides the app out of the stack" news "ATOM tray stack 2 alone 1" "$L" "ATOM ##"
after "its own icon brings its window back" seen "alpha minimized=false active=true" "$A" "^alpha"
after "seen, it steps back into the stack" seen "ATOM tray stack 3 alone 0" "$L" "ATOM ##"
errs=$(grep -E "status|Tray|Windows|Notify|Atom" "$L" | grep -E "Error|TypeError|ReferenceError|Cannot|Unable|not a type|is not defined|Could not set|Binding loop|Invalid property" | sort -u | head)
[ -n "$errs" ] && { echo "$errs"; fail=1; }
echo "logs: $N/out"
exit $fail
