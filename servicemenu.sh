#!/bin/sh
# servicemenu.sh here|all|add FILE...   Dolphin's "Rice" actions on images
# (~/.local/share/kio/servicemenus/rice.desktop)
#   here  set it as this screen's wallpaper and re-theme from it (the screen Dolphin is on)
#   all   the same on every screen
#   add   copy the images into ~/Pictures/Wallpapers, for the wallpaper picker
set -eu
cmd=${1:-}; shift || true
rice="$HOME/.config/plasma-rice/rice.py"
case "$cmd" in
    here) exec "$rice" "$1" --screen focused ;;
    all)  exec "$rice" "$1" --screen all ;;
    add)
        dir="$HOME/Pictures/Wallpapers"
        mkdir -p "$dir"
        n=0
        for f; do
            [ -e "$dir/$(basename "$f")" ] && continue
            cp -- "$f" "$dir/" && n=$((n + 1))
        done
        notify-send -a Theme -i preferences-desktop-wallpaper "Wallpapers" "Added $n to your collection" ;;
    *) echo "usage: $0 here|all|add FILE..." >&2; exit 2 ;;
esac
