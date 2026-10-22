#!/usr/bin/env python3
"""App themes that follow the wallpaper palette, and one-shot app settings (atom/apps.py has the details).

    apps.py                   theme the apps from the current palette (rice.py does this on every change)
    apps.py install-vscode    build the VS Code theme extension and install it
    apps.py setup             one-shot, not palette-driven: Dolphin's toolbar and view, Darkly's glass
    apps.py dolphin-refresh   take Dolphin's own toolbar file again (after a Dolphin update)
    apps.py konsole-chrome    Konsole without menu bar or toolbars, tabs as pills (cheap; for login)
"""
import sys

from atom import apps

if __name__ == "__main__":
    apps.main(sys.argv[1:])
