#!/bin/bash
# The shell's full-screen surfaces and what's around them (nested Plasma, two screens, the real bars and the
# real rice_islands KWin script): the launcher clears its screen's windows and the bar's islands get out of its
# way to the other screen, as for a fullscreen game, and come back when it closes; its search-only finder
# moves nothing; the power page clears the windows on every screen and brings them back; opened from the
# launcher's power button it opens OVER the launcher (the launcher stays, its windows stay gone) and dismissing
# it goes back to the launcher, which brings them back when it closes. Exit 0 = all good.
#   tools/nested/test-cover.sh [OUT_DIR]
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
copy_to=${1:-}
state="$HOME/.local/state/rice"
for s in 0 1; do
    [ -e "$state/palette-Virtual-$s.json" ] && { echo "a palette-Virtual-$s.json is already there: not touching it" >&2; exit 2; }
done
for s in 0 1; do cp "$state/palette-HDMI-A-1.json" "$state/palette-Virtual-$s.json"; done
trap 'rm -f "$state/palette-Virtual-0.json" "$state/palette-Virtual-1.json"; [ -n "${KEEP:-}" ] && echo "kept $t" || rm -rf "$t"' EXIT
wall=$(python3 -c "import json; print(json.load(open('$state/palette-HDMI-A-1.json'))['_wallpaper'])")
t=$(mktemp -d)
source "$here/bar-applets.sh"
{ bar_applets 0 1 30 "$wall" "preferred://filemanager"; bar_applets 1 2 31 "$wall" "preferred://filemanager"; } > "$t/appletsrc"
# the test widget (Shell.debug: everything logs, nothing applies) on the first bar
printf '[Containments][1][Applets][99]\nimmutability=1\nplugin=com.atom.test.islanda\n\n' >> "$t/appletsrc"
sed -i '0,/^\[Containments\]\[1\]\[General\]/{n;s/^AppletOrder=\(.*\)/AppletOrder=\1;99/}' "$t/appletsrc"

cat > "$t/inner.sh" <<'I'
#!/bin/bash
source "$ATOM_NESTED/env.sh"
[ -n "${TRACE:-}" ] && { exec 2>>"$N/out/trace.log"; set -x; }
for p in 1 2; do printf '[PlasmaViews][Panel %s]\nfloating=0\n\n' $p; done > "$N/config/plasmashellrc"
start_plasma 12
cp "$REPO/kwin/rice_islands/contents/ui/main.qml" "$N/islands.qml"
sid=$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript "$N/islands.qml" rice_islands_test)
qdbus6 org.kde.KWin /Scripting/Script$sid org.kde.kwin.Script.run
qml6 "$REPO/tools/nested/app.qml" >> "$N/out/app.log" 2>&1 & app=$!
sleep 2
step() { mark "$1"; echo "## $1" >> "$N/out/app.log"; }
toggle() { qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu; }
step "pointer on screen 0";  $F move 800 450 click wait 300 move 910 510 wait 1200; shot s-start      # (the app has the keyboard)
step "launcher";             toggle; $F wait 2200; shot s-launcher
step "launcher closes";      toggle; $F wait 1800; shot s-closed     # (the shortcut: Esc is test-launcher's; here, on two
                                                                    #  nested screens, it's flaky with or without this change)
step "finder";               qdbus6 org.kde.krunner /App org.kde.krunner.App.display; $F wait 1800; shot s-finder
step "finder closes";        $F key 1 wait 1200
step "power";                S=$(grep -o 'ATOM island power at [0-9]* [0-9]*' "$L" | grep -v ' at 2[0-9][0-9][0-9] ' | tail -1 | awk '{print $5, $6}')
                             $F move 900 500 move ${S:-1500 1240} click wait 1800; shot s-power
