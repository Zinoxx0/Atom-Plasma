"""Atom Plasma's updater (Atom Manager's engine): releases are git tags (atom/version.py: stable, beta, alpha).

    rice.py update check [--notify] [--offline]   ask GitHub for releases on your channel; --notify: a
                                                    notification from "Atom Manager" when one waits (the timer)
    rice.py update start [--force]                update to the newest release, in the background (a systemd
                                                    unit: it restarts plasmashell at the end, which would kill it
                                                    anywhere inside the desktop); --force: over a custom build
    rice.py update apply TAG [--force]            what start runs (the steps below), in the foreground
    rice.py update channel stable|beta|alpha      which releases you get (settings updates.channel)
    rice.py update fresh                          a new install (install.sh runs it after cloning)
    rice.py update rollback                       back to the build before the last update

Who it manages: a copy on its own branch `atom-release` (install.sh makes one). Any other branch is a
developer copy (yours, a contributor's): the updater reports what's out but never touches it, unless you ask
it to switch to releases (that counts as custom: it asks first, and keeps your work).

An update, step by step (~/.local/state/rice/update-progress.json, read live by Atom Manager; the log in
update.log beside it):
    check     the target's own requirements (Plasma range, Wayland, packages) against this system
    backup    your build as a branch backup/<date>-<version> (and your changes, stashed and kept as a branch)
    packages  what the target needs and you lack: the distro's through one polkit prompt, the AUR's through
              your AUR helper in a terminal you watch (Arch family only for now; elsewhere it lists them)
    code      atom-release moves to the target's tag
    build     the parts that are compiled: Atom.Native, the pad's input method (rice.py install), and the
              window corners plugin when its recipe or KWin changed (makepkg, then one polkit prompt)
    install   rice.py install with the new code (links, units, the saved data's upgrade)
    restart   plasmashell
    verify    plasmashell stays up and the shell loads; if not, everything goes back to the backup (rollback)

Critical updates: a release's annotated tag message carries `Critical: yes` (and `Summary: ...`); everyone
below it on a channel that takes it sees the banner, and the notification stays until it's answered.
ATOM_UPDATE_DRY=1 (the tests): the git work only; nothing installed, built, restarted or notified."""
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

from . import caps, util
from .util import CACHE, ROOT, STATE
from .version import CHANNELS, Version, allowed, newest

STATE_FILE = STATE / "update.json"
PROGRESS = STATE / "update-progress.json"
BACKUP_FILE = STATE / "update-backup.json"
BUILT = STATE / "update-built.json"           # what the compiled plugins were last built from
LOG = STATE / "update.log"
STATUS = CACHE / "manager-status.json"          # the launcher's gear: a dot, the critical banner
BRANCH = "atom-release"
REQS = "atom/data/requirements.json"
UNIT = "atom-plasma-updating"
DRY = os.environ.get("ATOM_UPDATE_DRY") == "1"
STEPS = ["check", "backup", "packages", "code", "build", "install", "restart", "verify"]


# ---------------------------------------------------------------- git
def git(*args, timeout=120, check=False):
    r = util.run("git", "-C", str(ROOT), *args, quiet=True, timeout=timeout)
    if check and r.returncode:
        raise UpdateError(f"git {' '.join(args[:2])}: {(r.stderr or r.stdout).strip()[-300:]}")
    return r


def out(*args, timeout=60):
    r = git(*args, timeout=timeout)
    return r.stdout.strip() if r.returncode == 0 else ""


class UpdateError(Exception):
    pass


def is_checkout():
    return (ROOT / ".git").exists()


def branch():
    return out("rev-parse", "--abbrev-ref", "HEAD")


def mode():
    """managed (atom-release, or detached at a release tag) | developer (any other branch) | none (no git)."""
    if not is_checkout():
        return "none"
    b = branch()
    if b == BRANCH:
        return "managed"
    if b == "HEAD" and Version.parse(out("describe", "--tags", "--exact-match")):
        return "managed"
    return "developer"


def remote_url():
    from .manager import https_url
    url = out("remote", "get-url", "origin")
    return https_url(url) if url else ""


