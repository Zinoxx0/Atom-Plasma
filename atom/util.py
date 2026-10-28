"""What every part of Atom Plasma shares: its folders, settings.json, writing files safely, running
commands (failures go to the log), the log itself, template filling and finding font files."""
import fcntl
import functools
import json
import logging
import logging.handlers
import os
import re
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
ROOT = Path(__file__).resolve().parent.parent        # ~/.config/plasma-rice
STATE = HOME / ".local/state/rice"
CACHE = HOME / ".cache/rice"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")      # cleared at logout/reboot
LOG_FILE = STATE / "rice.log"


# ---------------------------------------------------------------- settings
def settings():
    """~/.config/plasma-rice/settings.json ({} if it's missing or broken)."""
    return load_json(ROOT / "settings.json", {})


def wallpaper_dir(cfg=None):
    """The wallpaper collection: settings wallpaper_dir, else Pictures/Wallpapers (XDG Pictures folder)."""
    d = (cfg if cfg is not None else settings()).get("wallpaper_dir")
    return Path(d).expanduser() if d else _pictures() / "Wallpapers"


@functools.cache
def _pictures():
    try:
        out = subprocess.run(["xdg-user-dir", "PICTURES"], capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        out = ""
    return Path(out) if out and out != str(HOME) else HOME / "Pictures"


# ---------------------------------------------------------------- files
def load_json(path, default=None):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return default


def write_if_changed(path, text):
    """Write `text` atomically (temp file, then rename), only if the file differs. True if it changed."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        if path.read_text() == text:
            return False
    except (OSError, ValueError):
        pass
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text)
    tmp.replace(path)
    return True


def save_json(path, data, indent=2):
    return write_if_changed(path, json.dumps(data, indent=indent, ensure_ascii=False) + "\n")


_locks = {}


def hold_lock(name="rice"):
    """One writer at a time for `name` (~/.local/state/rice/<name>.lock), held until the process ends.
    Taken once per process: a second flock on a new open of the same file would wait for the first."""
    if name not in _locks:
        STATE.mkdir(parents=True, exist_ok=True)
        f = open(STATE / f"{name}.lock", "w")
        fcntl.flock(f, fcntl.LOCK_EX)
        _locks[name] = f


# ---------------------------------------------------------------- log
@functools.cache
def _logger():
    log = logging.getLogger("atom")
    log.setLevel(logging.INFO)
    who = Path(sys.argv[0]).name if sys.argv and sys.argv[0] else "python"
    try:
        STATE.mkdir(parents=True, exist_ok=True)
        fh = logging.handlers.RotatingFileHandler(LOG_FILE, maxBytes=256 * 1024, backupCount=1)
        fh.setFormatter(logging.Formatter(f"%(asctime)s {who}[{os.getpid()}] %(levelname)s %(message)s", "%Y-%m-%d %H:%M:%S"))
        log.addHandler(fh)
    except OSError:
        pass
    err = logging.StreamHandler(sys.stderr)         # warnings also on stderr: the Theme page shows the last line
    err.setLevel(logging.WARNING)
    err.setFormatter(logging.Formatter(f"{who}: %(message)s"))
    log.addHandler(err)
    return log


def log(msg, *args):
    _logger().info(msg, *args)


def warn(msg, *args):
    _logger().warning(msg, *args)


def run(*cmd, quiet=False, timeout=60):
    """Run a command, capture its output. A failure is logged (unless `quiet`: an answer that may be
    empty on purpose) and never raised: the caller looks at returncode when it matters."""
    try:
        r = subprocess.run(cmd, check=False, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError) as e:
        if not quiet:
            warn("%s: %s", " ".join(map(str, cmd))[:200], e)
        return subprocess.CompletedProcess(cmd, 127, "", str(e))
    if r.returncode and not quiet:
        warn("%s exited %s: %s", " ".join(map(str, cmd))[:200], r.returncode, (r.stderr or r.stdout).strip()[-400:])
    return r


def run_bytes(cmd, data, timeout=60):
    """A command fed `data` on stdin; its stdout as bytes (b"" if it can't run)."""
    try:
        return subprocess.run(cmd, input=data, capture_output=True, timeout=timeout).stdout
    except (OSError, subprocess.SubprocessError):
        return b""


def notify(title, body, icon="preferences-desktop-theme", tag="wallpaper"):
    run("notify-send", "-a", "Theme", "-i", str(icon), "-h", f"string:x-canonical-private-synchronous:{tag}", title, body)


# ---------------------------------------------------------------- templates
TEMPLATE = re.compile(r"\{\{(\w+)(\.rgb)?\}\}")


def fill(text, values, what="template"):
    """{{name}} -> the value (a palette colour as #rrggbb), {{name.rgb}} -> the colour as r;g;b (for ANSI
    escape codes). Names it doesn't know stay as they are, and are logged unless on a comment line
    (# or //), where a template may show the syntax itself."""
    def sub(m):
        v = values.get(m.group(1))
        if v is None:
            return m.group(0)
        if m.group(2):
            from . import palette
            return palette.rgb_csv(v).replace(",", ";")
        return str(v)
    out = TEMPLATE.sub(sub, text)
    left = {m.group(0) for line in out.splitlines() if not line.lstrip().startswith(("#", "//"))
            for m in TEMPLATE.finditer(line)}
    if left:
        warn("%s: unknown placeholders %s", what, ", ".join(sorted(left)))
    return out


# ---------------------------------------------------------------- fonts
@functools.cache
def font(pattern):
    """(file, face index) fontconfig picks for `pattern` (e.g. "Inter:style=Medium"; Inter is one .ttc of
    many faces), so a font package that moves its files doesn't break anything. (None, 0) if none."""
    r = run("fc-match", "-f", "%{file}\n%{index}", pattern, quiet=True)
    f, _, i = r.stdout.partition("\n")
    return (f, int(i or 0)) if f and Path(f).is_file() else (None, 0)
