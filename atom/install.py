"""`rice.py install [--dry-run]`: put every piece of the rice where Plasma, KWin and systemd look for it,
from wherever this repo is cloned. Safe to run again (it only changes what differs) and never overwrites
something it didn't make (a file in the way is reported, not replaced).

  links      ~/.config/plasma-rice to the clone (when it's cloned elsewhere: units, widgets and shortcuts call
             that path), plasmoids/*, lnf/* and kwin/* into ~/.local/share (symlinks into the repo, so a git pull is
             the update), the user units in systemd/ into ~/.config/systemd/user
  units      enabled by feature: the display watcher always; keyboard lights, the update check when on
  plasmashell  its drop-in (the widgets read and write the rice's files with XMLHttpRequest)
  shortcuts  command launchers (Meta+Alt+N / B / Shift+N: next, previous, random wallpaper; Meta+Shift+W the
             Theme page; Meta+Alt+T tiling)
             and the Dolphin "Rice" menu for images; keys are only bound where nothing is bound yet
  Claude Code  Clawd's hooks and, when you have none, the status line that feeds the usage rings, in
             ~/.claude/settings.json (atom/claude.py); commands calling the scripts' old place move to bin/
  checks     the commands and Python modules the rice needs

What needs root (login screen copier, the Razer udev rule, boot theming) is printed for the user to run.
`rice.py doctor` checks the result.
"""
import importlib.util
import shutil
import subprocess

from . import caps, claude, kde, kwin, util
from .util import HOME, ROOT

APPS = HOME / ".local/share/applications"
SERVICEMENUS = HOME / ".local/share/kio/servicemenus"
UNITS = HOME / ".config/systemd/user"
DROPIN = UNITS / "plasma-plasmashell.service.d/rice.conf"
CANONICAL = HOME / ".config/plasma-rice"            # where units, shortcuts and widgets find the rice

NEEDS_CMDS = ["python3", "qdbus6", "kscreen-doctor", "kwriteconfig6", "kreadconfig6", "magick", "notify-send",
              "udevadm", "plasmashell"]
NEEDS_PY = ["PIL", "numpy", "dbus", "gi", "evdev"]

# command launchers: id -> (name, icon, command after the repo path, default keys)
LAUNCHERS = {
    "net.local.rice-wall-next": ("Next wallpaper", "go-next", "rice.py next --screen focused", "Meta+Alt+N"),
    "net.local.rice-wall-prev": ("Previous wallpaper", "go-previous", "rice.py prev --screen focused", "Meta+Alt+B"),
    # (not Meta+Alt+R: Spectacle's screen recording has it by default)
    "net.local.rice-wall-random": ("Random wallpaper", "media-playlist-shuffle", "rice.py random --screen focused",
                                   "Meta+Alt+Shift+N"),
    "net.local.rice-wallpapers": ("Wallpapers", "preferences-desktop-wallpaper", "bin/wallpapers.sh", "Meta+Shift+W"),
    "net.local.rice-tiling": ("Toggle auto-tiling", "view-grid", "bin/tiling.sh", "Meta+Alt+T"),
}

DROPIN_TEXT = """# Atom Plasma: the rice widgets read their palette files with QML's XMLHttpRequest instead of spawning a
# process per read (qml/Rice/RicePalette.qml), and pass a command's changing arguments in a file
# (qml/Rice/RiceShell.qml exec(), in $XDG_RUNTIME_DIR). The shell's QML (qml/Atom, imported by URI so every
# widget shares one Atom.Shell) and its native part (Atom.Native, built per user) are found through
# QML_IMPORT_PATH.
[Service]
Environment=QML_XHR_ALLOW_FILE_READ=1
Environment=QML_XHR_ALLOW_FILE_WRITE=1
Environment=QML_IMPORT_PATH=%h/.config/plasma-rice/qml:%h/.local/lib/qt6/qml
"""
NATIVE = HOME / ".local/lib/qt6/qml/Atom/Native"     # pkg/atom-native/build.sh puts it there

# the programs that lived at the repo's root before bin/ (2026-11-15): what may still call them there
MOVED_TO_BIN = ("agenda.py", "apps.py", "ask.sh", "battery-saver.py", "boot.py", "clawd-hook.sh", "clawd-intent.py",
                "displayd.py", "kwin-run.py", "layout.py", "rgb.py", "run-argv.py", "servicemenu.sh", "tiling.sh",
                "tokens.py", "update-check.py", "wallhaven.py", "wallpapers.sh", "weather.py")
# where a user's own setup may call them (the installer's own files it simply rewrites)
CALLERS = [".zshrc", ".bashrc", ".profile", ".config/fish/config.fish", ".config/autostart/*.desktop",
           ".local/share/applications/*.desktop", ".local/share/kio/servicemenus/*.desktop", ".claude/settings.json"]


