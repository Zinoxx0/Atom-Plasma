"""Antigravity / Gemini hooks for Atom Plasma.

Registers a named lifecycle hook ("atom-plasma-gemini") in ~/.gemini/config/hooks.json so
bin/gemini-hook.sh updates ~/.cache/gemini/activity.json on SessionStart, PreInvocation,
PostToolUse, PostInvocation and Stop. PreToolUse is intentionally omitted so the hook can never
override Antigravity's tool permission decisions.

All other named hooks in ~/.gemini/config/hooks.json are left completely untouched.
"""
import json

from .util import HOME

HOOKS_FILE = HOME / ".gemini/config/hooks.json"
T3_PROVIDERS = HOME / ".t3/userdata/providers/antigravity"
HOOK_NAME = "atom-plasma-gemini"
BASE = "~/.config/plasma-rice/"


def hook_files():
    """All Antigravity global hooks.json locations on this machine: standard ~/.gemini/config/hooks.json
    plus any T3 Code isolated Antigravity provider config dirs (~/.t3/userdata/providers/antigravity/*/config/)."""
    out = [HOOKS_FILE]
    if T3_PROVIDERS.is_dir():
        for d in sorted(T3_PROVIDERS.iterdir()):
            cfg_dir = d / "config"
            if d.is_dir() and cfg_dir.is_dir():
                out.append(cfg_dir / "hooks.json")
    return out


def spec():
    """The named hook definition installed under HOOK_NAME in ~/.gemini/config/hooks.json."""
    cmd = lambda ev: {"type": "command", "command": f"{BASE}bin/gemini-hook.sh {ev}", "timeout": 5}
    return {
        "enabled": True,
        "SessionStart": [cmd("start")],
        "PreInvocation": [cmd("pre")],
        "PostToolUse": [{"matcher": "*", "hooks": [cmd("post")]}],
        "PostInvocation": [cmd("post")],
        "Stop": [cmd("stop")],
    }


def plan(text, enabled=True):
    """What `install` or `modules enable/disable` does to hooks.json's TEXT ("" when missing):
    returns (new_text or None when unchanged, [descriptions]). Raises ValueError on bad JSON."""
    data = json.loads(text) if text.strip() else {}
    if not isinstance(data, dict):
        raise ValueError("not a JSON object")
    want = spec() if enabled else None
    cur = data.get(HOOK_NAME)
    if enabled:
        if cur == want:
            return None, []
        action = "updated hook" if HOOK_NAME in data else "added hook"
        data[HOOK_NAME] = want
        return json.dumps(data, indent=2, ensure_ascii=False) + "\n", [f"{action} {HOOK_NAME}"]
    if HOOK_NAME not in data:
        return None, []
    del data[HOOK_NAME]
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n", [f"removed hook {HOOK_NAME}"]


def missing():
    """What `rice.py doctor` reports when the Gemini module is on."""
    out = []
    for path in hook_files():
        try:
            _, done = plan(path.read_text() if path.exists() else "", enabled=True)
            out += [f"{path.name}: {d}" for d in done]
        except (OSError, ValueError):
            out.append(f"{path} can't be read as JSON")
    return out
