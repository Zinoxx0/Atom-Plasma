"""Claude Code and the rice. Clawd learns what Claude Code is doing from its hooks (bin/clawd-hook.sh writes
~/.cache/clawd/activity.json), and the usage rings read ~/.cache/claude-usage.json, which Claude Code's status
line writes (bin/claude-statusline.sh). Both are set in ~/.claude/settings.json: `rice.py install` adds the
hooks that are missing, and sets the status line only when there is none (yours stays; it then needs to write
that file too). Commands that still call the rice's scripts where they were before bin/ are moved there.
`rice.py doctor` says what's missing."""
import json
import re

from .util import HOME

SETTINGS = HOME / ".claude/settings.json"
BASE = "~/.config/plasma-rice/"             # (install links a clone kept elsewhere there)

# (event, matcher, command after BASE, async): Clawd's hooks, then the reminders Claude gets with a prompt
# while a check-in (bin/ask.sh) or an important update (bin/update-check.py) waits for the user
HOOKS = [
    ("UserPromptSubmit", None, "bin/clawd-hook.sh prompt", True),
    ("PreToolUse", "*", "bin/clawd-hook.sh pre", True),
    ("PostToolUse", "*", "bin/clawd-hook.sh post", True),
    ("Notification", None, "bin/clawd-hook.sh notify", True),
    ("PreCompact", None, "bin/clawd-hook.sh compact", True),
    ("Stop", None, "bin/clawd-hook.sh stop", True),
    ("SessionEnd", None, "bin/clawd-hook.sh end", True),
    ("UserPromptSubmit", None, "bin/ask.sh --remind", False),
]
UPDATE_HOOK = ("UserPromptSubmit", None, "bin/update-check.py --remind", False)
STATUS_LINE = {"type": "command", "command": BASE + "bin/claude-statusline.sh", "padding": 0}

# the scripts Claude Code's settings may call at the repo's root, from before they moved to bin/
_OLD = re.compile(r"(plasma-rice/)(clawd-hook\.sh|clawd-intent\.py|ask\.sh|update-check\.py|claude-statusline\.sh)\b")


def wanted(update_check=True):
    return HOOKS + ([UPDATE_HOOK] if update_check else [])


def _moved(command):
    return _OLD.sub(r"\1bin/\2", command)


def _has(settings, event, command):
    tail = "plasma-rice/" + command
    return any(tail in h.get("command", "") for g in settings.get("hooks", {}).get(event, [])
               for h in g.get("hooks", []))


def plan(text, update_check=True):
    """What `install` does to the settings file's TEXT ("" when there's none): (new text, or None when it stays
    as it is; [what changed]). Raises ValueError when the file isn't a JSON object."""
    settings = json.loads(text) if text.strip() else {}
    if not isinstance(settings, dict):
        raise ValueError("not a JSON object")
    done = []
    for groups in settings.get("hooks", {}).values():
        for g in groups:
            for h in g.get("hooks", []):
                if isinstance(h.get("command"), str) and _moved(h["command"]) != h["command"]:
                    done.append(f"moved to bin/: {h['command']}")
                    h["command"] = _moved(h["command"])
    for event, matcher, command, background in wanted(update_check):
        if _has(settings, event, command):
            continue
        hook = {"type": "command", "command": BASE + command, "timeout": 5}
        if background:
            hook["async"] = True
        group = ({"matcher": matcher} if matcher else {}) | {"hooks": [hook]}
        settings.setdefault("hooks", {}).setdefault(event, []).append(group)
        done.append(f"hook {event}: {command}")
    line = settings.get("statusLine")
    if not line:
        settings["statusLine"] = dict(STATUS_LINE)
        done.append("status line: bin/claude-statusline.sh")
    elif isinstance(line.get("command"), str) and _moved(line["command"]) != line["command"]:
        done.append(f"moved to bin/: {line['command']}")
        line["command"] = _moved(line["command"])
    if not done:
        return None, []
    return json.dumps(settings, indent=2, ensure_ascii=False) + "\n", done


def missing(update_check=True):
    """What doctor reports: the hooks that aren't there (or still call the old paths)."""
    try:
        new, done = plan(SETTINGS.read_text() if SETTINGS.exists() else "", update_check)
    except (OSError, ValueError):
        return ["~/.claude/settings.json can't be read as JSON"]
    return done


def status_line_is_ours():
    try:
        line = json.loads(SETTINGS.read_text()).get("statusLine") or {}
    except (OSError, ValueError, AttributeError):
        return False
    return "claude-statusline.sh" in str(line.get("command", ""))
