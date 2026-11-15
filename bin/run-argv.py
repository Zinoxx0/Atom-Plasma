#!/usr/bin/env python3
"""Run the command a widget left in FILE: a JSON list, the program and its arguments (no shell).

    run-argv.py FILE

RiceShell.exec() writes the file (in $XDG_RUNTIME_DIR, from a short rotation of names) and runs this
under a fixed command name. Commands whose arguments change every time (a colour, a wallpaper, a
window id) would otherwise each be a new name for Plasma's executable engine, and every long-lived
DataSource in plasmashell (Panel Colorizer keeps one) grows by one property per name it sees.
"""
import json
import os
import sys

if __name__ == "__main__":
    try:
        argv = json.loads(open(sys.argv[1]).read())
    except (IndexError, OSError, ValueError) as e:
        sys.exit(f"run-argv: {e}")
    if not (isinstance(argv, list) and argv and all(isinstance(a, str) for a in argv)):
        sys.exit("run-argv: not a command (a JSON list of strings)")
    os.execvp(argv[0], argv)
