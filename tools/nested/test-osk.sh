#!/bin/bash
# The game controller's on-screen keyboard on two screens, in a nested Plasma (tools/nested/run.sh,
# ATOM_NESTED_OUTPUTS=2): it comes up on the screen the daemon names (KWin's active screen, which follows
# the pointer), except while the launcher is open, when it comes up on the launcher's screen. Also checks that
# KWin's workspace.activeScreen follows the pointer (what bin/pad.py's KWin script reports). Exit 0 = all good.
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
wall=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.local/state/rice/palette.json'))).get('_wallpaper',''))")
panel() {   # panel containment $1 on screen $2, applets from $1*10
    local c=$1 s=$2 a=$(( $1 * 10 ))
    cat <<A
[Containments][$c]
activityId=
formfactor=2
immutability=1
lastScreen=$s
location=4
plugin=org.kde.panel
wallpaperplugin=org.kde.image

[Containments][$c][Applets][$((a+1))]
immutability=1
plugin=com.zinoxx.launcher

[Containments][$c][Applets][$((a+2))]
immutability=1
plugin=com.zinoxx.glimpse

[Containments][$c][Applets][$((a+3))]
immutability=1
plugin=org.kde.plasma.panelspacer

[Containments][$c][Applets][$((a+4))]
immutability=1
plugin=com.atom.test.islanda

[Containments][$c][Applets][$((a+5))]
immutability=1
plugin=com.zinoxx.shell

[Containments][$c][General]
AppletOrder=$((a+1));$((a+2));$((a+3));$((a+4));$((a+5))

A
}
desk() {    # a desktop per screen: without them Plasma puts both panels on the first screen
    printf '[Containments][%s]\nactivityId=\nformfactor=0\nimmutability=1\nlastScreen=%s\nlocation=0\nplugin=org.kde.plasma.folder\nwallpaperplugin=org.kde.image\n\n' "$1" "$2"
}
{ panel 1 0; panel 2 1; desk 3 0; desk 4 1; } > "$t/appletsrc"
for w in A; do
cat > "$t/app$w.qml" <<Q
import QtQuick
import QtQuick.Window
Window {
    visible: true; width: 600; height: 300; title: "user app $w"; color: "#203040"
    onActiveChanged: console.warn("ATOM-TEST app$w active", active)
    TextInput { anchors.fill: parent; anchors.margins: 20; focus: true; color: "white"; font.pixelSize: 30
        onTextChanged: console.warn("ATOM-TEST app$w typed", JSON.stringify(text)) }
}
Q
done
cat > "$t/inner.sh" <<I
#!/bin/bash
source "\$ATOM_NESTED/env.sh"
printf '%s\n' "${ATOM_STYLE:-simplified}" > "\$N/config/atom-test-style"
start_plasma 8
step() { mark "\$1"; echo "## \$1" >> "\$N/out/app.log"; }
post() { qdbus6 org.kde.plasmashell /Atom org.zinoxx.Atom.Post pad "\$1" >/dev/null; }
kscreen() { python3 -c "import sys; sys.path.insert(0, '\$REPO'); from atom import kwinscript; print('kwin screen', '\$1', kwinscript.run('answer(workspace.activeScreen.name + \\" \\" + typeof workspace.cursorPosChanged.connect)', answer=True))" >> "\$N/out/app.log" 2>&1; }
step "app A on the left";  \$F move 800 450 wait 200
qml6 "$t/appA.qml" >> "\$N/out/app.log" 2>&1 & a=\$!
sleep 2
\$F move 800 450 click wait 300
kscreen left
step "pointer right";      \$F move 2400 450 wait 400
kscreen right
step "show on the right";  post '{"osk":"show","screen":"Virtual-1"}'; sleep 1; shot k-right
step "hide";               post '{"osk":"hide"}'; sleep 1
step "show, no screen";    post '{"osk":"show"}'; sleep 1
step "hide again";         post '{"osk":"hide"}'; sleep 1
J0=\$(grep -o 'ATOM island launcher at [0-9]* [0-9]* on .*' "\$L" | awk '\$5 < 1600 {print \$5, \$6; exit}')
step "launcher left";      \$F move \$J0 click wait 2200
step "show over launcher"; post '{"osk":"show","screen":"Virtual-1"}'; sleep 1; shot k-launcher
step "hide over launcher"; post '{"osk":"hide"}'; sleep 1
step end
kill \$a; stop_plasma
I
chmod +x "$t/inner.sh"
N=$(ATOM_NESTED_OUTPUTS=2 "$here/run.sh" --plasma "$t/appletsrc" "$t/inner.sh" 90 | tail -1)
L="$N/out/plasmashell.log"
fail=0
check() { if grep -qE -- "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
between() { sed -n "/ATOM ## $2/,/ATOM ## $3/p" "$L" | grep -qE -- "$4" && echo "ok   $1" || { echo "FAIL $1"; fail=1; }; }
check "KWin's active screen is the pointer's (left)"   'kwin screen left Virtual-0 function' "$N/out/app.log"
check "...and follows it right"                         'kwin screen right Virtual-1 function' "$N/out/app.log"
between "it comes up on the screen the daemon names"   "show on the right" "hide" 'pad keyboard shown on Virtual-1'
between "with none named, on the active window's"      "show, no screen" "hide again" 'pad keyboard shown on Virtual-0'
between "over the launcher, on the launcher's screen"  "show over launcher" "hide over launcher" 'pad keyboard shown on Virtual-0'
errs=$(grep -E "Keyboard|Pad|Atom" "$L" | grep -E "Error|error:|TypeError|ReferenceError|Cannot|Unable|not a type|is not defined|Invalid property" | sort -u | head -20)
[ -n "$errs" ] && { echo "$errs"; fail=1; }
echo "logs: $N/out"
exit $fail
