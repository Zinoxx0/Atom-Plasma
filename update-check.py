#!/usr/bin/env python3
"""Update check: every evening at 20:00 a headless Claude Code reviews the updates CachyOS has waiting
and, ONLY when one is very important (a big measured performance gain, a critical bug fix that hits
this PC, a critical security patch), the desktop Clawd holds up an "Important Cachy update!" bubble
with the reason under the clock. Nothing is ever installed.

    update-check.py              when the next check runs, what the last one found, the open notice
    update-check.py --force      review every waiting update now (raises the notice if it finds
                                 something new); the 20:00 check still runs
    update-check.py --dry-run    review every waiting update now and print the report: no notice, no state
    update-check.py --status     print the open notice as JSON ("none" if there is none)
    update-check.py --ack        mark it seen (a click on Clawd's bubble)
    update-check.py --clear      drop it
    update-check.py --remind     for Claude Code's UserPromptSubmit hook: while a notice is open, tell
                                 Claude about it and where the report is
    update-check.py --scheduled  the 20:00 timer: reviews the updates that are new since the last check
    update-check.py --tidy       the hourly timer: puts away a notice once its updates are installed, and
                                 retries a 20:00 check that failed or waited for Claude usage, until midnight

How it decides: the code gathers the waiting updates (checkupdates, paru -Qua), the Arch security
tracker advisories they fix, the latest Arch and CachyOS news and the held packages, and picks the MUST
CHECK items: watched packages (WATCH) with a new upstream version, and held packages past their skipped
version. Claude (web tools only) has to look each one up and name its source; a run that made no lookups
is asked once more. Its verdict, plus the hold rule (a held package's next version always raises the
notice), decides. The report adds the lookups Claude really made (read from its run, not its word), any
must-check item it gave no source for, and every waiting update. A notice never repeats for the same
upstream versions.

The notice is ~/.local/state/rice/update.json (the desk widget watches it with ClaudeAsk.qml, like
ask.sh's check-ins); ~/.local/state/rice/update-check/ holds report.md, state.json, prompt.txt (what
Claude was given) and last-output.jsonl (its whole run).
settings.json "update_check": {"model": "sonnet", "holds": {name: {"skip", "why"}}}.
A hold is a package kept back with IgnorePkg because one version broke something here: while the
installed one is older than "skip", a waiting version newer than "skip" always raises a notice.
"""
import fcntl
import hashlib
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
STATE_FILE = DIR / "state.json"
CLAUDE = Path.home() / ".local/bin/claude"
TITLE = "Important Cachy update!"
TIMER = "atom-plasma-update-check.timer"
TRACKER = "https://security.archlinux.org/issues/all.json"
FEEDS = (("Arch", "https://archlinux.org/feeds/news/", 5), ("CachyOS", "https://cachyos.org/rss.xml", 3))
MODES = {"scheduled": "the 20:00 check", "forced": "run by hand", "dry": "dry run"}

# watched packages: a new upstream version of any of these always gets looked up, one lookup per family
# (named after its shortest waiting member); the first family that matches a package takes it
WATCH = (
    ("firmware", r"linux-firmware(-.+)?"),
    ("microcode", r"(amd|intel)-ucode"),
    ("LTS kernel", r"linux(-cachyos)?-lts(-headers|-nvidia-open)?"),
    ("kernel", r"linux(-cachyos)?(-headers|-nvidia-open)?"),
    ("nvidia", r"(lib32-)?nvidia-utils|(lib32-)?opencl-nvidia|nvidia-settings"),
    ("mesa", r"(lib32-)?(mesa|vulkan-radeon)"),
    ("plasma", r"kwin|plasma-workspace|plasma-desktop|kscreenlocker|plasma-login-manager|xdg-desktop-portal-kde"),
    ("qt", r"qt6-(base|declarative|wayland)"),
    ("systemd", r"(lib32-)?systemd(-libs)?"),
    ("glibc", r"(lib32-)?glibc"),
    ("openssl", r"(lib32-)?openssl"),
    ("openssh", r"openssh"),
    ("sudo", r"sudo"),
    ("polkit", r"polkit"),
    ("nss", r"(lib32-)?nss"),
    ("gnutls", r"(lib32-)?gnutls"),
    ("curl", r"(lib32-)?curl"),
    ("firefox", r"firefox"),
    ("pipewire", r"(lib32-)?pipewire(-.+)?|wireplumber"),
    ("bluez", r"bluez(-libs|-utils)?"),
    ("xwayland", r"xorg-xwayland"),
    ("wine", r"wine(-cachyos.*)?|proton-cachyos.*|(lib32-)?vkd3d.*|dxvk.*"),
    ("gamescope", r"gamescope"),
)

