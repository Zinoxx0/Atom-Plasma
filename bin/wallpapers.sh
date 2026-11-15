#!/bin/sh
# Meta+Shift+W (net.local.rice-wallpapers.desktop): the launcher, opened on its Theme page (on the
# screen Plasma opens it on), at a tab: walls (default), colours or lights. The launcher reads this
# note when it opens, then deletes it.
mkdir -p "$HOME/.local/state/rice"
echo "${1:-walls}" > "$HOME/.local/state/rice/launcher-open"
qdbus6 org.kde.kglobalaccel /component/plasmashell org.kde.kglobalaccel.Component.invokeShortcut "activate application launcher"
