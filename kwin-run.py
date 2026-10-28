#!/usr/bin/env python3
"""Run a one-shot KWin script, and with --answer, wait for what it sends back (atom/kwinscript.py).

    kwin-run.py [--answer] [--timeout SECONDS] < script.js

With --answer the script can call `answer(value)` once: the value is printed (exit 1 with nothing printed if
no answer came within the timeout, 2 s by default). Used by Glimpse's glimpse-kwin.sh (moving a window).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from atom import kwinscript  # noqa: E402


def main(args):
    want = "--answer" in args
    timeout = float(args[args.index("--timeout") + 1]) if "--timeout" in args else 2.0
    out = kwinscript.run(sys.stdin.read(), answer=want, timeout=timeout)
    if want:
        if not out:
            sys.exit(1)
        print(out)


if __name__ == "__main__":
    main(sys.argv[1:])