# CachyOS kernels carry the same upstream versions as Arch's, so the tracker's kernel advisories apply
ALIASES = {"linux": ("linux-cachyos",), "linux-lts": ("linux-cachyos-lts",)}

PROMPT = """You are Atom Plasma's update check, running unattended on the user's PC (Thorfinn, CachyOS).
Your memory file describes the machine and what has been going on with it. Today is {date}.
You only advise: nothing gets installed by you.
{scope}

Updates to judge, as "name old -> new". (AUR) marks AUR packages; [rebuild] marks the same upstream
version rebuilt or repackaged (only the pkgrel changed):
{updates}
{seen}
Arch security tracker advisories that these updates fix:
{security}
(The tracker is sparse and slow: few recent CVEs ever reach it. "none" is NOT evidence that an update
carries no security fix.)

Recent Arch and CachyOS news (manual interventions are announced here):
{news}

Held back on purpose (IgnorePkg in /etc/pacman.conf) because one version broke something here,
as "name: installed, skipped version, why":
{holds}

MUST CHECK: watched packages with a new upstream version, and held packages past their skipped version.
Before you decide, look up each line with WebSearch and WebFetch (its release notes, changelog or
security advisories for the versions shown; the project's own pages beat news sites), then give each
line ONE entry in `checked`, named after its first package (the packages after "with" share it):
{must}

Decide whether ANY of the updates to judge is VERY important for this user to install soon. The user
updates when they like and is wary of updates that break things, so the bar is high. It counts only if
one holds:
- a critical or high-severity security fix in software this PC actually runs or exposes (the kernel,
  browsers, openssh, sudo, glibc, openssl, nss, systemd, network-facing services...), above all if it
  is exploited in the wild;
- a fix for a serious bug that hits this machine: crashes, data loss, broken boot, display, input,
  audio or network, or the NVIDIA, KWin or Plasma problems your memory mentions;
- a big, measured performance gain for this hardware or for gaming (not a "may be faster");
- a held package waiting at a version NEWER than the one skipped: the user is waiting for it. Say in
  the message whether its release notes fix the problem, and in the caveat that its IgnorePkg line
  has to come out of /etc/pacman.conf first. A held package waiting at the skipped version doesn't count.
Routine version bumps, rebuilds, small fixes and new features do NOT count, and neither does anything
you still can't back with a changelog or an advisory after looking. When in doubt after looking, it is
not important. Beyond the MUST CHECK list, look things up only for updates that could plausibly qualify.

If something qualifies, also say whether installing it needs care (an Arch or CachyOS news manual
intervention, the plugin rebuild your memory describes for Plasma upgrades, a known regression).

Reply with:
- important: true or false
- message: when important, what it is and why it matters to this user, in plain words and at most
  130 characters (it is shown under the desktop clock), e.g. "KWin 6.8.1 fixes the stuck cursor in
  Wayland games, and OpenSSL fixes a high-severity hole." Empty when not important.
- packages: the waiting package names that make it important; empty when not important
- caveat: one short sentence about the care installing it needs, or ""
- checked: one entry per MUST CHECK line: name (its first package name, exactly as listed), finding
  (one sentence: what changed that matters on this PC, or that nothing qualifies), source (the URL you
  used; "" when you found nothing, and then say in finding where you looked)
- report: markdown for the user: the verdict and your reasoning, with source links. The checked list,
  the lookups you made and the update list are added to it for you: don't repeat them.
"""

NUDGE = """
Your previous answer to this made no web lookups. Look up every MUST CHECK item before you answer.
"""


def settings():
    cfg = util.settings().get("update_check") or {}
    return {"model": cfg.get("model", "sonnet"), "holds": cfg.get("holds") or {}}


