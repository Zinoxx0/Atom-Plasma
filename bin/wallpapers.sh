#!/bin/sh
# Meta+Shift+W (net.local.rice-wallpapers.desktop): the launcher, opened on its Theme page (on the
# screen Plasma opens it on), at a tab: walls (default), colours or lights. Posted over D-Bus
# (Atom.Native Bus) so normal launcher opens never fork a shell to check a note file.
tab="${1:-walls}"
qdbus6 org.kde.plasmashell /Atom org.zinoxx.Atom.Post themeOpen "{\"tab\":\"$tab\",\"at\":$(date +%s)}" >/dev/null 2>&1 || true
qdbus6 org.kde.kglobalaccel /component/plasmashell org.kde.kglobalaccel.Component.invokeShortcut "activate application launcher"
