"""Atom.Native's Gamepad, driven by a pretend controller (tools/nested/pad.py, a uinput device) against
tests/qml/gamepad.qml run offscreen.

The case it guards: a pad's press closes the surface it drives (B is Escape, and the launcher closes on
it; A launches an app, and that closes it too), which turns the Gamepad off from inside its own read of
the pad. That freed the pad mid-read and crashed plasmashell (2026-11-15). Each time the Gamepad goes off
the page turns it on again, so one pad goes through: B, A, a held direction, then unplugged (its device must be let go).

The pretend pad is a real device for the whole machine for about three seconds (games and Steam see a
controller appear), so this runs only when asked: RICE_DEVICE_TESTS=1. It needs write access to /dev/uinput,
python-evdev, and Atom.Native (built by pkg/atom-native/build.sh, or ATOM_NATIVE_QML=<a qml folder>)."""
import os
import shutil
import subprocess
import sys
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QML = ROOT / "tests" / "qml" / "gamepad.qml"
PAD = ROOT / "tools" / "nested" / "pad.py"
NATIVE = Path(os.environ.get("ATOM_NATIVE_QML", Path.home() / ".local/lib/qt6/qml"))


def why_not():
    if os.environ.get("RICE_DEVICE_TESTS") != "1":
        return "makes a pretend controller for the whole machine: set RICE_DEVICE_TESTS=1"
    if not shutil.which("qml6"):
        return "needs qml6 (qt6-declarative)"
    if not os.access("/dev/uinput", os.W_OK):
        return "needs write access to /dev/uinput"
    try:
        import evdev  # noqa: F401
    except ImportError:
        return "needs python-evdev"
    if not (NATIVE / "Atom" / "Native" / "qmldir").exists():
        return f"needs Atom.Native in {NATIVE} (pkg/atom-native/build.sh)"
    return None


@unittest.skipIf(why_not(), why_not())
class Gamepad(unittest.TestCase):
    def test_off_from_inside_a_read(self):
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_FORCE_STDERR_LOGGING="1",
                   QML_IMPORT_PATH=str(NATIVE))
        app = subprocess.Popen(["qml6", str(QML)], env=env, stderr=subprocess.PIPE, text=True)
        try:
            lines = []
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:          # wait for the page before the pad appears
                line = app.stderr.readline()
                if not line:
                    break
                lines.append(line.rstrip())
                if line.startswith("qml: pad ready"):
                    break
            # B (its Escape turns the Gamepad off), A (its signal does), then down held, then unplugged
            subprocess.run([sys.executable, str(PAD), "east", "wait:700", "south", "wait:700", "hold:200", "down"],
                           check=True, timeout=30)
            time.sleep(1.0)
            # the pretend pad is gone: nothing may still hold its device (other, real pads may be open)
            held = []
            for fd in Path(f"/proc/{app.pid}/fd").iterdir():
                try:
                    link = os.readlink(fd)
                except OSError:
                    continue
                if link.startswith("/dev/input/"):
                    held.append(link)
            app.terminate()
            _, rest = app.communicate(timeout=10)
            lines += rest.splitlines()
        finally:
            if app.poll() is None:
                app.kill()
        log = "\n".join(lines)
        self.assertNotIn(app.returncode, (-11, -6, 134, 139), f"qml6 crashed\n{log}")
        pad = [line[len("qml: pad "):] for line in lines if line.startswith("qml: pad ")]
        self.assertNotIn("timeout", pad, log)
        self.assertNotIn("button east", pad, log)      # B's Escape closed it: its signal is for no one

        def after(what, start):
            i = pad.index(what, start) if what in pad[start:] else -1
            self.assertGreaterEqual(i, 0, f"missing {what!r} after #{start}\n{log}")
            return i + 1

        i = after("present true", 0)
        i = after(f"key {0x01000000}", i)               # Qt.Key_Escape, from B: it turns the Gamepad off
        i = after("active false", i)
        i = after("present true", i)                    # on again, and the pad is read again
        i = after(f"key {0x01000004}", i)               # Qt.Key_Return, from A
        i = after("button south", i)                    # its signal turns it off
        i = after("active false", i)
        i = after("present true", i)
        after(f"key {0x01000015}", i)                   # Qt.Key_Down, held
        stale = [link for link in held if link.endswith("(deleted)") or not os.path.exists(link)]
        self.assertEqual(stale, [], "an unplugged pad is still open")


if __name__ == "__main__":
    unittest.main()