def fetch():
    """The releases (every tag) and main from the repo's home, over https (no key, never a prompt). Moves
    tags and origin/main only: your branch and files stay as they are. '' when it worked, else why not."""
    url = remote_url()
    if not url:
        return "no remote to ask"
    src = url + ".git" if url.startswith("https://") else out("remote", "get-url", "origin")     # (a local path: as is)
    r = util.run("git", "-C", str(ROOT), "-c", "credential.helper=", "fetch", "--quiet", "--force", src,
                 "+refs/tags/*:refs/tags/*", "+refs/heads/main:refs/remotes/origin/main", quiet=True, timeout=60)
    if r.returncode == 0:
        return ""
    msg = (r.stderr or r.stdout).strip().splitlines()
    return msg[-1] if msg else "couldn't reach it"


def releases():
    """[{version, tag, critical, summary, notes}] for every tag that is a version, oldest first."""
    fmt = "%(refname:short)%1f%(contents)%1e"
    rows = []
    for rec in out("for-each-ref", "refs/tags", "--format=" + fmt).split("\x1e"):
        name, _, body = rec.strip().partition("\x1f")
        v = Version.parse(name)
        if not v or not name.startswith("v"):
            continue
        fields = dict((k.lower(), val.strip()) for k, val in re.findall(r"^([A-Za-z-]+):\s*(.+)$", body, re.M))
        rows.append({"version": v, "tag": name, "critical": fields.get("critical", "").lower() in ("yes", "true", "1"),
                     "summary": fields.get("summary", ""), "notes": body.strip()})
    rows.sort(key=lambda r: r["version"])
    return rows


def current():
    """This build's version (atom/__init__.py, read fresh: the code on disk may be newer than this process)."""
    m = re.search(r'__version__\s*=\s*"([^"]+)"', (ROOT / "atom/__init__.py").read_text())
    return Version.parse(m[1]) if m else None


def channel(cfg=None):
    cfg = util.settings() if cfg is None else cfg
    c = str((cfg.get("updates") or {}).get("channel", "stable")).lower()
    return c if c in CHANNELS else "stable"


def set_channel(c):
    if c not in CHANNELS:
        raise SystemExit(f"channel: one of {', '.join(CHANNELS)}")
    cfg = util.user_settings()
    cfg.setdefault("updates", {})["channel"] = c
    util.save_settings(cfg)


def custom_reasons():
    """Why this build isn't a plain release: changed files, commits of its own, another branch."""
    why = []
    changed = [l for l in out("status", "--porcelain", "--untracked-files=no").splitlines() if l.strip()]
    if changed:
        why.append(f"{len(changed)} changed file{'s' if len(changed) != 1 else ''}")
    cur = current()
    tag_commit = out("rev-parse", "--verify", "--quiet", f"{cur.tag}^{{commit}}") if cur else ""
    if mode() == "developer":
        why.append(f"a developer copy (on {branch()})")
    elif tag_commit and tag_commit != out("rev-parse", "HEAD"):
        n = out("rev-list", "--count", f"{tag_commit}..HEAD")
        if n and n != "0":
            why.append(f"{n} commit{'s' if n != '1' else ''} of your own")
    return why


# ---------------------------------------------------------------- the system and what it needs
def requirements(ref=None):
    text = out("show", f"{ref}:{REQS}") if ref else ""
    if not text:
        try:
            text = (ROOT / REQS).read_text()
        except OSError:
            return {}
    try:
        return json.loads(text)
    except ValueError:
        return {}


def distro():
    osr = {}
    try:
        for line in Path("/etc/os-release").read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                osr[k] = v.strip().strip('"')
    except OSError:
        pass
    ids = {osr.get("ID", "")} | set(osr.get("ID_LIKE", "").split())
    family = "arch" if ids & {"arch", "archlinux"} or shutil.which("pacman") else ""
    return {"name": osr.get("PRETTY_NAME", "") or osr.get("NAME", "Linux"), "family": family}


def _minor(v):
    m = re.match(r"(\d+)\.(\d+)", v or "")
    return (int(m[1]), int(m[2])) if m else None


