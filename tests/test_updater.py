"""The updater against a pretend GitHub: a local repo of this code with release tags, a managed copy cloned from
it, every run in dry mode (git work only) under a throwaway HOME (the real state is never touched)."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from atom.version import Version, allowed, newest

ROOT = Path(__file__).resolve().parent.parent


class Versions(unittest.TestCase):
    def test_order_and_channels(self):
        vs = [Version.parse(s) for s in ("1.2.0", "1.3.0-alpha.5", "1.3.0-beta.1", "1.2.1", "1.3.0-alpha.12")]
        self.assertEqual([str(v) for v in sorted(vs)], ["1.2.0", "1.2.1", "1.3.0-alpha.5", "1.3.0-alpha.12", "1.3.0-beta.1"])
        self.assertEqual(str(newest(vs, "stable")), "1.2.1")
        self.assertEqual(str(newest(vs, "beta")), "1.3.0-beta.1")
        self.assertEqual(str(newest(vs + [Version.parse("1.3.0")], "alpha")), "1.3.0")
        self.assertFalse(allowed(Version.parse("1.3.0-alpha.1"), "beta"))
        self.assertIsNone(Version.parse("1.3"))
        self.assertIsNone(Version.parse("1.3.0-rc.1"))
        self.assertEqual(Version.parse("v2.0.0-beta.3").tag, "v2.0.0-beta.3")


def git(cwd, *a):
    return subprocess.run(["git", "-C", str(cwd), "-c", "user.name=t", "-c", "user.email=t@t", *a],
                          check=True, capture_output=True, text=True).stdout.strip()


@unittest.skipUnless(shutil.which("git"), "needs git")
class Updater(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix="atom-upd-"))
        src = cls.tmp / "src"
        files = subprocess.run(["git", "ls-files", "-co", "--exclude-standard"], cwd=ROOT, capture_output=True, text=True).stdout.split()
        for f in files:
            if (ROOT / f).is_file() and not f.startswith("pkg/kwin-effect-rounded-corners-rice/kde"):
                (src / f).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / f, src / f)
        git(src, "init", "-q", "-b", "main")

        def release(v, msg=""):
            init = src / "atom/__init__.py"
            init.write_text(__import__("re").sub(r'__version__ = "[^"]+"', f'__version__ = "{v}"', init.read_text()))
            git(src, "add", "-A")
            git(src, "commit", "-q", "-m", f"Release {v}")
            git(src, "tag", "-a", f"v{v}", "-m", f"Atom Plasma {v}\n\n{msg}")
        release("1.1.0")
        release("1.1.1", "Critical: yes\nSummary: Fixes a hole.")
        release("1.2.0-beta.1", "Summary: New things.")
        release("1.2.0-alpha.9")      # (older than the beta by semver: alpha < beta)
        subprocess.run(["git", "clone", "-q", "--bare", str(src), str(cls.tmp / "origin.git")], check=True)
        cls.client = cls.tmp / "client"
        subprocess.run(["git", "clone", "-q", str(cls.tmp / "origin.git"), str(cls.client)], check=True)
        git(cls.client, "checkout", "-q", "-B", "atom-release", "v1.1.0")
        cls.home = cls.tmp / "home"
        cls.home.mkdir()
        # a stand-in plasmashell: CI's container has no Plasma, and the updater rightly refuses a system without it
        cls.bin = cls.tmp / "bin"
        cls.bin.mkdir()
        (cls.bin / "plasmashell").write_text("#!/bin/sh\nexit 0\n")
        (cls.bin / "plasmashell").chmod(0o755)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def run_upd(self, *args, fail=""):
        env = dict(os.environ, HOME=str(self.home), ATOM_UPDATE_DRY="1", ATOM_UPDATE_FAIL=fail,
                   PATH=f"{self.bin}:{os.environ.get('PATH', '')}")
        return subprocess.run(["python3", str(self.client / "rice.py"), "update", *args], env=env,
                              capture_output=True, text=True, timeout=120)

    def check(self, *extra):
        r = self.run_upd("check", *extra)
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def progress(self):
        return json.loads((self.home / ".local/state/rice/update-progress.json").read_text())

    def test_1_channels_and_critical(self):
        st = self.check()
        self.assertEqual((st["mode"], st["current"], st["latest"]), ("managed", "1.1.0", "1.1.1"))
        self.assertTrue(st["available"] and st["critical"])
        self.assertEqual(st["summary"], "Fixes a hole.")
        self.assertEqual(st["custom"], [])
        status = json.loads((self.home / ".cache/rice/manager-status.json").read_text())
        self.assertTrue(status["critical"])
        r = self.run_upd("channel", "beta")
        st = json.loads(r.stdout)
        self.assertEqual(st["latest"], "1.2.0-beta.1")
        self.assertTrue(st["critical"])         # (1.1.1 is on the way there)
        self.run_upd("channel", "stable")

    def test_2_update_and_custom(self):
        r = self.run_upd("apply", "v1.1.1")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.progress()["state"], "done")
        self.assertEqual(git(self.client, "describe", "--tags", "--exact-match"), "v1.1.1")
        self.assertEqual(git(self.client, "rev-parse", "--abbrev-ref", "HEAD"), "atom-release")
        st = self.check("--offline")
        self.assertFalse(st["available"])
        self.assertEqual(st["current"], "1.1.1")
        # a change of your own: custom, refused without --force, kept with it
        git(self.client, "checkout", "-q", "-B", "atom-release", "v1.1.0")
        (self.client / "README.md").write_text((self.client / "README.md").read_text() + "\nmine\n")
        st = self.check("--offline")
        self.assertEqual(st["custom"], ["1 changed file"])
        r = self.run_upd("apply", "v1.1.1")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("custom", self.progress()["message"])
        self.assertTrue((self.client / "README.md").read_text().endswith("mine\n"))     # (untouched)
        r = self.run_upd("apply", "v1.1.1", "--force")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        backup = json.loads((self.home / ".local/state/rice/update-backup.json").read_text())
        self.assertTrue(backup["changes"])
        self.assertIn("mine", git(self.client, "show", backup["branch"] + "-changes:README.md"))
        # rollback: the old build and its change come back
        r = self.run_upd("rollback")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((self.client / "README.md").read_text().endswith("mine\n"))
        self.assertEqual(git(self.client, "rev-parse", "HEAD"), git(self.client, "rev-parse", "v1.1.0^{commit}"))
        git(self.client, "checkout", "-q", "--", "README.md")

    def test_3_failure_rolls_back(self):
        git(self.client, "checkout", "-q", "-f", "-B", "atom-release", "v1.1.0")
        r = self.run_upd("apply", "v1.1.1", fail="verify")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.progress()["state"], "rolledback")
        self.assertEqual(git(self.client, "rev-parse", "HEAD"), git(self.client, "rev-parse", "v1.1.0^{commit}"))
        r = self.run_upd("apply", "v1.1.1", fail="packages")     # (before the code moves: nothing to undo)
        self.assertEqual(self.progress()["state"], "failed")
        self.assertEqual(git(self.client, "rev-parse", "HEAD"), git(self.client, "rev-parse", "v1.1.0^{commit}"))

    def test_4_developer_copy_is_left_alone(self):
        git(self.client, "checkout", "-q", "-f", "-B", "main", "v1.1.0")
        st = self.check("--offline")
        self.assertEqual(st["mode"], "developer")
        self.assertFalse(st["available"] or st["critical"])
        self.assertTrue(st["newer"])
        r = self.run_upd("apply", "v1.1.1")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("developer", self.progress()["message"])
        git(self.client, "checkout", "-q", "-f", "atom-release")


if __name__ == "__main__":
    unittest.main()