load = util.load_json


def save(path, data):
    util.save_json(path, data, indent=1)


def log(*a):
    print(*a, flush=True)


def today():
    return time.strftime("%Y-%m-%d")


def vercmp(a, b):
    return int(subprocess.run(["vercmp", a, b], capture_output=True, text=True).stdout.strip() or 0)


def upstream(version):
    """'1:6.8.1-2.1' -> '1:6.8.1': the version without its pkgrel (the part after pacman's last '-')."""
    return version.rpartition("-")[0] or version


def rebuild(old, new):
    """Only the pkgrel moved: the same upstream code, rebuilt or repackaged."""
    return upstream(old) == upstream(new)


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


def advisories(groups, ups):
    """Prompt lines for the Arch security tracker groups that the waiting updates fix."""
    hits = []
    for g in groups:
        fixed = g.get("fixed")
        if not fixed or g.get("status") not in ("Fixed", "Vulnerable"):
            continue
        for p in g.get("packages", []):
            for name in (p, *ALIASES.get(p, ())):
                if name in ups:
                    old, new, _ = ups[name]
                    if vercmp(old, fixed) < 0 <= vercmp(new, fixed):
                        hits.append(f"- {name}: {g['name']}, severity {g.get('severity')}, {g.get('type')}, "
                                    f"fixed in {fixed} ({p}), {', '.join(g.get('issues', [])[:6])}")
    return hits


def security(ups):
    try:
        groups = json.loads(get(TRACKER))
    except Exception as e:                          # the tracker is only a hint
        return f"(security tracker unreachable: {e})"
    return "\n".join(advisories(groups, ups)) or "none"


def news():
    items = []
    for name, url, count in FEEDS:
        try:
            root = ET.fromstring(get(url))
        except Exception as e:
            items.append(f"- ({name} news unreachable: {e})")
            continue
        for it in list(root.iter("item"))[:count]:
            items.append(f"- {name}, {it.findtext('pubDate', '')[:16]}: {it.findtext('title', '')} "
                         f"({it.findtext('link', '')})")
    return "\n".join(items) or "none"


def installed(pkgs):
    """{name: version} of the given packages that are installed."""
    r = subprocess.run(["pacman", "-Q", *pkgs], capture_output=True, text=True)
    return dict(line.split()[:2] for line in r.stdout.splitlines() if len(line.split()) >= 2)


def active_holds(holds):
    """The holds still in force, with the installed version added: once a version past the skipped
    one is in, the hold has done its job."""
    have = installed(holds) if holds else {}
    return {p: dict(h, have=have[p]) for p, h in holds.items() if p in have and vercmp(have[p], h["skip"]) < 0}


def family(name):
    """The WATCH family a package belongs to, or None."""
    return next((f for f, pattern in WATCH if re.fullmatch(pattern, name)), None)


def must_check(ups, holds):
    """What Claude has to look up, as [(name, prompt line)]: each watched family with a new upstream
    version waiting, then each held package waiting past its skipped version."""
    families = {}
    for name, (old, new, _) in sorted(ups.items()):
        if not rebuild(old, new) and family(name):
            families.setdefault(family(name), []).append(name)
    out = []
    for label, _ in WATCH:
        if label in families:
            names = families[label]
            lead = min(names, key=lambda n: (len(n), n))
            rest = ", ".join(n for n in names if n != lead)
            out.append((lead, f"- {lead} {ups[lead][0]} -> {ups[lead][1]} ({label}" +
                        (f"; with {rest})" if rest else ")")))
    watched = {n for names in families.values() for n in names}
    for p, h in sorted(holds.items()):
        if p in ups and p not in watched and vercmp(ups[p][1], h["skip"]) > 0:
            out.append((p, f"- {p} {h['have']} -> {ups[p][1]} (held: skipped {h['skip']}; {h.get('why', '')})"))
    return out