def system_check(reqs, sysinfo=None):
    """{blockers: [...], warnings: [...]} for this system against a version's requirements."""
    from .manager import system
    s = sysinfo or system()
    blockers, warnings = [], []
    if not shutil.which("plasmashell"):
        blockers.append("KDE Plasma isn't installed: Atom Plasma is a Plasma desktop")
    else:
        have, lo, hi = _minor(s.get("plasma")), _minor((reqs.get("plasma") or {}).get("min")), _minor((reqs.get("plasma") or {}).get("max"))
        if have and lo and have < lo:
            blockers.append(f"needs Plasma {reqs['plasma']['min']} or newer: this is {s['plasma']}")
        elif have and hi and have > hi:
            blockers.append(f"made for Plasma {reqs['plasma']['max']}: this is {s['plasma']} (a release for it will follow)")
    if reqs.get("session") == "wayland" and s.get("session") and s["session"].lower() != "wayland":
        blockers.append(f"runs on Plasma's Wayland session: this is {s['session']}")
    d = distro()
    if not d["family"]:
        warnings.append(f"packages can't be installed for you on {d['name']} yet: the list shows what to install")
    return {"blockers": blockers, "warnings": warnings, "family": d["family"], "distro": d["name"]}


def wanted_packages(reqs, cfg=None, fresh=False, family="arch"):
    """[{pkg, aur}] the version needs here: required, build, the features set to on (and, fresh, recommended)."""
    cfg = util.settings() if cfg is None else cfg
    fam = (reqs.get("families") or {}).get(family) or {}
    want = list(fam.get("required", [])) + list(fam.get("build", []))
    feats = cfg.get("features") or {}
    for name, pkgs in (fam.get("features") or {}).items():
        if str(feats.get(name, "auto")).lower() in ("on", "true", "1") or (fresh and caps.feature(name, cfg)):
            want += pkgs
    if fresh:
        want += fam.get("recommended", [])
    seen, uniq = set(), []
    for p in want:
        if p["pkg"] not in seen:
            seen.add(p["pkg"])
            uniq.append({"pkg": p["pkg"], "aur": bool(p.get("aur"))})
    return uniq


def missing_packages(pkgs):
    """The ones pacman doesn't have installed (provides count: pacman -T)."""
    if not pkgs or not shutil.which("pacman"):
        return list(pkgs)
    r = util.run("pacman", "-T", *[p["pkg"] for p in pkgs], quiet=True, timeout=30)
    gone = set(r.stdout.split())
    # (a group like base-devel isn't a package: pacman -T calls it missing; ask the group instead)
    for p in pkgs:
        if p["pkg"] in gone and util.run("pacman", "-Qg", p["pkg"], quiet=True).returncode == 0:
            gone.discard(p["pkg"])
    return [p for p in pkgs if p["pkg"] in gone]


# ---------------------------------------------------------------- check
def _status(st):
    util.save_json(STATUS, {"version": st.get("current", ""), "available": bool(st.get("available")),
                            "critical": bool(st.get("critical")), "latest": st.get("latest", ""),
                            "mode": st.get("mode", ""), "checked": st.get("checked", 0)})


