"""atom/manager.py: what Atom Manager shows (the launcher's settings page)."""
import json
import unittest
from unittest import mock

from atom import manager


class Manager(unittest.TestCase):
    def test_https_url(self):
        self.assertEqual(manager.https_url("git@github.com:Zinoxx0/Atom-Plasma.git"), "https://github.com/Zinoxx0/Atom-Plasma")
        self.assertEqual(manager.https_url("https://github.com/Zinoxx0/Atom-Plasma.git"), "https://github.com/Zinoxx0/Atom-Plasma")
        self.assertEqual(manager.https_url("ssh://git@github.com/a/b"), "https://github.com/a/b")

    def test_changelog_parses_groups_and_items(self):
        sec = manager.changelog(sections=1)
        self.assertEqual(len(sec), 1)
        self.assertTrue(sec[0]["groups"])
        for g in sec[0]["groups"]:
            self.assertTrue(g["items"])
            self.assertTrue(all("`" not in i for i in g["items"]))

    def test_update_state_prefers_the_newer_source(self):
        rp = {"behind": 2, "fetched": 100, "latestTag": "v1.0.0"}
        with mock.patch.object(manager.util, "load_json", return_value={}):
            st = manager.update_state(rp)
        self.assertEqual((st["available"], st["behind"], st["critical"]), (True, 2, False))
        with mock.patch.object(manager.util, "load_json", return_value={"checked": 200, "behind": 3, "critical": True}):
            st = manager.update_state(rp)
        self.assertEqual((st["behind"], st["critical"], st["checked"]), (3, True, 200))
        # an older updater file loses to a newer fetch; critical never shows without an update
        with mock.patch.object(manager.util, "load_json", return_value={"checked": 50, "behind": 3, "critical": True}):
            st = manager.update_state(dict(rp, behind=0))
        self.assertEqual((st["available"], st["critical"]), (False, False))

    def test_credits_are_complete(self):
        data = json.loads(manager.CREDITS.read_text())
        for g in data["groups"]:
            for it in g["items"]:
                for k in ("name", "what", "license", "url"):
                    self.assertTrue(it.get(k), f"{it.get('name')}: {k}")

    def test_contributors_have_no_addresses(self):
        for c in manager.contributors():
            self.assertNotIn("@", c["name"])


if __name__ == "__main__":
    unittest.main()
