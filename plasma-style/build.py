#!/usr/bin/env python3
"""Generate the Plasma Styles "Rice" and "Rice-Light" (atom/style.py) into ~/.local/share/plasma/desktoptheme.
Then delete ~/.cache/plasma_theme_Rice*.kcache and restart plasmashell."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))     # an entry point one folder down
from atom import style  # noqa: E402

if __name__ == "__main__":
    style.main()
