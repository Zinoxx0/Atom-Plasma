#!/usr/bin/env python3
"""Power-on -> desktop in one look: Limine, Plymouth and the login screen (atom/boot.py has the details).

    boot.py limine [--dry-run] | plymouth [--rebuild] | login | greeter-sync | preview
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))   # (bin/..: the atom package)
from atom import boot  # noqa: E402

if __name__ == "__main__":
    boot.main(sys.argv[1:])
