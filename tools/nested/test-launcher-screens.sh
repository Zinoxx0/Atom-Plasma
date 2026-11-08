#!/bin/bash
# The launcher on two screens, in a nested Plasma (tools/nested/run.sh, ATOM_NESTED_OUTPUTS=2): opening it
# clears only its own screen; moving the pointer to the other screen takes it there (the query comes
# along, the first screen's window comes back); Esc gives the keyboard back to the window that had it;
# the bar is covered while open; Glimpse's top band opens over it and a window picked there closes it.
# Screenshots in the logs folder. Exit 0 = all good.
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
for w in A B; do
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
start_plasma 8
# the desktops show the wallpaper the rice palette names, so the bar's cover can be checked against it
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "desktops().forEach(d => { d.currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General']; d.writeConfig('Image', 'file://$wall') })" >/dev/null
sleep 1
step() { mark "\$1"; echo "## \$1" >> "\$N/out/app.log"; }
step "app A on the left";  \$F move 800 450 wait 200
qml6 "$t/appA.qml" >> "\$N/out/app.log" 2>&1 & a=\$!
sleep 2
step "app B on the right"; \$F move 2400 450 wait 200
qml6 "$t/appB.qml" >> "\$N/out/app.log" 2>&1 & b=\$!
sleep 2
shot s-apps
J0=\$(grep -o 'ATOM island launcher at [0-9]* [0-9]* on .*' "\$L" | awk '\$5 < 1600 {print \$5, \$6; exit}')
echo "jewel 0: \$J0" >> "\$N/out/app.log"
step "focus A";            \$F move 800 450 click wait 300 type "a" wait 300
step "jewel on the left";  \$F move \$J0 click wait 2200; shot s-open-left
step "type";               \$F type "fire" wait 1200
step "to the right";       \$F move 2400 450 wait 400 move 2410 460 wait 1800
step "type there";         \$F type "fox" wait 1200; shot s-moved-right
step "back to the left";   \$F move 800 450 wait 400 move 810 460 wait 1800; shot s-moved-left
step "esc clears";         \$F key 1 wait 600
step "esc closes";         \$F key 1 wait 1200; shot s-closed
step "type z (A?)";        \$F type "z" wait 300
step "jewel again";        \$F move \$J0 click wait 2200
step "top edge";           \$F move 700 30 wait 300 move 700 0 wait 900; shot s-band
python3 -c "import sys; sys.path.insert(0, '\$REPO'); from atom import kwinscript; print('stacking', kwinscript.run('answer(workspace.stackingOrder.map(w => [w.resourceClass, w.caption, w.layer, w.output ? w.output.name : \\"?\\", Math.round(w.y), Math.round(w.height)].join(\\":\\")).join(\\" | \\"))', answer=True))" >> "\$N/out/app.log" 2>&1
step "click band space";   \$F move 700 12 wait 300 click wait 800; shot s-band-space
step "click the app";      \$F move 45 20 wait 300 click wait 1500; shot s-picked
step end
kill \$a \$b; stop_plasma
I
chmod +x "$t/inner.sh"
N=$(ATOM_NESTED_OUTPUTS=2 "$here/run.sh" --plasma "$t/appletsrc" "$t/inner.sh" 150 | tail -1)
L="$N/out/plasmashell.log"
fail=0
check() { if grep -q -- "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
check "opening cleared only the left screen"   'windows cleared Virtual-0 1' "$L"
check "the launcher followed the pointer right" 'pointer moved from Virtual-0 to Virtual-1 (following)' "$L"
check "the left screen got its window back"     'windows restored Virtual-0 1' "$L"
check "the right screen was cleared on arrival" 'windows cleared Virtual-1 1' "$L"
check "and followed it back"                    'pointer moved from Virtual-1 to Virtual-0 (following)' "$L"
check "Esc gave the keyboard back to app A"     'appA typed "az"' "$N/out/app.log"
if grep -q 'appB typed' "$N/out/app.log" || grep -q 'appA typed "af' "$N/out/app.log"; then echo "FAIL typing after the move reached an app"; fail=1
else echo "ok   typing after the move went to the launcher"; fi
band=$(awk '/## click band space/,/## click the app/' "$L")
if echo "$band" | grep -q 'shell kind ""'; then echo "FAIL the band's empty space closed the launcher (the band is under it)"; fail=1
else echo "ok   the opened band is above the launcher"; fi
picked=$(awk '/## click the app/,/## end/' "$L")
if echo "$picked" | grep -q 'shell kind ""' && awk '/## click the app/,/## end/' "$N/out/app.log" | grep -q 'appA active true'
then echo "ok   picking the app in the band closed the launcher and brought it up"; else echo "FAIL picking an app in the band"; fail=1; fi
errs=$(grep -E "launcher|Stage|Atom|glimpse|Glimpse|Shelf" "$L" | grep -E "Error|error:|TypeError|ReferenceError|Cannot|Unable|not a type|is not defined|Invalid property|no panel for" | sort -u | head -20)
[ -n "$errs" ] && { echo "$errs"; fail=1; }
echo "logs: $N/out"
exit $fail
