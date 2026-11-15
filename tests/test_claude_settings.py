"""atom/claude.py: what `rice.py install` does to Claude Code's ~/.claude/settings.json. It adds Clawd's hooks
where they're missing, moves commands that call the scripts' old place (before bin/) there, sets the status
line only when there is none, keeps everything else as it was, and changes nothing the second time."""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from atom import claude  # noqa: E402


def commands(settings, event):
    return [h["command"] for g in settings["hooks"].get(event, []) for h in g["hooks"]]


class ClaudeSettings(unittest.TestCase):
    def test_fresh(self):
        text, done = claude.plan("")
        s = json.loads(text)
        for event, matcher, command, background in claude.wanted():
            self.assertIn(claude.BASE + command, commands(s, event))
        self.assertEqual(s["statusLine"]["command"], claude.BASE + "bin/claude-statusline.sh")
        pre = s["hooks"]["PreToolUse"][0]
        self.assertEqual(pre["matcher"], "*")
        self.assertTrue(pre["hooks"][0]["async"])
        self.assertEqual(claude.plan(text), (None, []))              # once is enough

    def test_without_the_update_check(self):
        s = json.loads(claude.plan("", update_check=False)[0])
        self.assertFalse(any("update-check" in c for c in commands(s, "UserPromptSubmit")))

    def test_old_paths_move_and_the_rest_stays(self):
        old = {
            "model": "opus",
            "hooks": {
                "PreToolUse": [{"matcher": "*", "hooks": [
                    {"type": "command", "command": "~/.config/plasma-rice/clawd-hook.sh pre", "timeout": 5, "async": True},
                    {"type": "command", "command": "my-own-hook.sh"}]}],
                "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "$HOME/.config/plasma-rice/ask.sh --remind"}]}],
            },
            "statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "padding": 0},
        }
        text, done = claude.plan(json.dumps(old, indent=2))
        s = json.loads(text)
        self.assertEqual(s["model"], "opus")
        self.assertEqual(commands(s, "PreToolUse"), ["~/.config/plasma-rice/bin/clawd-hook.sh pre", "my-own-hook.sh"])
        self.assertIn("$HOME/.config/plasma-rice/bin/ask.sh --remind", commands(s, "UserPromptSubmit"))
        self.assertEqual(sum("ask.sh" in c for c in commands(s, "UserPromptSubmit")), 1)   # moved, not added again
        self.assertEqual(s["statusLine"]["command"], "~/.claude/statusline.sh")            # yours stays
        self.assertTrue(any(d.startswith("moved to bin/") for d in done))

    def test_not_an_object(self):
        with self.assertRaises(ValueError):
            claude.plan("[1, 2]")
        with self.assertRaises(ValueError):
            claude.plan("{broken")


if __name__ == "__main__":
    unittest.main()
