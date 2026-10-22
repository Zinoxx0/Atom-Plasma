#!/usr/bin/env python3
"""Update check: every couple of days a headless Claude Code reads the updates CachyOS has waiting
and, ONLY when one is very important (a big measured performance gain, a critical bug fix that hits
this PC, a critical security patch), the desktop Clawd holds up an "Important Cachy update!" bubble
with the reason under the clock. Nothing is ever installed.

    update-check.py            what the timer runs (hourly): clears a notice once its updates are
                               installed, and runs the check when the last one is old enough
    update-check.py --force    run the check now (raises the notice if it finds something new)
    update-check.py --dry-run  run the check now and print the verdict: no notice, no state
    update-check.py --status   print the open notice as JSON ("none" if there is none)
    update-check.py --ack      mark it seen (a click on Clawd's bubble)
    update-check.py --clear    drop it
    update-check.py --remind   for Claude Code's UserPromptSubmit hook: while a notice is open, tell
                               Claude about it and where the report is

The notice is ~/.local/state/rice/update.json (the desk widget watches it with ClaudeAsk.qml, like
ask.sh's check-ins); the last report and verdict are in ~/.local/state/rice/update-check/.
settings.json "update_check": {"every_days": 2, "model": "sonnet"}.
"""
import fcntl
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

from atom import util

STATE = util.STATE
NOTICE = STATE / "update.json"
DIR = STATE / "update-check"
REPORT = DIR / "report.md"
CLAUDE = Path.home() / ".local/bin/claude"
TITLE = "Important Cachy update!"

SCHEMA = {
    "type": "object",
    "properties": {
        "important": {"type": "boolean"},
        "message": {"type": "string"},
        "packages": {"type": "array", "items": {"type": "string"}},
        "caveat": {"type": "string"},
        "report": {"type": "string"},
    },
    "required": ["important", "message", "packages", "caveat", "report"],
}

PROMPT = """You are Atom Plasma's update check, running unattended on the user's PC (Thorfinn, CachyOS).
Your memory file describes the machine and what has been going on with it. Today is {date}.
You only advise: nothing gets installed by you.

These updates are waiting (repo packages from checkupdates, then the AUR), as "name old -> new":
{updates}

Updates that fix an Arch security tracker advisory:
{security}

Recent Arch news (manual interventions are announced here):
{news}

Decide whether ANY of these updates is VERY important for this user to install soon. The user updates
when they like and is wary of updates that break things, so the bar is high. It counts only if one holds:
- a critical or high-severity security fix in software this PC actually runs or exposes (the kernel,
  browsers, openssh, sudo, glibc, openssl, systemd, network-facing services...), above all if it is
  exploited in the wild;
- a fix for a serious bug that hits this machine: crashes, data loss, broken boot, display, input,
  audio or network, or the NVIDIA, KWin or Plasma problems your memory mentions;
- a big, measured performance gain for this hardware or for gaming (not a "may be faster").
Routine version bumps, rebuilds, small fixes, new features and anything you can't back with a
changelog or an advisory do NOT count. When unsure, it is not important.

Look up release notes, changelogs or advisories only for the candidates that could plausibly qualify
(kernel, nvidia, mesa, kwin and plasma, systemd, glibc, openssl or openssh, browsers, wine or proton
bits, firmware), with WebSearch and WebFetch. A handful of lookups is enough.

If something qualifies, also say whether installing it needs care (an Arch news manual intervention,
the plugin rebuild your memory describes for Plasma upgrades, a known regression).

Reply with:
- important: true or false
- message: when important, what it is and why it matters to this user, in plain words and at most
  130 characters (it is shown under the desktop clock), e.g. "KWin 6.8.1 fixes the stuck cursor in
  Wayland games, and OpenSSL fixes a high-severity hole." Empty when not important.
- packages: the names (from the list above) that make it important; empty when not important
- caveat: one short sentence about the care installing it needs, or ""
- report: markdown for the user: the verdict, the notable updates you looked at and why they do or
  don't count, with source links
"""


def settings():
    cfg = util.settings().get("update_check") or {}
    return {"every_days": float(cfg.get("every_days", 2)), "model": cfg.get("model", "sonnet")}


load = util.load_json


def save(path, data):
    util.save_json(path, data, indent=1)


def log(*a):
    print(*a, flush=True)


def vercmp(a, b):
    return int(subprocess.run(["vercmp", a, b], capture_output=True, text=True).stdout.strip() or 0)


