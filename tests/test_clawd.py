"""Rice/Clawd.qml and its two libraries (ClawdArt.js, ClawdActs.js), run offscreen (tests/qml/clawd.qml).

Every act has frames with a duration and only shows things there is a picture of; every frame can be
drawn; every hobby a pool can offer exists, never comes twice running, and its little project is
where the clock says it is after each burst; two views agree on the hobby and on an act with chance
in it; a click reaches the other view (through a scratch cache folder, so the real Clawds on the bars
don't join in); and the canvas is only repainted when the picture changed."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

QML = Path(__file__).parent / "qml" / "clawd.qml"
CHECKS = ["acts", "hobbies", "painted", "two views, one hobby", "two views, one act", "a hop, and back at rest",
          "no repaint without a change", "greets on hover", "a click plays an act", "four clicks make it dizzy", "a click reaches the other view",
          "a pinned hobby", "at work", "out of energy", "paused"]


@unittest.skipUnless(shutil.which("qml6"), "needs qml6 (qt6-declarative)")
class Clawd(unittest.TestCase):
    def test_clawd(self):
        with tempfile.TemporaryDirectory() as cache:
            os.mkdir(os.path.join(cache, "clawd"))      # (the hooks' folder: the views watch it for clicks)
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl",
                       QT_FORCE_STDERR_LOGGING="1", QML_XHR_ALLOW_FILE_READ="1", QML_XHR_ALLOW_FILE_WRITE="1",
                       XDG_CACHE_HOME=cache)
            out = subprocess.run(["qml6", str(QML)], env=env, capture_output=True, text=True, timeout=120)
        lines = [line[len("qml: clawd "):] for line in out.stderr.splitlines() if line.startswith("qml: clawd ")]
        self.assertEqual([line for line in lines if line.startswith("FAIL")], [], out.stderr)
        passed = [line[3:] for line in lines if line.startswith("ok ")]
        for check in CHECKS:
            self.assertTrue(any(p.startswith(check) for p in passed), f"missing: {check}\n{out.stderr}")
        self.assertIn("done 0", lines, out.stderr)
        # and nothing else went wrong on the way (a binding loop, a type error in a handler)
        noise = [line for line in out.stderr.splitlines()
                 if any(w in line for w in ("Error", "Binding loop", "is not defined", "Cannot", "Unable to assign"))]
        self.assertEqual(noise, [], out.stderr)


if __name__ == "__main__":
    unittest.main()
