#!/bin/sh
# Meta+Alt+T: toggle auto-tiling on the focused window's screen (atom/tiling.py has the details).
# kglobalaccel caches this shortcut's Exec line until relogin, so this path stays and only its body changes.
here=$(dirname "$(readlink -f "$0")")
mode=$(python3 "$here/rice.py" tiling toggle --screen focused) || exit 1
if [ "$mode" = tile ]; then
    notify-send -a "Tiling" -i view-grid -h string:x-canonical-private-synchronous:tiling "Auto-tiling on" "this screen tiles its windows"
else
    notify-send -a "Tiling" -i window -h string:x-canonical-private-synchronous:tiling "Auto-tiling off" "windows float freely on this screen"
fi