def apply_holds(verdict, ups, holds):
    """Make sure a held package's next version raises the notice even if Claude didn't flag it."""
    fresh = {p: ups[p][1] for p, h in holds.items() if p in ups and vercmp(ups[p][1], h["skip"]) > 0}
    flagged = verdict.get("packages", []) if verdict.get("important") else []
    missed = [p for p in fresh if p not in flagged]
    if not missed:
        return verdict
    note = "; ".join(f"{p} {fresh[p]} is out, past the {holds[p]['skip']} you skipped" for p in missed)
    if flagged and verdict.get("message"):
        verdict["message"] += f" Also: {note}."
        verdict["packages"] = flagged + missed
    else:
        verdict.update(important=True, message=note[0].upper() + note[1:] + ".", packages=missed)
    verdict["caveat"] = verdict.get("caveat") or "Remove its IgnorePkg line from /etc/pacman.conf to install it."
    verdict["report"] = verdict.get("report", "") + f"\n\nHeld package with a newer version: {note}."
    return verdict


# ---------- asking Claude ----------
def update_line(name, update):
    old, new, src = update
    return f"{name} {old} -> {new}" + (" (AUR)" if src == "aur" else "") + (" [rebuild]" if rebuild(old, new) else "")


def build_prompt(ups, new, holds, security_text, news_text, date):
    """(prompt, must-check items) for the updates in `new` (names), with the rest of `ups` as context."""
    must = must_check({n: ups[n] for n in new}, holds)
    seen = sorted(set(ups) - set(new))
    scope = ("This is a full review of every waiting update." if not seen else
             f"This is the daily check: {len(new)} of the {len(ups)} waiting updates are new since the last "
             "check, and only those are yours to judge. The others were reviewed in an earlier check.")
    held = [f"- {p}: {h['have']}, skipped {h['skip']}, {h.get('why', '')}" for p, h in sorted(holds.items())]
    prompt = PROMPT.format(
        date=date, scope=scope,
        updates="\n".join(update_line(n, ups[n]) for n in sorted(new)),
        seen=(f"\nAlso waiting, reviewed in an earlier check (context only: don't judge them again):\n"
              f"{', '.join(f'{n} {ups[n][1]}' for n in seen)}\n" if seen else ""),
        security=security_text, news=news_text, holds="\n".join(held) or "none",
        must="\n".join(line for _, line in must) or "(nothing: no watched package has a new upstream version)")
    return prompt, must


def schema(names):
    return {
        "type": "object",
        "properties": {
            "important": {"type": "boolean"},
            "message": {"type": "string"},
            "packages": {"type": "array", "items": {"type": "string", "enum": sorted(names)}},
            "caveat": {"type": "string"},
            "checked": {"type": "array", "items": {
                "type": "object",
                "properties": {"name": {"type": "string"}, "finding": {"type": "string"},
                               "source": {"type": "string"}},
                "required": ["name", "finding", "source"]}},
            "report": {"type": "string"},
        },
        "required": ["important", "message", "packages", "caveat", "checked", "report"],
    }


def lookups(events):
    """The web lookups a run really made, from its event stream: ["search: ...", "fetch: ..."]."""
    out = []
    for e in events:
        if e.get("type") != "assistant":
            continue
        for b in e.get("message", {}).get("content", []):
            if b.get("type") == "tool_use" and b.get("name") == "WebSearch":
                out.append(f"search: {b.get('input', {}).get('query', '')}")
            elif b.get("type") == "tool_use" and b.get("name") == "WebFetch":
                out.append(f"fetch: {b.get('input', {}).get('url', '')}")
    return out


