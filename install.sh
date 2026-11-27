#!/bin/sh
# Atom Plasma's installer:
#   curl -fsSL https://raw.githubusercontent.com/ViviaTech/Atom-Plasma/main/install.sh | sh
# Clones Atom Plasma into ~/.config/plasma-rice, then hands over to its updater (rice.py update fresh): it checks
# this system (KDE Plasma on Wayland, the Plasma version), installs what's missing (one password prompt; AUR
# packages in a terminal you watch), picks the newest release on your channel and puts every piece in place.
# ATOM_CHANNEL=beta|alpha for newer builds (stable by default). Run again any time: it never overwrites a copy.
set -eu
repo="${ATOM_REPO:-https://github.com/ViviaTech/Atom-Plasma}"
dest="$HOME/.config/plasma-rice"

say() { printf '%s\n' "$*"; }
need() {
    command -v "$1" >/dev/null 2>&1 && return 0
    if command -v pacman >/dev/null 2>&1; then
        say "Atom Plasma needs $2 first:  sudo pacman -S --needed $2"
    else
        say "Atom Plasma needs $2 first (install it with your distro's package manager)."
    fi
    exit 1
}
need git git
need python3 python

if ! command -v plasmashell >/dev/null 2>&1; then
    say "KDE Plasma isn't installed here: Atom Plasma is a Plasma 6 desktop (Wayland session)."
    exit 1
fi
if [ -d "$dest/.git" ]; then
    say "Atom Plasma is already in $dest: update it from Atom Manager (the gear in the launcher)"
    say "or with: $dest/rice.py update check && $dest/rice.py update start"
    exit 0
fi
if [ -e "$dest" ]; then
    say "$dest exists and isn't an Atom Plasma copy: move it away first."
    exit 1
fi
say "Getting Atom Plasma from $repo"
git clone --quiet "$repo" "$dest"
exec python3 "$dest/rice.py" update fresh