step "power closes";         $F key 1 wait 1500
step "launcher again";       $F move 900 500 wait 200; toggle; $F wait 2200
P=$(grep -o 'power at [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $3, $4}')
step "its power button [$P]"; $F move 900 500 wait 100 move ${P:-1400 60} click wait 1800; shot s-handover
step "power closes again";   $F key 1 wait 1500; shot s-back
step "launcher closes again"; toggle; $F wait 1500
step end
kill $app; stop_plasma
I
chmod +x "$t/inner.sh"
N=$(WALL="$wall" ATOM_NESTED_OUTPUTS=2 ATOM_NESTED_W=1600 ATOM_NESTED_H=900 "$here/run.sh" --plasma "$t/appletsrc" "$t/inner.sh" 150 | tail -1)
L="$N/out/plasmashell.log"
fail=0
# the bar's state as plasmashell got it, between two steps
barIn() { sed -n "/ATOM ## $1/,/ATOM ## $2/p" "$L" | grep 'ATOM bar ' | tail -1; }
want() { if echo "$3" | grep -q -- "$2"; then echo "ok   $1"; else echo "FAIL $1   [$3]"; fail=1; fi; }
want "the islands start on screen 0"                  '"screen":"Virtual-0"' "$(sed -n '1,/ATOM ## launcher [0-9]/p' "$L" | grep 'ATOM bar ' | tail -1)"
want "the launcher sends them to screen 1"            '"screen":"Virtual-1"' "$(barIn 'launcher [0-9]' 'launcher closes')"
want "...as from a fullscreen game (cover)"           '"cover":\["Virtual-0"\]' "$(barIn 'launcher [0-9]' 'launcher closes')"
want "...but not as a fullscreen window to the shell" '"covered":\[\]' "$(barIn 'launcher [0-9]' 'launcher closes')"
want "they come back when it closes"                  '"screen":"Virtual-0"' "$(barIn 'launcher closes' 'finder [0-9]')"
sed -n '/ATOM ## launcher closes/,/ATOM ## finder [0-9]/p' "$L" | grep -q 'ATOM shell kind ""' && echo "ok   the shortcut closed the launcher" || { echo "FAIL the launcher didn't close"; fail=1; }
nb=$(sed -n '/ATOM ## finder [0-9]/,/ATOM ## finder closes/p' "$L" | grep -c '"screen":"Virtual-1"')
[ "$nb" = 0 ] && echo "ok   the finder leaves them where they are" || { echo "FAIL the finder moved them"; fail=1; }
cl() { sed -n "/ATOM ## $1/,/ATOM ## $2/p" "$L" | grep -c "ATOM windows cleared $3 [1-9]"; }
[ "$(cl 'launcher [0-9]' 'launcher closes' Virtual-0)" -ge 1 ] && echo "ok   the launcher cleared its screen's windows" || { echo "FAIL the launcher left the windows"; fail=1; }
[ "$(sed -n '/ATOM ## power [0-9]/,/ATOM ## power closes [0-9]/p' "$L" | grep -c 'ATOM windows cleared Virtual-[01] .* for power')" -ge 2 ] && echo "ok   the power page cleared every screen" || { echo "FAIL the power page didn't clear every screen"; fail=1; }
sed -n '/ATOM ## power closes [0-9]/,/ATOM ## launcher again/p' "$L" | grep -q 'ATOM windows restored Virtual-0 [1-9]' && echo "ok   ...and brought the windows back" || { echo "FAIL the windows didn't come back after the power page"; fail=1; }
sed -n '/ATOM ## its power button/,/ATOM ## power closes again/p' "$L" | grep -q 'ATOM windows restored' && { echo "FAIL the windows came back between the launcher and the power page"; fail=1; } || echo "ok   launcher -> power page: the windows stay gone in between"
sed -n '/ATOM ## its power button/,/ATOM ## power closes again/p' "$L" | grep -q 'ATOM stage Virtual-0 phase closing' && { echo "FAIL the launcher closed under the power page"; fail=1; } || echo "ok   the launcher stays under the power page"
sed -n '/ATOM ## power closes again/,/ATOM ## launcher closes again/p' "$L" | grep -q 'ATOM shell kind "launcher"' && echo "ok   dismissing the power page goes back to the launcher" || { echo "FAIL dismissing the power page didn't go back to the launcher"; fail=1; }
sed -n '/ATOM ## power closes again/,/ATOM ## launcher closes again/p' "$L" | grep -q 'ATOM windows restored Virtual-0 [1-9]' && { echo "FAIL the windows came back under the launcher"; fail=1; } || echo "ok   ...its windows still gone"
sed -n '/ATOM ## launcher closes again/,$p' "$L" | grep -q 'ATOM windows restored Virtual-0 [1-9]' && echo "ok   ...and back once it closes" || { echo "FAIL the windows didn't come back after the launcher"; fail=1; }
errs=$(grep -E "Shell|Windows|PowerWindow|Stage|islands" "$L" | grep -E "TypeError|ReferenceError|Cannot|Unable|is not defined" | sort -u | head)
[ -n "$errs" ] && { echo "$errs"; fail=1; }
[ -n "$copy_to" ] && mkdir -p "$copy_to" && cp "$N"/out/*.png "$L" "$copy_to"/ 2>/dev/null
echo "logs: $N/out"
exit $fail
