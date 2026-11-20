"""bin/claude-usage.py: Claude's usage limits from Anthropic in the status line's shape, so the Claude island's
rings stay right with no Claude Code session here. No network: fetch() is replaced, the files live in a
scratch folder."""
import importlib.util
import json
import sys
import tempfile
import time
import unittest
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cu = load("claude_usage", ROOT / "bin/claude-usage.py")
alerts = load("claude_alerts", ROOT / "plasmoids/com.zinoxx.claudeusage/contents/code/alerts.py")

# what the endpoint answers (its shape as Claude Code's /usage reads it)
ANSWER = {
    "five_hour": {"utilization": 6.0, "resets_at": "2026-11-20T19:29:59.943648+00:00"},
    "seven_day": {"utilization": 35.5, "resets_at": "2026-11-27T01:00:00.120+00:00"},
    "seven_day_opus": None,
    "extra_usage": {"is_enabled": False},
}
R5 = int(datetime(2026, 11, 20, 19, 30, tzinfo=timezone.utc).timestamp())
R7 = int(datetime(2026, 11, 27, 1, 0, tzinfo=timezone.utc).timestamp())


class Window(unittest.TestCase):
    def test_shape(self):
        self.assertEqual(cu.window(ANSWER["five_hour"]), {"used_percentage": 6, "resets_at": R5})
        self.assertEqual(cu.window(ANSWER["seven_day"]), {"used_percentage": 35.5, "resets_at": R7})

    def test_not_started_or_odd(self):
        none = {"used_percentage": 0, "resets_at": None}
        self.assertEqual(cu.window(None), none)
        self.assertEqual(cu.window({"utilization": None, "resets_at": None}), none)
        self.assertEqual(cu.window({"utilization": "x", "resets_at": "not a date"}), none)
        self.assertEqual(cu.window({"utilization": 3, "resets_at": "2026-11-20T19:30:00Z"}),
                         {"used_percentage": 3, "resets_at": R5})

    def test_record_matches_the_status_line(self):
        rec = cu.poll_record(ANSWER, 1000.4)
        self.assertEqual(rec, {"checked": 1000, "five_hour": {"used_percentage": 6, "resets_at": R5},
                               "seven_day": {"used_percentage": 35.5, "resets_at": R7}})

    def test_newest(self):
        line, poll = {"updated": 50}, {"checked": 60}
        self.assertIs(cu.newest(line, poll), poll)
        self.assertEqual(cu.newest({"updated": 70}, poll)["updated"], 70)
        self.assertIs(cu.newest(None, poll), poll)
        self.assertIsNone(cu.newest(None, None))


class Run(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.saved = {k: getattr(cu, k) for k in ("CREDS", "LINE", "OUT", "ALERTS", "fetch")}
        cu.CREDS, cu.LINE, cu.OUT = self.tmp / "creds.json", self.tmp / "line.json", self.tmp / "poll.json"
        cu.ALERTS = self.tmp / "no-alerts.py"
        self.calls = 0

        def fetch(tok):
            self.calls += 1
            self.assertEqual(tok, "tok")
            return ANSWER
        cu.fetch = fetch
        self.argv = sys.argv
        sys.argv = ["claude-usage.py"]

    def tearDown(self):
        for k, v in self.saved.items():
            setattr(cu, k, v)
        sys.argv = self.argv

    def creds(self, expires_in):
        cu.CREDS.write_text(json.dumps({"claudeAiOauth": {"accessToken": "tok",
                                                          "expiresAt": int((time.time() + expires_in) * 1000)}}))

    def test_writes_the_poll_file(self):
        self.creds(3600)
        self.assertEqual(cu.main(), 0)
        rec = json.loads(cu.OUT.read_text())
        self.assertEqual(rec["five_hour"], {"used_percentage": 6, "resets_at": R5})
        self.assertLess(abs(rec["checked"] - time.time()), 5)

    def test_a_live_session_here_skips(self):
        self.creds(3600)
        cu.LINE.write_text(json.dumps({"updated": int(time.time()) - 30, "five_hour": {}}))
        cu.main()
        self.assertEqual(self.calls, 0)
        self.assertFalse(cu.OUT.exists())
        sys.argv.append("--force")
        cu.main()
        self.assertEqual(self.calls, 1)

    def test_expired_or_missing_sign_in_waits(self):
        self.assertEqual(cu.main(), 0)              # no credentials file
        self.creds(-10)
        self.assertEqual(cu.main(), 0)
        self.assertEqual(self.calls, 0)
        self.assertFalse(cu.OUT.exists())

    def test_offline_keeps_the_old_file(self):
        self.creds(3600)
        cu.OUT.write_text('{"checked":1}\n')

        def offline(tok):
            raise OSError("no route")
        cu.fetch = offline
        self.assertEqual(cu.main(), 0)
        self.assertEqual(cu.OUT.read_text(), '{"checked":1}\n')


class Alerts(unittest.TestCase):
    def test_reads_the_newer_cache(self):
        tmp = Path(tempfile.mkdtemp())
        saved = alerts.CACHES
        try:
            alerts.CACHES = (tmp / "line.json", tmp / "poll.json")
            self.assertIsNone(alerts.newest())
            alerts.CACHES[0].write_text(json.dumps({"updated": 100, "five_hour": {"used_percentage": 1}}))
            self.assertEqual(alerts.newest()["updated"], 100)
            alerts.CACHES[1].write_text(json.dumps({"checked": 200, "five_hour": {"used_percentage": 2}}))
            self.assertEqual(alerts.newest()["checked"], 200)
            alerts.CACHES[1].write_text("{half")
            self.assertEqual(alerts.newest()["updated"], 100)
        finally:
            alerts.CACHES = saved


if __name__ == "__main__":
    unittest.main()