def run_claude(prompt, model, names):
    """One headless Claude Code run: (verdict, lookups made, its result event)."""
    env = dict(os.environ, PATH=f"{CLAUDE.parent}:{os.environ.get('PATH', '/usr/bin:/bin')}")
    # web tools only, nothing else (no shell, no file edits, no MCP connectors); the prompt goes in on
    # stdin; run from its own folder so no project's files come along; the event stream shows the lookups;
    # no hooks, so Clawd doesn't act out a conversation the user never had
    cmd = [str(CLAUDE), "-p", "--model", model, "--output-format", "stream-json", "--verbose",
           "--json-schema", json.dumps(schema(names)), "--tools", "WebSearch,WebFetch",
           "--allowedTools", "WebSearch", "WebFetch", "--permission-mode", "dontAsk",
           "--strict-mcp-config", "--no-session-persistence", "--settings", '{"disableAllHooks": true}']
    r = subprocess.run(cmd, input=prompt, capture_output=True, text=True, cwd=DIR, env=env, timeout=900)
    (DIR / "last-output.jsonl").write_text(r.stdout)
    events = []
    for line in r.stdout.splitlines():
        try:
            events.append(json.loads(line))
        except ValueError:
            pass
    result = next((e for e in reversed(events) if e.get("type") == "result"), {})
    if r.returncode != 0 or not result or result.get("is_error"):
        raise RuntimeError(f"claude exited {r.returncode}: {(r.stderr or str(result.get('result', ''))).strip()[-500:]}")
    verdict = result.get("structured_output")
    if verdict is None:                             # fall back to the text answer
        text = re.sub(r"^```(json)?|```$", "", (result.get("result") or "").strip(), flags=re.M)
        verdict = json.loads(text)
    return verdict, lookups(events), result


def ask_claude(prompt, must, model, names):
    """Claude's verdict and the lookups it made; a run that skipped the must-check lookups goes again once."""
    DIR.mkdir(parents=True, exist_ok=True)
    (DIR / "prompt.txt").write_text(prompt)
    verdict, found, result = run_claude(prompt, model, names)
    if must and not found:
        log("the run made no web lookups: asking once more")
        verdict, found, result = run_claude(prompt + NUDGE, model, names)
    log(f"{len(found)} lookups, {result.get('num_turns')} turns, {(result.get('duration_ms') or 0) / 1000:.0f} s, "
        f"${result.get('total_cost_usd') or 0:.2f}")
    return verdict, found


def render_report(stamp, mode, ups, new, verdict, must, found):
    """report.md: Claude's verdict, then what the code knows: the items checked, the must-check ones
    without a source, the lookups really made and every waiting update."""
    seen = set(ups) - set(new)
    leads = {name for name, _ in must}
    covered = {family(name) for name in leads} - {None}
    # one entry per must-check line: entries Claude made for the rest of a family fold into its first
    checked = [c for c in verdict.get("checked") or []
               if c.get("name", "").strip() in leads or family(c.get("name", "").strip()) not in covered]
    sourced = [c.get("name", "").strip() for c in checked if c.get("source", "").strip()]
    unsourced = [line for name, line in must if not any(s == name or s.startswith(name + " ") for s in sourced)]
    out = [f"# Update check, {stamp} ({MODES[mode]})", "",
           f"{len(ups)} updates waiting" + (f", {len(new)} of them new since the last check" if seen else "") + ".",
           "", verdict.get("report", "").strip(), ""]
    if checked:
        out += ["## Checked", ""]
        out += [f"- **{c.get('name', '')}**: {c.get('finding', '')}" +
                (f" ([source]({c['source']}))" if c.get("source") else " (no source)") for c in checked]
        out.append("")
    if unsourced:
        out += ["## Must-check items with no source", ""] + unsourced + [""]
    out += ["## Lookups made", ""]
    out += [f"- {x}" for x in found] or ["- none" + (": the verdict rests on the package list alone." if must else ".")]
    out += ["", "## Updates waiting", ""]
    out += [f"- {update_line(n, ups[n])}" + (" (new)" if seen and n in new else "") for n in sorted(ups)]
    return "\n".join(out) + "\n"


# ---------- the check ----------
def notice_keys(message, pkgs):
    """What a notice is about, so it never repeats: name=upstream version per flagged package (a rebuild
    of the same version is no news), or the message itself when it names no waiting package."""
    return {f"{p}={upstream(v)}" for p, v in pkgs.items()} or {"msg:" + hashlib.sha1(message.encode()).hexdigest()[:12]}


def told(state):
    """The keys notified so far (older entries carry the whole version, name=pkgver-pkgrel)."""
    return {k.split("=", 1)[0] + "=" + upstream(k.split("=", 1)[1]) if "=" in k else k
            for k in state.get("notified", [])}


