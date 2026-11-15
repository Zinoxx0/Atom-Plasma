#!/usr/bin/env python3
"""Regenerate qml/Rice/Tokens.qml from the design tokens in atom/tokens.py (rice.py does it on every run too)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))   # (bin/..: the atom package)
from atom import tokens  # noqa: E402

if __name__ == "__main__":
    print(tokens.write())
