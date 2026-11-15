#!/bin/sh
# Build Atom Pad's input method and set it up for this user (no root): ~/.local/bin/atom-pad-im, the .desktop
# file KWin starts it from, and KWin's input method setting (only when none is set, or it's this one already:
# another input method, fcitx or Maliit, is never replaced; the on-screen keyboard then falls back to the
# clipboard for characters the layout can't type). Needs wayland-protocols, wayland-scanner, a C compiler.
#   ~/.config/plasma-rice/pkg/atom-pad-im/build.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="$here/build"
mkdir -p "$out"
xml=/usr/share/wayland-protocols/unstable/input-method/input-method-unstable-v1.xml
wayland-scanner client-header "$xml" "$out/input-method-unstable-v1-client-protocol.h"
wayland-scanner private-code "$xml" "$out/input-method-unstable-v1-protocol.c"
# shellcheck disable=SC2046
cc -O2 -Wall -Wextra -Wno-unused-parameter -I"$out" -o "$out/atom-pad-im" "$here/atom-pad-im.c" \
    "$out/input-method-unstable-v1-protocol.c" $(pkg-config --cflags --libs wayland-client libsystemd)
bin="$HOME/.local/bin"
mkdir -p "$bin"
# replace, not overwrite in place: KWin may be running the old one
cp "$out/atom-pad-im" "$bin/.atom-pad-im.new"
mv -f "$bin/.atom-pad-im.new" "$bin/atom-pad-im"
desktop="$HOME/.local/share/applications/org.zinoxx.atom-pad-im.desktop"
mkdir -p "$(dirname "$desktop")"
cat > "$desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Atom Pad
Comment=Lets the game controller's on-screen keyboard type any character (Atom Plasma)
Exec=$bin/atom-pad-im
Icon=input-gamepad
NoDisplay=true
X-KDE-Wayland-VirtualKeyboard=true
EOF
now=$(kreadconfig6 --file kwinrc --group Wayland --key InputMethod)
if [ -z "$now" ] || [ "$now" = "$desktop" ]; then
    kwriteconfig6 --file kwinrc --group Wayland --key InputMethod "$desktop" --notify
    echo "KWin's input method: Atom Pad"
else
    echo "KWin already has an input method ($now): left as it is"
fi
echo "installed: $bin/atom-pad-im"