def check(do_fetch=True, notify=False):
    """What's out on your channel, written to update.json (Atom Manager and the gear read it)."""
    if not is_checkout():
        st = {"checked": int(time.time()), "mode": "none", "error": "not a git copy: reinstall with install.sh"}
        util.save_json(STATE_FILE, st)
        _status(st)
        return st
    err = fetch() if do_fetch else ""
    old = util.load_json(STATE_FILE, {}) or {}
    cfg = util.settings()
    chan, cur, rels, m = channel(cfg), current(), releases(), mode()
    target = newest([r["version"] for r in rels], chan)
    ahead = bool(cur and target and target > cur)
    tgt = next((r for r in rels if r["version"] == target), None) if ahead else None
    crit = [r for r in rels if cur and r["critical"] and cur < r["version"] <= (target or cur) and allowed(r["version"], chan)] if ahead else []
    reqs = requirements(tgt["tag"]) if tgt else requirements()
    sysc = system_check(reqs)
    need = missing_packages(wanted_packages(reqs, cfg)) if sysc["family"] == "arch" else wanted_packages(reqs, cfg, family=sysc["family"] or "arch")
    st = {
        "checked": int(time.time()) if not err else int(old.get("checked", 0) or 0),
        "error": err,
        "mode": m,
        "branch": branch(),
        "channel": chan,
        "current": str(cur) if cur else "",
        "latest": str(target) if target else "",
        "latestTag": tgt["tag"] if tgt else "",
        "available": ahead and m == "managed",
        "newer": ahead,                          # (a developer copy sees it too, it just isn't offered)
        "critical": bool(crit) and m == "managed",
        "summary": (crit[-1]["summary"] if crit else tgt["summary"] if tgt else ""),
        "notes": tgt["notes"] if tgt else "",
        "blockers": sysc["blockers"],
        "warnings": sysc["warnings"],
        "distro": sysc["distro"],
        "install": {"repo": [p["pkg"] for p in need if not p["aur"]], "aur": [p["pkg"] for p in need if p["aur"]]},
        "custom": custom_reasons() if m != "none" else [],
        "devBehind": int(out("rev-list", "--count", "HEAD..origin/main") or 0) if m == "developer" else 0,
        "notified": old.get("notified", ""),
        "releases": [{"version": str(r["version"]), "channel": r["version"].channel, "critical": r["critical"]} for r in rels[-12:]],
    }
    util.save_json(STATE_FILE, st)
    _status(st)
    if notify and st["available"] and not st["blockers"] and not DRY:
        key = st["latest"] + (":critical" if st["critical"] else "")
        if key != st["notified"] or st["critical"]:
            st["notified"] = key
            util.save_json(STATE_FILE, st)
            if offer(st) == "update":
                start(force=False)
    return st


def state():
    return util.load_json(STATE_FILE, {}) or {}


# ---------------------------------------------------------------- notifications (as "Atom Manager")
def notify(title, body, critical=False, actions=None, icon="system-software-update"):
    """A notification from Atom Manager; with actions it waits and returns the one picked ('' for none)."""
    if DRY or not shutil.which("notify-send"):
        return ""
    cmd = ["notify-send", "-a", "Atom Manager", "-i", icon, "-u", "critical" if critical else "normal"]
    for k, label in (actions or {}).items():
        cmd.append(f"--action={k}={label}")
    cmd += [title, body]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=6 * 3600 if actions else 20)
        return r.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def offer(st):
    if st["critical"]:
        return notify("Critical update for Atom Plasma", (st["summary"] or "It fixes a security problem.") + f"\nAtom Plasma {st['latest']} is ready.",
                      critical=True, actions={"update": "Update now", "later": "Later"}, icon="security-low")
    return notify(f"Atom Plasma {st['latest']} is out", st["summary"] or f"An update on the {st['channel']} channel is ready.",
                  actions={"update": "Update", "later": "Later"})


# ---------------------------------------------------------------- an update
class Progress:
    def __init__(self, target, steps=STEPS):
        self.d = {"state": "running", "target": target, "steps": list(steps), "step": "", "done": [], "message": "",
                  "started": int(time.time()), "finished": 0, "log": str(LOG)}
        self.save()

    def save(self):
        util.save_json(PROGRESS, self.d)

    def step(self, name, message=""):
        if self.d["step"] and self.d["step"] not in self.d["done"]:
            self.d["done"].append(self.d["step"])
        self.d["step"], self.d["message"] = name, message
        log(f"-- {name}: {message}")
        self.save()
        if DRY and os.environ.get("ATOM_UPDATE_FAIL") == name:        # (the tests: a step that fails)
            raise UpdateError(f"{name} failed (test)")

    def say(self, message):
        self.d["message"] = message
        log(message)
        self.save()

    def end(self, st, message):
        if st == "done" and self.d["step"] not in self.d["done"]:
            self.d["done"].append(self.d["step"])
        self.d.update(state=st, message=message, finished=int(time.time()))
        log(f"== {st}: {message}")
        self.save()


