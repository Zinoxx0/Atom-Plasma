#!/bin/bash
# Notifications (nested Plasma): plasmashell owns the notification server without the stock tray, a
# message grows a card out of the status island, more from the same chat merge into it (+n), another app
# gets its own card, they leave on their own, and the app keeps the keyboard. Exit 0 = all good.
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
step() { mark "$1"; echo "## $1" >> "$N/out/app.log"; }
step "focus app";      $F move 800 450 click wait 300 type "a" wait 300
echo "server: $(busctl --user status org.freedesktop.Notifications 2>&1 | grep -E '^Comm=')" >> "$N/out/app.log"
step "message";        notify-send -a ZapZap -i com.rtosta.zapzap "Ana" "are you coming tonight?"; $F wait 180; shot n-grow; $F wait 900; shot n-one
step "same chat";      notify-send -a ZapZap -i com.rtosta.zapzap "Ana" "the others are already here"; sleep 0.3; notify-send -a ZapZap -i com.rtosta.zapzap "Ana" "🎉"; $F wait 900; shot n-merged
step "other app";      notify-send -a Discord -i discord "#general · Nuno" "pushed the new build, check it out"; $F wait 900; shot n-two
step "type b";         $F type "b" wait 300
step "wait";           sleep 8; shot n-gone
B=$(grep -o 'ATOM island control at [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $5, $6}')
step "open control";   $F move $B click wait 1300; shot n-history
step "esc";            $F key 1 wait 600
step end
step end
kill $app; stop_plasma
I
chmod +x "$t/inner.sh"
N=$("$here/run.sh" --plasma "$t/appletsrc" "$t/inner.sh" 90 | tail -1)
L="$N/out/plasmashell.log"
fail=0
check() { if grep -q -- "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
check "plasmashell owns the notification server" 'server: Comm=plasmashell' "$N/out/app.log"
check "the app kept the keyboard" 'app typed "ab"' "$N/out/app.log"
errs=$(grep -E "Toasts|Notify|status|Atom" "$L" | grep -E "Error|TypeError|ReferenceError|Cannot|Unable|not a type|is not defined|Could not set|Binding loop|Invalid property|no panel for" | sort -u | head)
[ -n "$errs" ] && { echo "$errs"; fail=1; }
echo "logs: $N/out"
exit $fail
