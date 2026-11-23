"""`rice.py manager`: what Atom Manager (the launcher's settings page) shows, as one JSON.

    rice.py manager            the version, whether it's up to date (as of the last check), the machine,
                               the features, the credits, what's new; quick and offline
    rice.py manager check      the same after asking the repo's home for news (git fetch, read-only for your
                               files: it only moves origin/main)
    rice.py manager doctor     `rice.py doctor`'s checks as JSON (slower: it loads the shell offscreen)

Update state: the updater (to come) writes ~/.local/state/rice/update.json {checked, latest, behind,
critical, summary}; until then the state comes from git: how far origin/main (as last fetched) is ahead of
this checkout. `critical` (a security fix) is only ever set by that file; the launcher shows a banner by its
settings button while it's true. Each run leaves that button's state in ~/.cache/rice/manager-status.json."""
import json
import os
import re
import shutil
import time
from pathlib import Path

from . import caps, util
from .util import CACHE, ROOT, STATE

UPDATE_STATE = STATE / "update.json"
STATUS = CACHE / "manager-status.json"     # what the launcher's settings button shows (a dot, the critical banner)
CREDITS = ROOT / "atom/data/credits.json"
SUPPORTED_PLASMA = "6.8"                # the minor version the shell is built and tested on


def _git(*args, timeout=20):
    r = util.run("git", "-C", str(ROOT), *args, quiet=True, timeout=timeout)
    return r.stdout.strip() if r.returncode == 0 else ""


def https_url(url):
    """git@github.com:owner/repo.git -> https://github.com/owner/repo (anyone can fetch a public repo this way)."""
    m = re.match(r"^(?:ssh://)?git@([^:/]+)[:/](.+?)(?:\.git)?/?$", url)
    if m:
        return f"https://{m.group(1)}/{m.group(2)}"
    return re.sub(r"\.git/?$", "", url)


def repo():
    """The checkout: version, commit, how it stands against origin/main (as last fetched)."""
    import atom
    out = {"version": atom.__version__, "git": False}
    if not (ROOT / ".git").exists():
        return out
    remote = _git("remote", "get-url", "origin")
    head = _git("rev-parse", "--short", "HEAD")
    upstream = "origin/main" if _git("rev-parse", "--verify", "--quiet", "origin/main") else ""
    behind = ahead = 0
    if upstream:
        counts = _git("rev-list", "--left-right", "--count", f"HEAD...{upstream}").split()
        if len(counts) == 2:
            ahead, behind = int(counts[0]), int(counts[1])
    fetched = 0
    for f in (ROOT / ".git/FETCH_HEAD", ROOT / ".git/refs/remotes/origin/main"):
        try:
            fetched = max(fetched, int(f.stat().st_mtime))
        except OSError:
            pass
    latest = _git("describe", "--tags", "--abbrev=0", upstream) if upstream else ""
    out.update({
        "git": True,
        "commit": head,
        "date": _git("log", "-1", "--format=%cs"),
        "branch": _git("rev-parse", "--abbrev-ref", "HEAD"),
        "tag": _git("describe", "--tags", "--abbrev=0"),
        "latestTag": latest,
        "dirty": bool(_git("status", "--porcelain", "--untracked-files=no")),
        "ahead": ahead,
        "behind": behind,
        "fetched": fetched,
        "url": https_url(remote) if remote else "",
    })
    return out


def fetch():
    """Ask the repo's home what's new: moves origin/main only (your files and branch stay as they are). Over
    https, so it needs no key and never prompts."""
    remote = _git("remote", "get-url", "origin")
    if not remote:
        return "no remote"
    env_url = https_url(remote)
    r = util.run("git", "-C", str(ROOT), "-c", "credential.helper=", "fetch", "--quiet", "--no-tags",
                 env_url + ".git", "+refs/heads/main:refs/remotes/origin/main", quiet=True, timeout=40)
    if r.returncode == 0:
        util.run("git", "-C", str(ROOT), "fetch", "--quiet", "--tags", env_url + ".git", quiet=True, timeout=40)
        return ""
    return (r.stderr or r.stdout).strip().splitlines()[-1:][0] if (r.stderr or r.stdout).strip() else "couldn't reach it"


def update_state(rp):
    """What the page and the banner show. The updater's file wins when it's newer than the last fetch."""
    st = util.load_json(UPDATE_STATE, {}) or {}
    mine, fetched = int(st.get("checked", 0) or 0), int(rp.get("fetched", 0) or 0)
    behind = int(st.get("behind", 0) or 0) if st and mine >= fetched else int(rp.get("behind", 0) or 0)
    checked = max(mine, fetched)
    return {
        "checked": checked,
        "behind": behind,
        "available": behind > 0,
        "critical": bool(st.get("critical")) and behind > 0,
        "summary": st.get("summary", ""),
        "latest": st.get("latest") or rp.get("latestTag", ""),
    }


def system():
    """The machine, as a bug report would want it (kinfo when it's there)."""
    info = {}
    if shutil.which("kinfo"):
        r = util.run("kinfo", quiet=True, timeout=10)
        for line in r.stdout.splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                info[k.strip()] = v.strip()
    osr = {}
    try:
        for line in Path("/etc/os-release").read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                osr[k] = v.strip().strip('"')
    except OSError:
        pass
    plasma = info.get("KDE Plasma Version", "")
    if not plasma:
        r = util.run("plasmashell", "--version", quiet=True, timeout=10)
        plasma = r.stdout.strip().split()[-1] if r.stdout.strip() else ""
    gpus = [v for k, v in sorted(info.items()) if k.startswith("Graphics Processor")]
    return {
        "os": osr.get("PRETTY_NAME") or info.get("Operating System", ""),
        "plasma": plasma,
        "frameworks": info.get("KDE Frameworks Version", ""),
        "qt": info.get("Qt Version", ""),
        "kernel": info.get("Kernel Version", "") or os.uname().release,
        "session": info.get("Graphics Platform", "") or os.environ.get("XDG_SESSION_TYPE", "").capitalize(),
        "cpu": info.get("Processors", ""),
        "memory": info.get("Memory", ""),
        "gpus": gpus,
        "supportedPlasma": SUPPORTED_PLASMA,
        "supported": plasma == SUPPORTED_PLASMA or plasma.startswith(SUPPORTED_PLASMA + "."),
    }


