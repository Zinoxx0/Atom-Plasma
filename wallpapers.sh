#!/bin/sh
# Meta+Shift+W (net.local.rice-wallpapers.desktop): the launcher, opened on its wallpapers (on the
# screen Plasma opens it on). The launcher reads this note when it opens, then deletes it.
mkdir -p "$HOME/.local/state/rice"
echo walls > "$HOME/.local/state/rice/launcher-open"
qdbus6 org.kde.kglobalaccel /component/plasmashell org.kde.kglobalaccel.Component.invokeShortcut "activate application launcher"
