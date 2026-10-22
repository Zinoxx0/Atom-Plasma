#!/usr/bin/env python3
"""Regenerate qml/Rice/Tokens.qml from the design tokens in atom/tokens.py (rice.py does it on every run too)."""
from atom import tokens

if __name__ == "__main__":
    print(tokens.write())
