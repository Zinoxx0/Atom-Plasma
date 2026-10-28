"""`rice.py doctor`: is the rice whole on this machine? What it has (atom/caps.py), the displays
(atom/displays.py), and the pieces installed outside the repo: the plasmoids, the look-and-feel, the KWin
effects, the user units, plasmashell's environment, one Colorizer per bar, the saved state's version.
Each check is one line: ok, or what's wrong and what to run."""
import json
import os
import subprocess

from . import caps, displays, migrate, panel, util
from .util import HOME, ROOT

PLASMOIDS = HOME / ".local/share/plasma/plasmoids"
LNF = HOME / ".local/share/plasma/look-and-feel"
EFFECTS = HOME / ".local/share/kwin/effects"
UNITS = HOME / ".config/systemd/user"
DROPIN = UNITS / "plasma-plasmashell.service.d/rice.conf"


def _linked(link, target):
    try:
        return link.resolve(strict=True) == target.resolve(strict=True)
    except OSError:
        return False


def checks():
    """[(ok, what, fix)]"""
    out = []
    for d in sorted(p for p in (ROOT / "plasmoids").iterdir() if p.is_dir()):
        out.append((_linked(PLASMOIDS / d.name, d), f"plasmoid {d.name}", f"ln -sfn {d} {PLASMOIDS / d.name}"))
    for d in sorted(p for p in (ROOT / "lnf").iterdir() if p.is_dir()):
        out.append((_linked(LNF / d.name, d), f"look-and-feel {d.name}", f"ln -sfn {d} {LNF / d.name}"))
    for d in sorted(p for p in (ROOT / "kwin").iterdir() if p.is_dir()):
        out.append((_linked(EFFECTS / d.name, d), f"KWin effect {d.name}", "rice.py setup"))
    for f in sorted((ROOT / "systemd").glob("*")):
        if f.suffix not in (".service", ".timer"):
            continue
        linked = _linked(UNITS / f.name, f)
        wanted = f.name not in ("atom-plasma-rgb.service", "atom-plasma-update-check.service",
                                "atom-plasma-update-tidy.service")       # started by udev / their timers
        active = True
        if wanted:
            r = util.run("systemctl", "--user", "is-active", f.name, quiet=True)
            active = r is not None and r.stdout.strip() == "active"
        out.append((linked and active, f"unit {f.name}" + ("" if active else " (not running)"),
                    f"ln -sf {f} {UNITS / f.name} && systemctl --user enable --now {f.name}"))
    env = DROPIN.read_text() if DROPIN.exists() else ""
    out.append(("QML_XHR_ALLOW_FILE_READ=1" in env and "QML_XHR_ALLOW_FILE_WRITE=1" in env,
                "plasmashell may read/write the rice's files (QML_XHR_ALLOW_FILE_*)",
                f"write {DROPIN} (see README), then relog"))
    try:
        bars = panel.panels()
        services = util.run("qdbus6", quiet=True).stdout
        missing = [b["panel"] for b in bars if f"{panel.COLORIZER}.c{b['panel']}.w{b['colorizer']}" not in services]
        out.append((not missing, f"Colorizer on every bar ({len(bars)} bars)"
                    + (f": not running on {missing}" if missing else ""), "systemctl --user restart plasma-plasmashell"))
    except (subprocess.CalledProcessError, ValueError, AttributeError):
        out.append((False, "plasmashell answers scripting", "is plasmashell running?"))
    out.append((migrate.version() >= migrate.VERSION, f"saved state version {migrate.version()}", "rice.py screens"))
    return out


def report():
    cfg = util.settings()
    ds = displays.probe()
    lines = ["== machine", caps.report(cfg), "", "== displays", displays.report(ds, cfg), "", "== install"]
    bad = 0
    for ok, what, fix in checks():
        lines.append(("ok   " if ok else "FIX  ") + what + ("" if ok else f"\n       -> {fix}"))
        bad += not ok
    lines.append("" if not bad else f"\n{bad} thing(s) to fix")
    return "\n".join(lines), bad
