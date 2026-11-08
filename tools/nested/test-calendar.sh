#!/bin/bash
# The clock island and its calendar panel (nested Plasma): it opens from the clock, shows the month and
# the day's agenda (a stand-in agenda with events today and tomorrow, put back afterwards), the arrows
# move the day, Page Down the month, Esc closes it and the keyboard goes back. Exit 0 = all good.
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d)
real="$HOME/.cache/rice/calendar.json"
[ -f "$real" ] && cp "$real" "$t/calendar.json.real"
trap 'if [ -f "$t/calendar.json.real" ]; then mv -f "$t/calendar.json.real" "$real"; else rm -f "$real"; fi; rm -rf "$t"' EXIT
python3 - "$real" <<'PY'
import datetime as dt, json, sys, time
now = dt.datetime.now().astimezone()
def at(days, h, m):
    return (now + dt.timedelta(days=days)).replace(hour=h, minute=m, second=0, microsecond=0).isoformat(timespec="minutes")
soon = (now + dt.timedelta(minutes=20)).replace(second=0, microsecond=0)
events = [
    {"title": "Standup with the ViVia team", "start": soon.isoformat(timespec="minutes"),
     "end": (soon + dt.timedelta(minutes=30)).isoformat(timespec="minutes"), "allDay": False, "location": "Discord", "calendar": "Work"},
    {"title": "42 study group", "start": at(0, 18, 0), "end": at(0, 20, 0), "allDay": False, "location": "42 Lisboa", "calendar": "Personal"},
    {"title": "Gym", "start": at(1, 9, 30), "end": at(1, 11, 0), "allDay": False, "location": "", "calendar": "Personal"},
    {"title": "ViVia offsite", "start": (now + dt.timedelta(days=3)).date().isoformat(), "end": (now + dt.timedelta(days=4)).date().isoformat(), "allDay": True, "location": "", "calendar": "Work"},
]
events.sort(key=lambda e: e["start"])
hol = {"2026-12-01": "Restoration of Independence", "2026-12-08": "Immaculate Conception", "2026-12-25": "Christmas Day", "2026-11-01": "All Saints' Day"}
json.dump({"updated": int(time.time()), "holidays": hol, "events": events, "source": "ical", "error": ""}, open(sys.argv[1], "w"))
PY
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
plugin=com.zinoxx.clock

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
C=$(grep -o 'ATOM island calendar at [0-9]* [0-9]*' "$L" | tail -1 | awk '{print $5, $6}')
[ -n "$C" ] || C="1540 877"
step() { mark "$1"; echo "## $1" >> "$N/out/app.log"; }
step "focus app";      $F move 800 450 click wait 300 type "a" wait 300
step "open calendar";  $F move $C click wait 150; shot c-grow; $F wait 900; shot c-open
step "next day";       $F key 106 wait 500; shot c-tomorrow
step "next month";     $F key 109 wait 700; shot c-month
step "esc";            $F key 1 wait 700
step "type b";         $F type "b" wait 300
step end
kill $app; stop_plasma
I
chmod +x "$t/inner.sh"
N=$("$here/run.sh" --plasma "$t/appletsrc" "$t/inner.sh" 90 | tail -1)
L="$N/out/plasmashell.log"
fail=0
check() { if grep -q -- "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
check "the clock opened the calendar"      'shell kind "calendar"' "$L"
check "keyboard back to the app after Esc" 'app typed "ab"' "$N/out/app.log"
errs=$(grep -E "Calendar|clock|Atom" "$L" | grep -E "Error|TypeError|ReferenceError|Cannot|Unable|not a type|is not defined|Could not set|Binding loop|Invalid property|no panel for" | sort -u | head)
[ -n "$errs" ] && { echo "$errs"; fail=1; }
echo "logs: $N/out"
exit $fail
