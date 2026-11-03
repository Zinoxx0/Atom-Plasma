"""Rice/BarFit.qml, the bar's container query: run offscreen against a stand-in panel (tests/qml/barfit.qml).

The stand-in's widgets add up to 60 + 500 + 1 + 200 + 300 + 150 + 0 and 6 gaps of 4 px = 1235 px with
everything; each step gives up what the ladder says (system numbers, Claude numbers, folded pins,
the battery's number) and a bar too narrow for even the last step stays on it."""
import os
import shutil
import subprocess
import unittest
from pathlib import Path

QML = Path(__file__).parent / "qml" / "barfit.qml"


@unittest.skipUnless(shutil.which("qml6"), "needs qml6 (qt6-declarative)")
class BarFit(unittest.TestCase):
    def test_steps(self):
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_FORCE_STDERR_LOGGING="1")
        out = subprocess.run(["qml6", str(QML)], env=env, capture_output=True, text=True, timeout=30)
        rows = [line.split(" ", 4)[2:] for line in out.stderr.splitlines() if line.startswith("qml: fit ")]
        self.assertEqual(len(rows), 8, out.stderr)
        self.assertEqual(rows[0][2], "[1235,1115,1035,655,625]")
        # bar width -> step: room for everything, one px short, then each step in turn, too narrow even for
        # the last one (it stays there), room again
        self.assertEqual([(int(float(r)), int(s)) for r, s, _ in rows],
                         [(1600, 0), (1235, 0), (1234, 1), (1100, 2), (1000, 3), (640, 4), (600, 4), (2000, 0)])


if __name__ == "__main__":
    unittest.main()
