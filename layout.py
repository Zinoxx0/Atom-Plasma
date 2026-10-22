#!/usr/bin/env python3
"""Where the desk's clock and music card sit on a wallpaper (atom/layout.py).

    layout.py preview OUT.png IMG:WxH [IMG:WxH ...]     overlay sheet (cost heat + boxes)
"""
import sys

from atom import layout

if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "preview":
        layout.preview(sys.argv[2], sys.argv[3:])
    else:
        sys.exit(__doc__)
