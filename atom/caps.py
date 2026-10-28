"""What this machine has, and which of the rice's features are on.

Each feature is "auto" (on when the machine has what it needs), "on" or "off" in settings.json
`features` {name: auto|on|off}. The rice asks feature(name) before doing anything that needs hardware or
software another machine may not have, so the same repo runs anywhere: a desktop PC gets no battery saver,
a machine without Claude Code no Clawd, a non-Arch system no update check.

    caps.report()      what was found and what's on (rice.py doctor shows it)
"""
import functools
import glob
import shutil
from pathlib import Path

from . import util
from .util import HOME


def _bus_has(name, system=False):
    r = util.run("qdbus6", *(["--system"] if system else []), name, quiet=True, timeout=5)
    return r is not None and r.returncode == 0


@functools.cache
def found():
    """{capability: bool}, probed once per process."""
    return {
        "battery": any(Path(p, "type").read_text().strip() == "Battery"
                       for p in glob.glob("/sys/class/power_supply/*") if Path(p, "type").exists()),
        "asus_keyboard": _bus_has("xyz.ljones.Asusd", system=True),
        "razer": any(Path(p).read_text().strip().lower() == "1532" for p in glob.glob("/sys/bus/usb/devices/*/idVendor")),
        "krohnkite": (HOME / ".local/share/kwin/scripts/krohnkite").is_dir()
                     or Path("/usr/share/kwin/scripts/krohnkite").is_dir(),
        "colorizer": Path("/usr/share/plasma/plasmoids/luisbocanegra.panel.colorizer").is_dir()
                     or (HOME / ".local/share/plasma/plasmoids/luisbocanegra.panel.colorizer").is_dir(),
        "claude": bool(shutil.which("claude")) or (HOME / ".claude").is_dir(),
        "nvidia": bool(shutil.which("nvidia-smi")),
        "arch": bool(shutil.which("pacman")) and bool(shutil.which("checkupdates")),
        "aur_helper": bool(shutil.which("paru") or shutil.which("yay")),
        "limine": bool(shutil.which("limine")),        # (/boot itself may be root-only)
        "plymouth": bool(shutil.which("plymouth-set-default-theme")),
        "plasma_login": Path("/etc/plasmalogin.conf").exists() or Path("/usr/lib/systemd/system/plasmalogin.service").exists(),
        "vscode": bool(shutil.which("code")),
        "zen": (HOME / ".local/share/zen").is_dir() or bool(shutil.which("zen-browser")),
    }


# feature -> (what it needs: all of these capabilities, what it does)
FEATURES = {
    "claude": (["claude"], "Clawd and Claude usage on the bar, desk and popups (Claude Code)"),
    "tiling": (["krohnkite"], "per-screen auto-tiling (Krohnkite), its bar toggle and Meta+Alt+T"),
    "islands": (["colorizer"], "the bar's glass islands (Panel Colorizer)"),
    "keyboard_lights": ([], "keyboard RGB in the screen's accents (ASUS laptops through asusd, Razer keyboards)"),
    "battery_saver": (["battery"], "the battery saver card on the launcher (laptops)"),
    "update_check": (["arch", "claude"], "the daily check for important updates (Arch/CachyOS + Claude Code)"),
    "boot_theme": (["limine", "plymouth"], "boot menu and splash theming (Limine + Plymouth)"),
    "login_theme": (["plasma_login"], "the login screen follows the theme (Plasma Login Manager)"),
}


def feature(name, cfg=None):
    """Is this feature on? settings features.<name>: on | off | auto (default: on when its needs are met)."""
    cfg = util.settings() if cfg is None else cfg
    want = str(((cfg.get("features") or {}).get(name, "auto"))).lower()
    if want in ("on", "true", "1"):
        return True
    if want in ("off", "false", "0"):
        return False
    needs, _ = FEATURES.get(name, ([], ""))
    if name == "keyboard_lights":
        return found()["asus_keyboard"] or found()["razer"]
    return all(found().get(n) for n in needs)


def report(cfg=None):
    cfg = util.settings() if cfg is None else cfg
    f = found()
    lines = ["found:    " + ", ".join(k for k, v in f.items() if v),
             "missing:  " + (", ".join(k for k, v in f.items() if not v) or "nothing")]
    for name, (needs, what) in FEATURES.items():
        setting = (cfg.get("features") or {}).get(name, "auto")
        lines.append(f"{'on ' if feature(name, cfg) else 'off'}  {name:<16} {what}"
                     + (f"  [set {setting}]" if setting != "auto" else ""))
    return "\n".join(lines)