def old_paths():
    """[(file, line number, line)] of the user's files that still call a script at the root, not in bin/."""
    import re
    pat = re.compile(r"plasma-rice/(" + "|".join(re.escape(n) for n in MOVED_TO_BIN) + r")\b")
    out = []
    for glob in CALLERS:
        for f in sorted(HOME.glob(glob)):
            try:
                lines = f.read_text().splitlines()
            except (OSError, UnicodeDecodeError):
                continue
            out += [(f, i + 1, line.strip()) for i, line in enumerate(lines) if pat.search(line)]
    return out


def native_stale():
    """Atom.Native is missing, or older than its sources (a pull brought new C++: the QML that uses it won't
    load until it's rebuilt)."""
    lib = NATIVE / "libatomnative.so"
    if not (NATIVE / "qmldir").exists() or not lib.exists():
        return True
    src = ROOT / "pkg/atom-native"
    newest = max(f.stat().st_mtime for f in [src / "CMakeLists.txt", *(src / "src").iterdir()] if f.is_file())
    return newest > lib.stat().st_mtime


PAD_IM = HOME / ".local/bin/atom-pad-im"


def pad_im_stale():
    """Atom Pad's input method (the controller's keyboard types any character through it) is missing or older
    than its source."""
    src = ROOT / "pkg/atom-pad-im"
    if not PAD_IM.exists():
        return True
    return max(f.stat().st_mtime for f in (src / "atom-pad-im.c", src / "build.sh")) > PAD_IM.stat().st_mtime


class Plan:
    def __init__(self, dry):
        self.dry, self.done, self.blocked = dry, [], []

    def link(self, link, target):
        try:
            if link.resolve(strict=True) == target.resolve():
                return
        except OSError:
            pass
        if link.exists() and not link.is_symlink():
            self.blocked.append(f"{link} is in the way (a real file or folder, not ours)")
            return
        self.done.append(f"link {link} -> {target}")
        if not self.dry:
            link.parent.mkdir(parents=True, exist_ok=True)
            link.unlink(missing_ok=True)
            link.symlink_to(target)

    def write(self, path, text, ours_marker=None):
        try:
            cur = path.read_text()
        except OSError:
            cur = None
        if cur == text:
            return
        if cur is not None and ours_marker and ours_marker not in cur:
            self.blocked.append(f"{path} exists and isn't ours")
            return
        self.done.append(f"write {path}")
        if not self.dry:
            util.write_if_changed(path, text)

    def run(self, *cmd):
        self.done.append("run " + " ".join(cmd))
        if not self.dry:
            util.run(*cmd)


def launcher(name, icon, command):
    return ("[Desktop Entry]\nType=Application\n"
            f"Name={name}\nExec={ROOT / command}\nIcon={icon}\nNoDisplay=true\n"
            "X-KDE-GlobalAccel-CommandShortcut=true\nX-AtomPlasma=true\n")


def servicemenu():
    menu = ROOT / "bin/servicemenu.sh"
    return ("[Desktop Entry]\nType=Service\nMimeType=image/jpeg;image/png;image/webp;\nActions=here;all;add;\n"
            "X-KDE-Submenu=Rice\nIcon=preferences-desktop-wallpaper\nX-AtomPlasma=true\n\n"
            "[Desktop Action here]\nName=Wallpaper for this screen (re-theme)\nIcon=preferences-desktop-wallpaper\n"
            f"Exec={menu} here %f\n\n"
            "[Desktop Action all]\nName=Wallpaper for all screens (re-theme)\nIcon=preferences-desktop-display\n"
            f"Exec={menu} all %f\n\n"
            "[Desktop Action add]\nName=Add to wallpaper collection\nIcon=list-add\n"
            f"Exec={menu} add %F\n")


def cfg_claude(p, cfg):
    """Claude Code's settings: Clawd's hooks, the status line (atom/claude.py). True when they changed."""
    if not caps.feature("claude", cfg):
        return False
    path = claude.SETTINGS.resolve()           # (a dotfiles symlink stays one)
    try:
        new, what = claude.plan(path.read_text() if path.exists() else "", caps.feature("update_check", cfg))
    except (OSError, ValueError):
        p.blocked.append(f"{claude.SETTINGS} isn't a JSON object: Clawd's hooks weren't added")
        return False
    if not new:
        return False
    p.done += [f"Claude Code: {w}" for w in what]
    if not p.dry:
        mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
        util.write_if_changed(path, new)
        path.chmod(mode)
    return True


def missing():
    cmds = [c for c in NEEDS_CMDS if not shutil.which(c)]
    mods = [m for m in NEEDS_PY if importlib.util.find_spec(m) is None]
    return cmds, mods


