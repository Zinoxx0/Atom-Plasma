"""atom/manager.py: what Atom Manager shows (the launcher's settings page)."""
import json
import unittest

from atom import manager


class Manager(unittest.TestCase):
    def test_https_url(self):
        self.assertEqual(manager.https_url("git@github.com:ViviaTech/Atom-Plasma.git"), "https://github.com/ViviaTech/Atom-Plasma")
        self.assertEqual(manager.https_url("https://github.com/ViviaTech/Atom-Plasma.git"), "https://github.com/ViviaTech/Atom-Plasma")
        self.assertEqual(manager.https_url("ssh://git@github.com/a/b"), "https://github.com/a/b")

    def test_changelog_parses_groups_and_items(self):
        sec = manager.changelog(sections=1)
        self.assertEqual(len(sec), 1)
        self.assertTrue(sec[0]["groups"])
        for g in sec[0]["groups"]:
            self.assertTrue(g["items"])
            self.assertTrue(all("`" not in i for i in g["items"]))

    def test_credits_are_complete(self):
        data = json.loads(manager.CREDITS.read_text())
        for g in data["groups"]:
            for it in g["items"]:
                for k in ("name", "what", "license", "url"):
                    self.assertTrue(it.get(k), f"{it.get('name')}: {k}")

    def test_contributors_have_no_addresses(self):
        people = manager.contributors()
        for c in people:
            self.assertNotIn("@", c["name"])
        self.assertTrue(any(c["role"] == "Author" for c in people))


if __name__ == "__main__":
    unittest.main()