def notify(verdict, ups, state):
    if not (verdict.get("important") and verdict.get("message")):
        return
    pkgs = {p: ups[p][1] for p in verdict.get("packages", []) if p in ups}
    keys, done = notice_keys(verdict["message"], pkgs), told(state)
    if keys <= done:
        log("already notified about these versions")
        return
    now = int(time.time())
    save(NOTICE, {"id": now, "title": TITLE, "msg": verdict["message"][:200], "caveat": verdict.get("caveat", ""),
                  "pkgs": pkgs, "report": str(REPORT), "since": now, "ack": 0})
    state["notified"] = (state.get("notified", []) + sorted(keys - done))[-300:]
    body = verdict["message"] + (("\n" + verdict["caveat"]) if verdict.get("caveat") else "")
    subprocess.run(["notify-send", "-a", "Atom Plasma", "-i", "system-software-update",
                    "-h", "string:x-canonical-private-synchronous:rice-update", TITLE, body], check=False)
    log("notice raised")


def check(mode):
    """One check. scheduled: judges the updates that are new since the last check; forced and dry: all
    of them (dry keeps no state, raises no notice and prints the report). False when it couldn't run."""
    cfg = settings()
    ups = pending()
    if ups is None:
        return False
    state = load(STATE_FILE, {})
    keys = {n: f"{n}={v[1]}" for n, v in ups.items()}
    judged = set(state.get("judged", []))
    new = sorted(n for n in ups if mode != "scheduled" or keys[n] not in judged)
    now = int(time.time())
    run = {"at": now, "mode": mode, "updates": len(ups), "new": len(new)}
    if not new:
        log(f"nothing new since the last check ({len(ups)} updates waiting, all reviewed)" if ups else "nothing to update")
        if mode != "dry":
            if not ups:
                REPORT.write_text(f"# Update check, {time.strftime('%Y-%m-%d %H:%M')} ({MODES[mode]})\n\nNothing to update.\n")
            state.update(judged=sorted(keys.values()), last_run=run)
            save(STATE_FILE, state)
        return True

    holds = active_holds(cfg["holds"])
    prompt, must = build_prompt(ups, new, holds, security(ups), news(), today())
    log(f"asking Claude ({cfg['model']}) about {len(new)} of {len(ups)} updates, {len(must)} to look up")
    verdict, found = ask_claude(prompt, must, cfg["model"], list(ups))
    verdict = apply_holds(verdict, {n: ups[n] for n in new}, holds)
    log(json.dumps({k: verdict.get(k) for k in ("important", "message", "packages", "caveat")}, ensure_ascii=False))
    text = render_report(time.strftime("%Y-%m-%d %H:%M"), mode, ups, new, verdict, must, found)
    if mode == "dry":
        print(text)
        return True

    REPORT.write_text(text)
    for old in ("last_try", "verdict"):             # left by the every-2-days version
        state.pop(old, None)
    state.update(judged=sorted(keys.values()), last_run=dict(run, must=len(must), lookups=len(found)),
                 last_verdict={k: verdict.get(k) for k in ("important", "message", "packages", "caveat")})
    notify(verdict, ups, state)
    save(STATE_FILE, state)
    return True


def safe_check(mode):
    try:
        return check(mode)
    except Exception as e:                          # the journal (or the terminal) gets the reason
        log(f"the check failed: {e!r}")
        return False


def mark(**changes):
    """Set (or, with None, drop) top-level keys of state.json."""
    state = load(STATE_FILE, {})
    for k, v in changes.items():
        if v is None:
            state.pop(k, None)
        else:
            state[k] = v
    save(STATE_FILE, state)


def scheduled_check():
    """The day's check; when it can't run now (Claude usage high, a failure) the hourly upkeep retries
    it until midnight."""
    if usage_peak() >= 80:                          # don't spend the user's last bit of Claude usage
        log("Claude usage is high: the check retries hourly until midnight")
        mark(retry=today())
        return True
    ok = safe_check("scheduled")
    mark(retry=None if ok else today())
    if not ok:
        log("it retries hourly until midnight")
    return ok


def tidy():
    """Put away a notice whose updates are installed."""
    n = load(NOTICE)
    if n and installed_all(n.get("pkgs") or {}):
        NOTICE.unlink(missing_ok=True)
        log("the flagged updates are installed: notice cleared")