def install(dry=False):
    p = Plan(dry)
    cfg = util.settings()
    # the units and the widgets call ~/.config/plasma-rice/...: a clone kept elsewhere is reached through it
    if ROOT != CANONICAL:
        p.link(CANONICAL, ROOT)
    for d in sorted(x for x in (ROOT / "plasmoids").iterdir() if x.is_dir()):
        p.link(HOME / ".local/share/plasma/plasmoids" / d.name, d)
    for d in sorted(x for x in (ROOT / "lnf").iterdir() if x.is_dir()):
        p.link(HOME / ".local/share/plasma/look-and-feel" / d.name, d)
    for src, link in kwin.packages():         # effects and scripts, each where KWin looks for it
        p.link(link, src)
    for f in sorted((ROOT / "systemd").glob("*.service")) + sorted((ROOT / "systemd").glob("*.timer")):
        p.link(UNITS / f.name, f)
    p.write(DROPIN, DROPIN_TEXT, ours_marker="Atom Plasma")
    if native_stale():                  # (missing, or a pull brought new sources)
        p.run(str(ROOT / "pkg/atom-native/build.sh"))
    if caps.feature("gamepad", cfg) and pad_im_stale():     # (also sets it as KWin's input method, if none is)
        p.run(str(ROOT / "pkg/atom-pad-im/build.sh"))
    for i, (name, icon, cmd, _) in LAUNCHERS.items():
        p.write(APPS / f"{i}.desktop", launcher(name, icon, cmd), ours_marker="X-AtomPlasma")
    p.write(SERVICEMENUS / "rice.desktop", servicemenu(), ours_marker="X-AtomPlasma")
    hooks_changed = cfg_claude(p, cfg)

    # keys, only where none is bound (kglobalaccel reads them at the next login)
    have = kde.kde_read(HOME / ".config/kglobalshortcutsrc")
    for i, (_, _, _, keys) in LAUNCHERS.items():
        if not have.get(("services", f"{i}.desktop"), {}).get("_launch"):
            p.run("kwriteconfig6", "--file", "kglobalshortcutsrc", "--group", "services", "--group", f"{i}.desktop",
                  "--key", "_launch", keys)

    want = ["atom-plasma-displayd.service"]
    if caps.feature("keyboard_lights", cfg):
        want.append("atom-plasma-rgb-watch.service")
    if caps.feature("gamepad", cfg):
        want.append("atom-plasma-pad.service")
    if caps.feature("update_check", cfg):
        want += ["atom-plasma-update-check.timer", "atom-plasma-update-tidy.timer"]
    # KRunner is replaced by the launcher's search (Atom.Native's KRunner holds its place on the bus, so its
    # shortcut and typing on the desktop open the finder): its own daemon must never start
    r = util.run("systemctl", "--user", "is-enabled", "plasma-krunner.service", quiet=True)
    if r is None or r.stdout.strip() != "masked":
        p.run("systemctl", "--user", "mask", "--now", "plasma-krunner.service")
    if not dry and p.done:
        util.run("systemctl", "--user", "daemon-reload")
    for u in want:
        r = util.run("systemctl", "--user", "is-enabled", u, quiet=True)
        if r is None or r.stdout.strip() != "enabled":
            p.run("systemctl", "--user", "enable", "--now", u)

    if not dry and (SERVICEMENUS / "rice.desktop").exists():
        (SERVICEMENUS / "rice.desktop").chmod(0o755)        # Dolphin only runs executable service menus
        (ROOT / "bin/servicemenu.sh").chmod(0o755)

    cmds, mods = missing()
    out = [("would " if dry else "") + x for x in p.done] or ["everything was in place"]
    out += [f"skipped: {b}" for b in p.blocked]
    if hooks_changed:
        out.append("Claude Code reads its hooks when a session starts: restart open sessions (or review them in /hooks)")
    rewritten = {APPS / f"{i}.desktop" for i in LAUNCHERS} | {SERVICEMENUS / "rice.desktop", claude.SETTINGS}
    for f, n, line in old_paths():
        if not (dry and f in rewritten):     # (a dry run hasn't rewritten its own files yet)
            out.append(f"still calls a script's old place (it's in bin/ now): {f}:{n}: {line}")
    if cmds or mods:
        out.append("missing: " + ", ".join(cmds + [f"python module {m}" for m in mods]))
    out.append("")
    out.append("needs root (run these yourself, once):")
    if caps.feature("login_theme", cfg):
        out.append(f"  {ROOT / 'bin/boot.py'} login        # the login screen follows the theme")
    if caps.found()["razer"]:
        out.append(f"  {ROOT / 'bin/rgb.py'} status        # prints the Razer udev rule to install, if it's missing")
    if caps.feature("boot_theme", cfg):
        out.append(f"  {ROOT / 'bin/boot.py'} plymouth / limine   # boot splash and menu (optional)")
    out.append("then: log out and in once (plasmashell's environment, shortcuts), and run rice.py setup + rice.py random")
    return "\n".join(out)
