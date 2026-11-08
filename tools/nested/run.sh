#!/bin/bash
# A nested, isolated Plasma for testing the shell without touching the user's session.
#
#   tools/nested/run.sh [--plasma APPLETSRC] INNER.sh [SECONDS]
#
# KWin runs on a virtual 1600x900 output (socket "atom-spike") inside its own D-Bus session with service
# activation OFF (an activating bus spawns a second xdg-document-portal that kills the user's). Config,
# data, cache and state live in a scratch dir, so nothing of the user's is read or written except what
# Plasma reads from $HOME (the Desktop folder, the wallpaper). With --plasma, the inner script can start
# plasmashell on that applets layout (start_plasma). The inner script gets:
#   N     scratch dir (logs and screenshots in $N/out)
#   F     fakein: pointer and keys for the nested KWin only (it refuses any other compositor)
#   L     plasmashell's log
#   start_plasma / stop_plasma (by PID: never pkill here, a name also matches the user's processes),
#   mark TEXT (a timestamped line in $L), shot NAME (screenshot to $N/out/NAME.png)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
applets=""
if [ "${1:-}" = "--plasma" ]; then applets=$(realpath "$2"); shift 2; fi
inner=$(realpath "$1"); secs=${2:-90}

N=${ATOM_NESTED_DIR:-${XDG_RUNTIME_DIR:-/tmp}/atom-nested}
rm -rf "$N"; mkdir -p "$N"/{config,data/plasma/plasmoids,cache,state,out,bin}
sed '/standard_session_servicedirs/d; /<include/d' /usr/share/dbus-1/session.conf > "$N/session.conf"

# fakein, built once per source change
fake=${XDG_CACHE_HOME:-$HOME/.cache}/rice/nested
mkdir -p "$fake"
if [ ! -x "$fake/fakein" ] || [ "$here/fakein.c" -nt "$fake/fakein" ] || [ "$here/fake-input.xml" -nt "$fake/fakein" ]; then
    wayland-scanner client-header "$here/fake-input.xml" "$fake/fake-input.h"
    wayland-scanner private-code "$here/fake-input.xml" "$fake/fake-input.c"
    gcc -O1 -I"$fake" -o "$fake/fakein" "$here/fakein.c" "$fake/fake-input.c" $(pkg-config --cflags --libs wayland-client)
fi

# the rice's widgets and the test ones, by link
for p in "$repo"/plasmoids/* "$here"/plasmoids/*; do ln -s "$p" "$N/data/plasma/plasmoids/$(basename "$p")"; done
[ -n "$applets" ] && cp "$applets" "$N/config/plasma-org.kde.plasma.desktop-appletsrc"

cat > "$N/env.sh" <<EOF
export N="$N" F="$fake/fakein" L="$N/out/plasmashell.log" REPO="$repo"
export QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=wayland XDG_CURRENT_DESKTOP=KDE KDE_FULL_SESSION=true
export KDE_SESSION_VERSION=6 QML_XHR_ALLOW_FILE_READ=1
export QML_IMPORT_PATH="$repo/qml:\$HOME/.local/lib/qt6/qml"
# by PID only: a name (pkill -x plasmashell) also matches the USER's processes outside the nested session
start_plasma() { /usr/lib/kactivitymanagerd & KAMD_PID=\$!; sleep 1; plasmashell --no-respawn >> "\$L" 2>&1 & PLASMA_PID=\$!; sleep "\${1:-7}"; }
stop_plasma() { kill \$PLASMA_PID \$KAMD_PID 2>/dev/null; sleep 1; }
pkill() { echo "nested tests: kill by PID (pkill would reach the user's session)" >&2; return 1; }
killall() { pkill; }
mark() { echo "qml: ATOM ## \$* \$(( \$(date +%s%3N) % 100000 ))" >> "\$L"; }
shot() { spectacle -b -n -f -o "\$N/out/\$1.png" >/dev/null 2>&1; }
EOF
: > "$N/out/plasmashell.log"

unset DISPLAY XAUTHORITY
export ATOM_NESTED="$N"
timeout "$secs" dbus-run-session --config-file="$N/session.conf" -- \
  env XDG_CONFIG_HOME="$N/config" XDG_DATA_HOME="$N/data" XDG_CACHE_HOME="$N/cache" XDG_STATE_HOME="$N/state" \
      QT_FORCE_STDERR_LOGGING=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
  kwin_wayland --virtual --no-lockscreen --no-global-shortcuts --socket atom-spike \
      --width 1600 --height 900 --exit-with-session "$inner" > "$N/out/kwin.log" 2>&1 || true
echo "$N"