def features(cfg=None):
    cfg = util.settings() if cfg is None else cfg
    found = caps.found()
    out = []
    for name, (needs, what) in caps.FEATURES.items():
        setting = str((cfg.get("features") or {}).get(name, "auto")).lower()
        missing = [n for n in needs if not found.get(n)]
        if name == "keyboard_lights" and not (found["asus_keyboard"] or found["razer"]):
            missing = ["an ASUS or Razer keyboard"]
        out.append({"id": name, "on": caps.feature(name, cfg), "setting": setting, "what": what, "missing": missing})
    return out


def contributors():
    """Everyone in the history: authors and Co-Authored-By trailers, by name (never their addresses)."""
    log = _git("log", "--format=%aN%x1f%(trailers:key=Co-Authored-By,valueonly,separator=%x1e)%x1d", timeout=30)
    count = {}
    for rec in log.split("\x1d"):
        rec = rec.strip()
        if not rec:
            continue
        author, _, trailers = rec.partition("\x1f")
        names = {author.strip()} | {re.sub(r"\s*<[^>]*>\s*$", "", t).strip() for t in trailers.split("\x1e") if t.strip()}
        for n in names:
            if not n:
                continue
            n = "Claude" if n.startswith("Claude") else n
            count[n] = count.get(n, 0) + 1
    people = sorted(count.items(), key=lambda kv: -kv[1])
    return [{"name": n, "commits": c, "role": "AI pair programmer (Anthropic)" if n == "Claude" else "Author" if i == 0 else "Contributor"}
            for i, (n, c) in enumerate(people)]


def credits():
    data = util.load_json(CREDITS, {"groups": []}) or {"groups": []}
    pkgs = sorted({it["pkg"] for g in data["groups"] for it in g["items"] if it.get("pkg")})
    have = {}
    if pkgs and shutil.which("pacman"):
        r = util.run("pacman", "-Q", *pkgs, quiet=True, timeout=15)
        for line in r.stdout.splitlines():
            p = line.split()
            if len(p) == 2:
                have[p[0]] = re.sub(r"-[^-]+$", "", p[1])         # (without the pkgrel)
    for g in data["groups"]:
        for it in g["items"]:
            if it.get("pkg"):
                it["version"] = have.get(it["pkg"], "")
                it["installed"] = it["pkg"] in have if shutil.which("pacman") else None
            elif it.get("path"):
                it["installed"] = Path(it["path"]).expanduser().exists()
    return data["groups"]


def changelog(upstream=False, sections=2):
    """CHANGELOG.md's newest sections: [{version, groups: [{title, items}]}] (origin/main's when it's ahead)."""
    text = _git("show", "origin/main:CHANGELOG.md") if upstream else ""
    if not text:
        try:
            text = (ROOT / "CHANGELOG.md").read_text()
        except OSError:
            return []
    out, cur, grp, item = [], None, None, None
    for line in text.splitlines():
        if line.startswith("## "):
            if len(out) >= sections:
                break
            cur = {"version": line[3:].strip(), "groups": []}
            out.append(cur)
            grp = item = None
        elif cur is None:
            continue
        elif (m := re.match(r"^\*\*(.+?)\*\*\s*(.*)$", line.strip())):
            grp = {"title": m.group(1), "note": m.group(2).strip("() "), "items": []}
            cur["groups"].append(grp)
            item = None
        elif line.startswith("- "):
            if grp is None:
                grp = {"title": "", "note": "", "items": []}
                cur["groups"].append(grp)
            item = line[2:].strip()
            grp["items"].append(item)
        elif line.startswith("  ") and grp is not None and grp["items"] and line.strip():
            grp["items"][-1] += " " + line.strip()
    for sec in out:
        for g in sec["groups"]:
            g["items"] = [re.sub(r"`([^`]*)`", r"\1", i) for i in g["items"]]
    return out


def info(cfg=None):
    rp = repo()
    up = update_state(rp)
    util.save_json(STATUS, {"version": rp["version"], "available": up["available"], "behind": up["behind"],
                            "critical": up["critical"], "checked": up["checked"]})
    return {
        "repo": rp,
        "update": up,
        "system": system(),
        "features": features(cfg),
        "contributors": contributors() if rp.get("git") else [],
        "credits": credits(),
        "changelog": changelog(upstream=up["available"]),
        "license": "GPL-3.0-or-later",
        "now": int(time.time()),
    }


def doctor():
    from . import doctor as doc
    rows = [{"ok": bool(ok), "what": what, "fix": "" if ok else fix} for ok, what, fix in doc.checks()]
    return {"checks": rows, "bad": sum(not r["ok"] for r in rows), "now": int(time.time())}


def main(args):
    sub = args[0] if args else "info"
    if sub == "check":
        err = fetch()
        out = info()
        out["checkError"] = err
        print(json.dumps(out))
    elif sub == "doctor":
        print(json.dumps(doctor()))
    elif sub == "info":
        print(json.dumps(info()))
    else:
        raise SystemExit("rice.py manager [check|doctor]")
