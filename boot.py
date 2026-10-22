#!/usr/bin/env python3
"""Power-on -> desktop in one look: Limine, Plymouth and the login screen (atom/boot.py has the details).

    boot.py limine [--dry-run] | plymouth [--rebuild] | login | greeter-sync | preview
"""
import sys

from atom import boot

if __name__ == "__main__":
    boot.main(sys.argv[1:])