# ---------- what's waiting ----------
def pending():
    """{name: (old, new, source)}, or None when the repos can't be reached."""
    out = {}
    r = subprocess.run(["checkupdates", "--nocolor"], capture_output=True, text=True)
    if r.returncode not in (0, 2):                  # 2 = nothing to update
        log("checkupdates failed:", r.stderr.strip())
        return None
    a = subprocess.run(["paru", "-Qua", "--color", "never"], capture_output=True, text=True)
    for text, src in ((r.stdout, "repo"), (a.stdout, "aur")):
        for line in text.splitlines():
            m = re.match(r"(\S+) (\S+) -> (\S+)", line.strip())
            if m:
                out[m[1]] = (m[2], m[3], src)
    return out


def get(url, timeout=20):
    req = urllib.request.Request(url, headers={"User-Agent": "atom-plasma-update-check"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def security(ups):
    """Arch security tracker groups that the waiting updates fix."""
    try:
        groups = json.loads(get("https://security.archlinux.org/all.json"))
    except Exception as e:                          # the tracker is only a hint
        return f"(security tracker unreachable: {e})"
    hits = []
    for g in groups:
        fixed = g.get("fixed")
        if not fixed or g.get("status") not in ("Fixed", "Vulnerable"):
            continue
        for p in g.get("packages", []):
            if p in ups:
                old, new, _ = ups[p]
                if vercmp(old, fixed) < 0 <= vercmp(new, fixed):
                    hits.append(f"- {p}: {g['name']}, severity {g.get('severity')}, {g.get('type')}, "
                                f"fixed in {fixed}, {', '.join(g.get('issues', [])[:6])}")
    return "\n".join(hits) or "none"


def news():
    try:
        root = ET.fromstring(get("https://archlinux.org/feeds/news/"))
    except Exception as e:
        return f"(Arch news unreachable: {e})"
    items = []
    for it in root.iter("item"):
        items.append(f"- {it.findtext('pubDate', '')[:16]}: {it.findtext('title', '')} ({it.findtext('link', '')})")
        if len(items) == 5:
            break
    return "\n".join(items) or "none"


# ---------- the check ----------
def ask_claude(ups, model):
    lines = [f"{n} {o} -> {v}" + (" (AUR)" if s == "aur" else "") for n, (o, v, s) in sorted(ups.items())]
    prompt = PROMPT.format(date=time.strftime("%Y-%m-%d"), updates="\n".join(lines),
                           security=security(ups), news=news())
    DIR.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, PATH=f"{CLAUDE.parent}:{os.environ.get('PATH', '/usr/bin:/bin')}")
    # web tools only, nothing else (no shell, no file edits, no MCP connectors); the prompt goes in on
    # stdin; run from its own folder so no project's files come along
    cmd = [str(CLAUDE), "-p", "--model", model, "--output-format", "json",
           "--json-schema", json.dumps(SCHEMA), "--tools", "WebSearch,WebFetch",
           "--allowedTools", "WebSearch", "WebFetch", "--permission-mode", "dontAsk",
           "--strict-mcp-config", "--no-session-persistence"]
    r = subprocess.run(cmd, input=prompt, capture_output=True, text=True, cwd=DIR, env=env, timeout=1800)
    (DIR / "last-output.json").write_text(r.stdout)
    if r.returncode != 0:
        raise RuntimeError(f"claude exited {r.returncode}: {(r.stderr or r.stdout).strip()[-500:]}")
    out = json.loads(r.stdout)
    verdict = out.get("structured_output")
    if verdict is None:                             # fall back to the text answer
        text = re.sub(r"^```(json)?|```$", "", (out.get("result") or "").strip(), flags=re.M)
        verdict = json.loads(text)
    return verdict


def check(dry=False):
    cfg = settings()
    ups = pending()
    if ups is None:
        return False
    if not ups:
        verdict = {"important": False, "message": "", "packages": [], "caveat": "",
                   "report": "Nothing to update."}
    else:
        log(f"asking Claude ({cfg['model']}) about {len(ups)} updates")
        if not dry:                                 # a failed run waits a while before the next try
            state = load(DIR / "state.json", {})
            state["last_try"] = int(time.time())
            save(DIR / "state.json", state)
        verdict = ask_claude(ups, cfg["model"])
    log(json.dumps({k: verdict.get(k) for k in ("important", "message", "packages", "caveat")}, ensure_ascii=False))
    if dry:
        print(verdict.get("report", ""))
        return True

    DIR.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y-%m-%d %H:%M")
    REPORT.write_text(f"# Update check, {stamp}\n\n{len(ups)} updates waiting.\n\n{verdict.get('report', '')}\n")
    state = load(DIR / "state.json", {})
    state.update(last_ok=int(time.time()), verdict=verdict)

    pkgs = {p: ups[p][1] for p in verdict.get("packages", []) if p in ups}
    keys = [f"{p}={v}" for p, v in pkgs.items()]
    told = state.get("notified", [])
    if verdict.get("important") and verdict.get("message") and not (keys and set(keys) <= set(told)):
        now = int(time.time())
        save(NOTICE, {"id": now, "title": TITLE, "msg": verdict["message"][:200], "caveat": verdict.get("caveat", ""),
                      "pkgs": pkgs, "report": str(REPORT), "since": now, "ack": 0})
        state["notified"] = (told + keys)[-300:]
        body = verdict["message"] + (("\n" + verdict["caveat"]) if verdict.get("caveat") else "")
        subprocess.run(["notify-send", "-a", "Atom Plasma", "-i", "system-software-update",
                        "-h", "string:x-canonical-private-synchronous:rice-update", TITLE, body], check=False)
        log("notice raised")
    save(DIR / "state.json", state)
    return True


def installed_all(pkgs):
    """True once every flagged package is installed at the notified version or newer (or is gone)."""
    if not pkgs:
        return False
    r = subprocess.run(["pacman", "-Q", *pkgs], capture_output=True, text=True)
    have = dict(line.split()[:2] for line in r.stdout.splitlines() if len(line.split()) >= 2)
    return all(p not in have or vercmp(have[p], v) >= 0 for p, v in pkgs.items())


def remind():
    sys.stdin.read()
    n = load(NOTICE)
    if not n or n.get("ack"):
        return
    ctx = (f"An Atom Plasma update notice is open (the desktop Clawd holds an \"{n.get('title', TITLE)}\" bubble): "
           f"\"{n.get('msg', '')}\"" + (f" Caveat: {n['caveat']}" if n.get("caveat") else "") +
           f" Packages: {', '.join(n.get('pkgs', {})) or 'see the report'}. Full report with sources: {n.get('report', REPORT)}."
           " Nothing was installed. It clears itself once those packages are installed; if the user dismisses it in chat,"
           " clear it with ~/.config/plasma-rice/update-check.py --clear.")
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": ctx}}))


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "--remind":
        remind()
        return
    if arg == "--status":
        print(NOTICE.read_text() if NOTICE.exists() else "none")
        return
    if arg == "--clear":
        NOTICE.unlink(missing_ok=True)
        return
    if arg == "--ack":
        n = load(NOTICE)
        if n:
            n["ack"] = int(time.time())
            save(NOTICE, n)
        return
    if arg in ("-h", "--help"):
        print(__doc__)
        return

    DIR.mkdir(parents=True, exist_ok=True)
    lock = open(DIR / "lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        log("a check is already running")
        return
    if arg == "--dry-run":
        check(dry=True)
        return
    if arg == "--force":
        sys.exit(0 if check() else 1)

    # the timer: put away a notice whose updates are in, then check when it's time
    n = load(NOTICE)
    if n and installed_all(n.get("pkgs") or {}):
        NOTICE.unlink(missing_ok=True)
        log("the flagged updates are installed: notice cleared")
    state = load(DIR / "state.json", {})
    now = time.time()
    due = max(state.get("last_ok", 0) + settings()["every_days"] * 86400 - 1800, state.get("last_try", 0) + 6 * 3600)
    if now < due:
        if sys.stdout.isatty():                     # run by hand: say why nothing happens
            print(f"Not due yet: the next check is in {(due - now) / 3600:.0f} h. --force checks now.")
        return
    if usage_peak() >= 80:                          # don't spend the user's last bit of Claude usage
        log("Claude usage is high: the check waits")
        return
    sys.exit(0 if check() else 1)


def usage_peak():
    """The fuller Claude usage window, % (the status line caches it; 0 when unknown or reset)."""
    u = load(Path.home() / ".cache/claude-usage.json", {})
    pct = 0
    for key in ("five_hour", "seven_day"):
        w = u.get(key) or {}
        if float(w.get("resets_at") or 0) > time.time():
            pct = max(pct, float(w.get("used_percentage") or 0))
    return pct


if __name__ == "__main__":
    main()