def log(msg):
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open("a") as f:
        f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")


def sh(*cmd, timeout=3600, cwd=None):
    """Run a step's command, its output into the log; raise when it fails."""
    log("$ " + " ".join(map(str, cmd)))
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError) as e:
        raise UpdateError(f"{cmd[0]}: {e}")
    if r.stdout.strip():
        log(r.stdout.strip()[-4000:])
    if r.stderr.strip():
        log(r.stderr.strip()[-4000:])
    if r.returncode:
        tail = ((r.stderr.strip() or r.stdout.strip()).splitlines() or [""])[-1]
        raise UpdateError(f"{Path(str(cmd[0])).name} failed ({r.returncode}): {tail}"[:300])
    return r


def start(force=False):
    """The update, in its own transient user unit (it outlives plasmashell's restart)."""
    st = state()
    if not st.get("latestTag"):
        st = check(do_fetch=False)
    tag = st.get("latestTag")
    if not tag:
        return "nothing to update to"
    if util.run("systemctl", "--user", "is-active", UNIT + ".service", quiet=True).stdout.strip() in ("active", "activating"):
        return "an update is already running"
    cmd = [sys.executable, str(ROOT / "rice.py"), "update", "apply", tag] + (["--force"] if force else [])
    if DRY:
        return " ".join(cmd)
    util.run("systemctl", "--user", "reset-failed", UNIT + ".service", quiet=True)
    r = util.run("systemd-run", "--user", "--unit", UNIT, "--collect", "--quiet", "--description", f"Atom Plasma update to {tag}",
                 "-p", "TimeoutStopSec=30", *cmd, quiet=True)
    return "" if r.returncode == 0 else (r.stderr or r.stdout).strip()


def backup(p, cur):
    """Your build as a branch, your changes stashed and kept as a branch too: nothing is ever lost."""
    stamp = datetime.now().strftime("%Y%m%d-%H%M")
    name = f"backup/{stamp}-{cur or 'unknown'}"
    head, was = out("rev-parse", "HEAD"), branch()
    git("branch", "-f", name, head, check=True)
    changes = ""
    if out("status", "--porcelain"):
        before = out("rev-parse", "--verify", "--quiet", "stash@{0}")
        ident = ["-c", "user.name=Atom Manager", "-c", "user.email=atom-manager@localhost"]
        git(*ident, "stash", "push", "--include-untracked", "-m", f"Atom Manager backup {stamp}", check=True)
        after = out("rev-parse", "--verify", "--quiet", "stash@{0}")
        if after and after != before:
            changes = after
            git("branch", "-f", name + "-changes", changes, check=True)
            git("stash", "drop", "stash@{0}")        # (anchored on the backup branch: keep the user's stash stack clean)
    b = {"branch": name, "head": head, "was": was, "changes": changes, "version": str(cur or ""), "at": int(time.time())}
    util.save_json(BACKUP_FILE, b)
    p.say(f"your build is kept as {name}" + (f" (your changes: {name}-changes)" if changes else ""))
    return b


def install_packages(p, need, family):
    if not need:
        p.say("nothing to install")
        return
    if family != "arch":
        raise UpdateError("install these first: " + ", ".join(x["pkg"] for x in need))
    repo = [x["pkg"] for x in need if not x["aur"]]
    aur = [x["pkg"] for x in need if x["aur"]]
    if DRY:
        p.say(f"(dry) would install {repo} and from the AUR {aur}")
        return
    if repo:
        p.say("installing " + ", ".join(repo) + " (asks for your password)")
        sh("pkexec", "pacman", "-S", "--needed", "--noconfirm", *repo, timeout=3600)
    if aur:
        helper = shutil.which("paru") or shutil.which("yay")
        if not helper:
            raise UpdateError("needs an AUR helper (paru or yay) for " + ", ".join(aur))
        p.say("building " + ", ".join(aur) + " from the AUR in a terminal")
        term = shutil.which("konsole")
        cmd = shlex.join([helper, "-S", "--needed", *aur])
        script = (f"if {cmd}; then echo; echo 'Atom Manager: done here, press Enter'; "
                  "else rc=$?; echo; echo \"Atom Manager: failed ($rc), press Enter\"; fi; read _")
        if term:
            sh(term, "--nofork", "-e", "sh", "-c", script, timeout=7200)
        else:
            sh(helper, "-S", "--needed", "--noconfirm", *aur, timeout=7200)
    left = missing_packages(need)
    if left:
        raise UpdateError("still missing: " + ", ".join(x["pkg"] for x in left))


