#!/bin/sh
# Build Atom.Native and install it for this user (no root): ~/.local/lib/qt6/qml/Atom/Native.
# Rebuild after a Qt or KDE Frameworks upgrade, then restart plasmashell:
#   ~/.config/plasma-rice/pkg/atom-native/build.sh && systemctl --user restart plasma-plasmashell
set -eu
here=$(cd "$(dirname "$0")" && pwd)
dest="${ATOM_QML_DEST:-$HOME/.local/lib/qt6/qml}/Atom/Native"
cmake -S "$here" -B "$here/build" -G Ninja -Wno-dev -DCMAKE_BUILD_TYPE=Release -DCMAKE_EXPORT_COMPILE_COMMANDS=ON >/dev/null
cmake --build "$here/build"
mkdir -p "$dest"
# replace, not overwrite in place: a running plasmashell has the old .so mapped
for f in qmldir atomnative.qmltypes libatomnative.so; do
    [ -e "$here/build/qml/Atom/Native/$f" ] || continue
    cp "$here/build/qml/Atom/Native/$f" "$dest/.$f.new"
    mv -f "$dest/.$f.new" "$dest/$f"
done
echo "installed: $dest"
