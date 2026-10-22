#!/usr/bin/env python3
"""Rebuild the Plasma panels as islands (Panel Colorizer): atom/panel.py main(). Safe to re-run: it only adds
what is missing, then restarts plasmashell to set the widget order."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))     # an entry point one folder down
from atom import panel  # noqa: E402

if __name__ == "__main__":
    panel.main()