def plugin_stamp(plugin):
    d = ROOT / plugin["dir"]
    h = hashlib.sha1()
    for f in sorted(x for x in d.iterdir() if x.is_file() and x.suffix in ("", ".patch", ".diff") and not x.name.startswith(".")):
        h.update(f.name.encode() + f.read_bytes())
    follows = util.run("pacman", "-Q", plugin["follows"], quiet=True).stdout.strip() if plugin.get("follows") and shutil.which("pacman") else ""
    return {"recipe": h.hexdigest(), "follows": follows}


def plugins_stale(reqs):
    built = util.load_json(BUILT, {}) or {}
    stale = []
    for pl in reqs.get("plugins", []):
        if not (ROOT / pl["dir"]).is_dir():
            continue
        installed = util.run("pacman", "-Q", pl["name"], quiet=True).returncode == 0 if shutil.which("pacman") else True
        if not installed or built.get(pl["name"]) != plugin_stamp(pl):
            stale.append(pl)
    return stale


def built_packages(name, d, listed=None):
    """Pick the built package file(s) from makepkg --packagelist (handles custom PKGDEST/PKGEXT, skips -debug and .sig)."""
    if listed is None:
        listed = []
        try:
            r = subprocess.run(["makepkg", "--packagelist"], cwd=d, capture_output=True, text=True, timeout=30)
            if r.returncode == 0:
                listed = [Path(line.strip()) for line in r.stdout.splitlines() if line.strip()]
        except (OSError, subprocess.SubprocessError):
            pass
    found = [Path(p) for p in listed if Path(p).is_file() and not Path(p).name.endswith(".sig")]
    if not found:
        found = sorted((f for f in Path(d).glob(f"{name}-*.pkg.tar*") if not f.name.endswith(".sig")),
                       key=lambda f: f.stat().st_mtime)
    main = [f for f in found if not f.name.startswith(f"{name}-debug-")]
    return main or found


def build_plugins(p, reqs):
    stale = plugins_stale(reqs)
    if not stale:
        p.say("the compiled plugins are current")
        return
    built = util.load_json(BUILT, {}) or {}
    for pl in stale:
        if DRY:
            p.say(f"(dry) would build {pl['name']}")
            continue
        d = ROOT / pl["dir"]
        p.say(f"building {pl['name']}")
        sh("makepkg", "-f", "--noconfirm", "--cleanbuild", cwd=d, timeout=3600)
        pkgs = built_packages(pl["name"], d)
        if not pkgs:
            raise UpdateError(f"makepkg made no package for {pl['name']}")
        p.say(f"installing {pl['name']} (asks for your password)")
        sh("pkexec", "pacman", "-U", "--noconfirm", str(pkgs[-1]))
        built[pl["name"]] = plugin_stamp(pl)
        util.save_json(BUILT, built)


def plasmashell_restarts():
    r = util.run("systemctl", "--user", "show", "-p", "NRestarts", "--value", "plasma-plasmashell.service", quiet=True)
    try:
        return int(r.stdout.strip() or 0)
    except ValueError:
        return 0


def restart_shell():
    if DRY:
        return
    util.run("systemctl", "--user", "reset-failed", "plasma-plasmashell.service", quiet=True)
    util.run("systemctl", "--user", "restart", "plasma-plasmashell.service", quiet=True, timeout=60)


