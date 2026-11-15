"""qmllint over the shell's QML, for the mistakes that break a component at load time (a missing required
property, a syntax error, a duplicate binding...): plasmashell only logs those, and a widget or the whole
launcher silently doesn't show. Fast (a few seconds); style warnings (unqualified access...) aren't failures."""
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Qt 6's (a bare `qmllint` on PATH may be Qt 5's, which knows none of this and checks nothing)
QMLLINT = next((c for c in ("/usr/lib/qt6/bin/qmllint", "/usr/lib64/qt6/bin/qmllint", shutil.which("qmllint6"), shutil.which("qmllint-qt6"))
                if c and Path(c).exists()), None)
# the categories that are errors; everything else is off (--only-explicit-categories)
ERRORS = ["syntax", "required", "signal-handler-parameters", "duplicate-property-binding", "read-only-property",
          "alias-cycle", "inheritance-cycle", "duplicated-name"]


@unittest.skipUnless(QMLLINT, "needs qmllint (qt6-declarative)")
class QmlLint(unittest.TestCase):
    def test_no_load_errors(self):
        files = subprocess.run(["git", "ls-files", "plasmoids/*.qml", "qml/*.qml", "lnf/*.qml"], cwd=ROOT,
                               capture_output=True, text=True, check=True).stdout.split()
        self.assertTrue(files)
        cmd = [QMLLINT, "-I", "qml", "-I", str(Path.home() / ".local/lib/qt6/qml"), "-I", "/usr/lib/qt6/qml",
               "--only-explicit-categories"]
        for c in ERRORS:
            cmd += [f"--{c}", "error"]
        out = subprocess.run(cmd + files, cwd=ROOT, capture_output=True, text=True, timeout=300)
        text = out.stdout + out.stderr
        self.assertNotIn("Unknown option", text)            # (a qmllint too old for these options)
        errors = [l for l in text.splitlines() if l.startswith("Error")]
        self.assertEqual(errors, [], "\n" + "\n".join(errors))


if __name__ == "__main__":
    unittest.main()
