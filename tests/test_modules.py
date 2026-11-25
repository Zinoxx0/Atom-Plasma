"""Tests for Misc Modules (atom/modules.py), Antigravity hooks (atom/gemini.py, bin/gemini-hook.sh),
Gemini usage alerts, and dynamic meters-island panel ordering."""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from atom import caps, gemini, modules, panel, util  # noqa: E402


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


gem_alerts = _load("gemini_alerts", ROOT / "plasmoids/com.zinoxx.geminiusage/contents/code/alerts.py")
t3_act = _load("t3_activity", ROOT / "bin/t3-activity.py")


class ModuleDiscoveryAndSettings(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.orig_user_dir = modules.USER_DIR
        self.orig_settings = util.SETTINGS
        self.orig_state = util.STATE
        modules.USER_DIR = self.tmp / "user-modules"
        util.SETTINGS = self.tmp / "settings.json"
        util.STATE = self.tmp / "state"

    def tearDown(self):
        modules.USER_DIR = self.orig_user_dir
        util.SETTINGS = self.orig_settings
        util.STATE = self.orig_state
        for f in util._locks.values():
            f.close()
        util._locks.clear()

    def test_builtin_modules_discovered(self):
        mods = {m["id"]: m for m in modules.discover()}
        self.assertIn("claude", mods)
        self.assertIn("gemini", mods)
        self.assertEqual(mods["claude"]["plasmoid"], "com.zinoxx.claudeusage")
        self.assertEqual(mods["gemini"]["plasmoid"], "com.zinoxx.geminiusage")
        self.assertLess(mods["claude"]["order"], mods["gemini"]["order"])
        # Gemini star style choice exists with both variants
        star = next(o for o in mods["gemini"]["schema"] if o["key"] == "star_style")
        self.assertEqual(star["default"], "iridescent")
        self.assertEqual([o["value"] for o in star["options"]], ["iridescent", "google4"])

    def test_custom_user_module_discovery_and_bar_order(self):
        custom = modules.USER_DIR / "chatgpt"
        (custom / "plasmoid").mkdir(parents=True)
        (custom / "plasmoid/metadata.json").write_text('{"KPlugin":{"Id":"com.user.chatgpt"}}')
        (custom / "module.json").write_text(json.dumps({
            "id": "chatgpt",
            "name": "ChatGPT",
            "subtitle": "Codex usage meter",
            "bar_slot": "meters",
            "order": 30,
            "plasmoid": "com.user.chatgpt",
            "config": [{"key": "alerts", "label": "Alerts", "type": "bool", "default": True}],
        }))

        mods = {m["id"]: m for m in modules.discover()}
        self.assertIn("chatgpt", mods)
        self.assertFalse(mods["chatgpt"]["builtin"])
        self.assertTrue(mods["chatgpt"]["plasmoid_path"].endswith("plasmoid"))

        meters = panel.meter_plasmoids(include_disabled=True)
        self.assertEqual(meters, ["com.zinoxx.claudeusage", "com.zinoxx.geminiusage", "com.user.chatgpt"])

        ids = {
            panel.LAUNCHER: 1, panel.TASKS: 2, panel.SHELL: 3, panel.COLORIZER: 4,
            "com.zinoxx.claudeusage": 5, "com.zinoxx.geminiusage": 6, "com.user.chatgpt": 7,
            "com.zinoxx.sysstats": 8, panel.STATUS: 9, panel.TILING: 10,
            "com.zinoxx.session": 11, panel.CLOCK: 12,
            "expanding": 20, "small": [21, 22, 23, 24],
        }
        order = panel.order_for(ids)
        self.assertEqual(order[order.index(5):order.index(8) + 1], [5, 6, 7, 8])

    def test_toggle_and_options_persist_and_sync_with_caps(self):
        self.assertFalse(modules.set_enabled("claude", False, apply_live=False))
        cfg = util.settings()
        self.assertFalse(modules.is_enabled("claude", cfg))
        self.assertFalse(caps.feature("claude", cfg))

        self.assertTrue(modules.set_enabled("gemini", True, apply_live=False))
        self.assertEqual(modules.set_option("gemini", "star_style", "google4", apply_live=False), "google4")
        self.assertEqual(modules.set_option("gemini", "ripples", "false", apply_live=False), False)

        gcfg = modules.module_config("gemini")
        self.assertEqual(gcfg["star_style"], "google4")
        self.assertFalse(gcfg["ripples"])
        self.assertTrue(gcfg["alerts"])

        with self.assertRaises(SystemExit):
            modules.set_option("gemini", "star_style", "neon_rainbow", apply_live=False)
        with self.assertRaises(SystemExit):
            modules.set_option("gemini", "nonexistent", "true", apply_live=False)


class GeminiHooks(unittest.TestCase):
    def test_plan_fresh_idempotent_and_remove(self):
        text, done = gemini.plan("", enabled=True)
        self.assertTrue(done)
        data = json.loads(text)
        self.assertIn(gemini.HOOK_NAME, data)
        spec = data[gemini.HOOK_NAME]
        self.assertIn("PreInvocation", spec)
        self.assertIn("PostToolUse", spec)
        self.assertIn("Stop", spec)
        # Never register PreToolUse so permission prompts are untouched
        self.assertNotIn("PreToolUse", spec)

        # Idempotent
        self.assertEqual(gemini.plan(text, enabled=True), (None, []))

        # Preserves unrelated user hooks when adding/removing
        data["my-linter"] = {"PostToolUse": [{"matcher": "run_command", "hooks": [{"command": "./lint.sh"}]}]}
        removed, rdone = gemini.plan(json.dumps(data), enabled=False)
        self.assertTrue(rdone)
        after = json.loads(removed)
        self.assertNotIn(gemini.HOOK_NAME, after)
        self.assertIn("my-linter", after)

    def test_invalid_json_raises(self):
        with self.assertRaises(ValueError):
            gemini.plan("[1, 2]")

    def test_hook_script_writes_activity_and_outputs_json(self):
        tmp = Path(tempfile.mkdtemp())
        env = dict(os.environ, HOME=str(tmp))
        payload = json.dumps({"toolCall": {"name": "run_command"}, "modelName": "gemini-4-neon"})
        res = subprocess.run(
            ["bash", str(ROOT / "bin/gemini-hook.sh"), "post"],
            input=payload, text=True, capture_output=True, env=env, check=True,
        )
        self.assertEqual(json.loads(res.stdout.strip()), {})
        act = json.loads((tmp / ".cache/gemini/activity.json").read_text())
        self.assertEqual(act["event"], "post")
        self.assertEqual(act["tool"], "run_command")
        self.assertEqual(act["model"], "gemini-4-neon")
        self.assertGreater(act["ts"], 0)


class GeminiAlerts(unittest.TestCase):
    def test_parses_t3_and_local_and_picks_newer(self):
        tmp = Path(tempfile.mkdtemp())
        saved = (gem_alerts.T3_CACHE, gem_alerts.LOCAL_CACHE, gem_alerts.SETTINGS)
        try:
            gem_alerts.T3_CACHE = tmp / "antigravity.json"
            gem_alerts.LOCAL_CACHE = tmp / "gemini-usage.json"
            gem_alerts.SETTINGS = tmp / "settings.json"
            t1 = "2026-11-24T22:00:00.000Z"
            r5 = "2026-11-25T02:00:00.000Z"
            gem_alerts.T3_CACHE.write_text(json.dumps({
                "usageLimits": {
                    "checkedAt": t1,
                    "windows": [
                        {"id": "3p-5h", "usedPercent": 10},
                        {"id": "gemini-5h", "usedPercent": 45.7, "resetsAt": r5},
                        {"id": "gemini-weekly", "usedPercent": 36.6, "resetsAt": "2026-11-30T20:00:00.000Z"},
                    ],
                }
            }))
            wins = gem_alerts.newest()
            self.assertEqual([w[0] for w in wins], ["gemini-5h", "gemini-weekly"])
            self.assertAlmostEqual(wins[0][2], 45.7)
            self.assertEqual(wins[0][3], datetime(2026, 11, 25, 2, 0, tzinfo=timezone.utc).timestamp())

            # Newer local cache wins
            t2 = int(datetime(2026, 11, 24, 22, 10, tzinfo=timezone.utc).timestamp())
            gem_alerts.LOCAL_CACHE.write_text(json.dumps({
                "updated": t2,
                "five_hour": {"used_percentage": 84, "resets_at": t2 + 3600},
            }))
            wins2 = gem_alerts.newest()
            self.assertEqual(wins2[0][0], "gemini-5h")
            self.assertEqual(wins2[0][2], 84.0)

            # Settings disable alerts cleanly
            gem_alerts.SETTINGS.write_text(json.dumps({"modules": {"gemini": {"enabled": True, "config": {"alerts": False}}}}))
            self.assertFalse(gem_alerts._alerts_enabled())
            gem_alerts.SETTINGS.write_text(json.dumps({"modules": {"gemini": {"enabled": False, "config": {"alerts": True}}}}))
            self.assertFalse(gem_alerts._alerts_enabled())
        finally:
            gem_alerts.T3_CACHE, gem_alerts.LOCAL_CACHE, gem_alerts.SETTINGS = saved


class T3ActivityProbe(unittest.TestCase):
    def test_detects_running_and_completed_runs(self):
        import sqlite3
        tmp = Path(tempfile.mkdtemp())
        db = tmp / "statev2.sqlite"
        con = sqlite3.connect(db)
        con.execute(
            "CREATE TABLE orchestration_v2_projection_runs "
            "(run_id TEXT, provider TEXT, status TEXT, requested_at TEXT, completed_at TEXT)"
        )
        now = datetime(2026, 11, 24, 23, 0, 0, tzinfo=timezone.utc)
        con.execute(
            "INSERT INTO orchestration_v2_projection_runs VALUES ('r1', 'antigravity', 'running', ?, NULL)",
            ("2026-11-24T22:59:30.000Z",),
        )
        con.execute(
            "INSERT INTO orchestration_v2_projection_runs VALUES ('r2', 'antigravity', 'completed', ?, ?)",
            ("2026-11-24T22:50:00.000Z", "2026-11-24T22:52:00.000Z"),
        )
        con.execute(
            "INSERT INTO orchestration_v2_projection_runs VALUES ('r3', 'claudeAgent', 'running', ?, NULL)",
            ("2026-11-24T22:59:45.000Z",),
        )
        con.commit()
        con.close()

        res = t3_act.query("antigravity", db_path=db, now=now.timestamp())
        self.assertEqual(res["running"], 1)
        self.assertEqual(res["status"], "running")

        # Stale run > 2 hours old is ignored
        res_stale = t3_act.query("antigravity", db_path=db, now=now.timestamp() + 3 * 3600)
        self.assertEqual(res_stale["running"], 0)
        self.assertEqual(res_stale["status"], "idle")

        # Missing DB cleanly returns idle
        res_missing = t3_act.query("antigravity", db_path=tmp / "nope.sqlite", now=now.timestamp())
        self.assertEqual(res_missing["running"], 0)


if __name__ == "__main__":
    unittest.main()