def verify():
    """plasmashell stays up for 25 s after its restart, and the shell's QML loads. '' or what's wrong."""
    if DRY:
        return ""
    before = plasmashell_restarts()
    time.sleep(25)
    active = util.run("systemctl", "--user", "is-active", "plasma-plasmashell.service", quiet=True).stdout.strip()
    if active != "active":
        return f"plasmashell is {active or 'down'}"
    if plasmashell_restarts() > before:
        return "plasmashell crashed after the update"
    r = util.run(sys.executable, str(ROOT / "rice.py"), "update", "selftest", quiet=True, timeout=60)
    return "" if r.returncode == 0 else "the shell doesn't load: " + (r.stdout or r.stderr).strip()[-200:]


def apply(tag, force=False):
    """The update to `tag`, step by step (module doc). Rolls back on a failure after the code moved."""
    target = Version.parse(tag)
    p = Progress(str(target) if target else tag)
    LOG.parent.mkdir(parents=True, exist_ok=True)
    log(f"==== Atom Plasma update to {tag}")
    moved = False
    b = None
    try:
        p.step("check", "checking this system against " + tag)
        if not target or not out("rev-parse", "--verify", "--quiet", f"{tag}^{{commit}}"):
            raise UpdateError(f"there's no release {tag} here (check again)")
        if mode() == "developer" and not force:
            raise UpdateError("this is a developer copy: switching it to releases needs your OK")
        why = custom_reasons()
        if why and not force:
            raise UpdateError("your build is custom (" + ", ".join(why) + "): it needs your OK")
        reqs = requirements(tag)
        sysc = system_check(reqs)
        if sysc["blockers"]:
            raise UpdateError("; ".join(sysc["blockers"]))
        cur = current()
        need = missing_packages(wanted_packages(reqs)) if sysc["family"] == "arch" else wanted_packages(reqs)

        p.step("backup", "keeping your build")
        b = backup(p, cur)

        p.step("packages", "what the new version needs")
        install_packages(p, need, sysc["family"])

        p.step("code", f"moving to {tag}")
        git("checkout", "-f", "-B", BRANCH, tag, check=True)
        moved = True

        p.step("build", "the compiled parts")
        build_plugins(p, reqs)

        p.step("install", "putting every piece in place")
        if not DRY:
            sh(sys.executable, str(ROOT / "rice.py"), "install", timeout=1800)     # (the new code: a new process)

        p.step("restart", "restarting the desktop's shell")
        restart_shell()

        p.step("verify", "making sure it came back")
        bad = verify()
        if bad:
            raise UpdateError(bad)
        p.end("done", f"Atom Plasma {target} is in place")
        notify("Atom Plasma updated", f"You're on {target}." + (f" Your old build is kept as {b['branch']}." if b and b.get("changes") else ""))
    except Exception as e:
        msg = str(e) if isinstance(e, UpdateError) else f"{type(e).__name__}: {e}"
        log(f"failed: {msg}")
        if moved and b:
            p.say(f"{msg}: going back")
            try:
                restore(b)
                p.end("rolledback", f"{msg}. Your build is back as it was.")
                notify("Atom Plasma update undone", f"{msg}. Everything is back as it was before.", critical=True, icon="dialog-warning")
            except Exception as e2:
                p.end("failed", f"{msg}; going back failed too: {e2}. Your build is in {b['branch']}.")
                notify("Atom Plasma update failed", f"Your build is kept in {b['branch']}: see {LOG}", critical=True, icon="dialog-error")
        else:
            p.end("failed", msg)
            if b:
                restore_changes(b)
            if not DRY:
                notify("Atom Plasma didn't update", msg, icon="dialog-warning")
    finally:
        try:
            check(do_fetch=False)
        except Exception as e:      # (a failed re-check must not hide the update's own result)
            log(f"re-check: {e}")
    return util.load_json(PROGRESS, {})


def restore_changes(b):
    """Put stashed changes back on top (applying the backup's own commit so an unrelated user stash is never popped)."""
    if b.get("changes"):
        r = git("stash", "apply", b["changes"])
        if r.returncode:
            log(f"stash apply {b['changes']}: {(r.stderr or r.stdout).strip()[-200:]}")