def installed_all(pkgs):
    """True once every flagged package is installed at the notified version or newer (or is gone)."""
    if not pkgs:
        return False
    have = installed(pkgs)
    return all(p not in have or vercmp(have[p], v) >= 0 for p, v in pkgs.items())


def usage_peak():
    """The fuller Claude usage window, % (the status line caches it; 0 when unknown or reset)."""
    u = load(Path.home() / ".cache/claude-usage.json", {})
    pct = 0
    for key in ("five_hour", "seven_day"):
        w = u.get(key) or {}
        if float(w.get("resets_at") or 0) > time.time():
            pct = max(pct, float(w.get("used_percentage") or 0))
    return pct


# ---------- for people ----------
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


def when(t):
    """'today 20:00' / 'yesterday 20:01' / 'Fri 23 Oct 20:00'."""
    day = time.strftime("%Y-%m-%d", time.localtime(t))
    names = {today(): "today", time.strftime("%Y-%m-%d", time.localtime(time.time() - 86400)): "yesterday",
             time.strftime("%Y-%m-%d", time.localtime(time.time() + 86400)): "tomorrow"}
    return f"{names.get(day) or time.strftime('%a %d %b', time.localtime(t))} {time.strftime('%H:%M', time.localtime(t))}"


def summary():
    """The plain run in a terminal: when the next check is, what the last one found, the open notice."""
    r = subprocess.run(["systemctl", "--user", "show", TIMER, "-p", "NextElapseUSecRealtime", "--value",
                        "--timestamp=unix"], capture_output=True, text=True)
    m = re.match(r"@(\d+)", r.stdout.strip())
    if m:
        left = int(m[1]) - time.time()
        nxt = f"{when(int(m[1]))} (in {int(left // 3600)} h {int(left % 3600 // 60)} min)" if left >= 3600 \
            else f"{when(int(m[1]))} (in {max(0, int(left // 60))} min)"
    else:
        nxt = f"not scheduled ({TIMER} isn't active)"
    state = load(STATE_FILE, {})
    run, v = state.get("last_run"), state.get("last_verdict") or {}
    if not run:
        last = "none yet"
    elif not run["new"]:
        last = f"{when(run['at'])}, {MODES[run['mode']]}: " + \
            (f"nothing new among {run['updates']} waiting updates" if run["updates"] else "nothing to update")
    else:
        last = (f"{when(run['at'])}, {MODES[run['mode']]}: {'IMPORTANT' if v.get('important') else 'not important'}, "
                f"{run['new']} of {run['updates']} updates reviewed, {run.get('lookups', 0)} lookups")
    n = load(NOTICE)
    notice = f"\"{n.get('msg', '')}\"" + (" (seen)" if n.get("ack") else "") if n else "none"
    lines = [("Next check", nxt), ("Last check", last), ("Notice", notice), ("Report", str(REPORT))]
    if state.get("retry") == today():
        lines.insert(1, ("Retrying", "today's 20:00 check didn't finish; the hourly upkeep tries again until midnight"))
    print("\n".join(f"{k:<12}{v}" for k, v in lines))
    print("\nclaupdate --force reviews every waiting update now; --help says more.")


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
    if not arg:
        summary()
        return
    if arg not in ("--scheduled", "--tidy", "--force", "--dry-run"):
        sys.exit(f"unknown option {arg} (--help lists them)")

    DIR.mkdir(parents=True, exist_ok=True)
    lock = open(DIR / "lock", "w")
    try:                                            # the 20:00 check waits its turn; the rest give way
        fcntl.flock(lock, fcntl.LOCK_EX | (0 if arg == "--scheduled" else fcntl.LOCK_NB))
    except BlockingIOError:
        log("a check is already running")
        return
    if arg == "--dry-run":
        sys.exit(0 if safe_check("dry") else 1)
    if arg == "--force":
        sys.exit(0 if safe_check("forced") else 1)
    tidy()
    if arg == "--scheduled":
        sys.exit(0 if scheduled_check() else 1)
    retry = load(STATE_FILE, {}).get("retry")       # --tidy
    if retry == today():
        sys.exit(0 if scheduled_check() else 1)
    if retry:                                       # yesterday's: tonight's check takes over
        mark(retry=None)


if __name__ == "__main__":
    main()
