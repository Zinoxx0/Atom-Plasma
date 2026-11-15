#!/usr/bin/env python3
"""Where the desk's clock and music card sit on a wallpaper (atom/layout.py).

    layout.py preview OUT.png IMG:WxH [IMG:WxH ...]     overlay sheet (cost heat + boxes)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))   # (bin/..: the atom package)
from atom import layout  # noqa: E402

if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "preview":
        layout.preview(sys.argv[2], sys.argv[3:])
    else:
        sys.exit(__doc__)