def restore(b):
    """Back to the build `b` recorded: its commit (on its branch), its changes, its install."""
    was = b.get("was") or BRANCH
    if was in ("HEAD", ""):
        git("checkout", "-f", b["head"], check=True)
    else:
        git("checkout", "-f", "-B", was, b["head"], check=True)
    restore_changes(b)
    if not DRY:
        sh(sys.executable, str(ROOT / "rice.py"), "install", timeout=1800)
        restart_shell()


def rollback():
    b = util.load_json(BACKUP_FILE, {})
    if not b:
        return "no update to undo"
    restore(b)
    check(do_fetch=False)
    return f"back to {b.get('version') or b['head'][:7]}"


# ---------------------------------------------------------------- a fresh install (install.sh)
def fresh():
    """After install.sh cloned the repo: the newest release on the channel (one with the updater), its
    packages, then rice.py install. Talks to a terminal."""
    print("Atom Plasma: checking this system")
    rels = releases()
    env_chan = (os.environ.get("ATOM_CHANNEL") or "").strip().lower()
    chan = env_chan if env_chan in CHANNELS else channel()
    has = [r for r in rels if git("cat-file", "-e", f"{r['tag']}:atom/updater.py").returncode == 0]
    ok = [r for r in has if allowed(r["version"], chan)]
    pick = ok[-1] if ok else None
    if not pick:
        anyrel = has
        pick = anyrel[-1] if anyrel else None
        if pick:
            print(f"  no {chan} release has the updater yet: installing {pick['version']} ({pick['version'].channel})")
    ref = pick["tag"] if pick else "HEAD"
    reqs = requirements(ref)
    sysc = system_check(reqs)
    for w in sysc["warnings"]:
        print("  note:", w)
    if sysc["blockers"]:
        print("Atom Plasma can't run here:")
        for x in sysc["blockers"]:
            print("  -", x)
        return 1
    need = missing_packages(wanted_packages(reqs, fresh=True)) if sysc["family"] == "arch" else wanted_packages(reqs, fresh=True)
    if need and sysc["family"] != "arch":
        print("Install these first, then run this again:\n  " + " ".join(x["pkg"] for x in need))
        return 1

    class Say:
        def say(self, m): print("  " + m); log(m)

    install_packages(Say(), need, sysc["family"])
    if env_chan in CHANNELS:
        set_channel(env_chan)
    if pick:
        git("checkout", "-f", "-B", BRANCH, pick["tag"], check=True)
        print(f"  Atom Plasma {pick['version']}")
    else:
        print("  no release yet: installing the newest code (a developer copy)")
    build_plugins(Say(), reqs)
    if not DRY:
        r = subprocess.run([sys.executable, str(ROOT / "rice.py"), "install"])
        if r.returncode:
            return r.returncode
    check(do_fetch=False)
    print("\nDone. Log out and back in, then:\n  ~/.config/plasma-rice/rice.py setup    (window chrome, once)\n"
          "  ~/.config/plasma-rice/rice.py random   (a wallpaper: everything themes from it)")
    return 0


def selftest():
    """The shell's QML loads (Atom, Atom.Native) the way plasmashell would: exit 0 or 1."""
    from .doctor import shell_loads
    ok = shell_loads()
    print("ok" if ok else "the shell's QML doesn't load")
    return 0 if ok else 1


# ---------------------------------------------------------------- rice.py update ...
def main(args):
    sub = args[0] if args else "check"
    force = "--force" in args
    if sub == "check":
        print(json.dumps(check(do_fetch="--offline" not in args, notify="--notify" in args)))
    elif sub == "start":
        msg = start(force=force)
        print(json.dumps({"started": not msg, "message": msg}))
    elif sub == "apply":
        if len(args) < 2:
            raise SystemExit("rice.py update apply TAG [--force]")
        res = apply(args[1], force=force)
        sys.exit(0 if res.get("state") == "done" else 1)
    elif sub == "channel":
        set_channel(args[1] if len(args) > 1 else "")
        print(json.dumps(check(do_fetch=False)))
    elif sub == "rollback":
        print(rollback())
    elif sub == "fresh":
        sys.exit(fresh())
    elif sub == "selftest":
        sys.exit(selftest())
    else:
        raise SystemExit(__doc__)
