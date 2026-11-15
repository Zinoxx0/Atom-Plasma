"""bin/pad.py (the game controller daemon): what it can check without a controller or a session. The keyboard
layouts the on-screen keyboard draws (libxkbcommon), the characters it can type as keys and the ones that go
through the clipboard, and which focused windows count as games. The daemon itself is tested live
(it drives the real pointer and keys): see its docstring."""
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("pad", ROOT / "bin/pad.py")
pad = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pad)


class Layouts(unittest.TestCase):
    def test_us(self):
        k = pad.Keymap("us")
        rows = [[key["l"][0] for key in row] for row in k.rows()]
        self.assertEqual(rows[1][:10], list("qwertyuiop"))
        self.assertEqual(rows[2][:9], list("asdfghjkl"))
        self.assertFalse(k.has102)                          # (an ANSI keyboard: no key left of Z)
        self.assertEqual(rows[3][0], "z")
        self.assertEqual(k.chars["@"], (3, 1))              # Shift+2
        self.assertEqual(k.chars["A"], (30, 1))
        self.assertNotIn("é", k.chars)                      # (through the clipboard)

    def test_pt(self):
        k = pad.Keymap("pt")
        self.assertTrue(k.has102)                           # (ISO: < > left of Z)
        self.assertEqual(k.chars["ç"], (39, 0))
        self.assertEqual(k.chars["@"], (3, 2))              # AltGr+2
        acute = next(key for row in k.rows() for key in row if key["code"] == 27)
        self.assertTrue(acute["dead"][0])                   # ´ composes with the next letter
        self.assertNotIn("´", k.chars)                      # (a dead key never types itself)

    def test_json_is_what_the_keyboard_reads(self):
        j = pad.Keymap("us").json()
        self.assertEqual((j["layout"], len(j["rows"])), ("us", 4))
        self.assertTrue(all({"code", "l", "dead"} <= set(key) for row in j["rows"] for key in row))


class Games(unittest.TestCase):
    def test_by_window(self):
        self.assertTrue(pad.is_game({"cls": "steam_app_1172470"}))
        self.assertTrue(pad.is_game({"cls": "gamescope"}))
        self.assertTrue(pad.is_game({"cls": "steam", "caption": "Steam Big Picture Mode"}))
        self.assertFalse(pad.is_game({"cls": "steam", "caption": "Steam"}))
        self.assertFalse(pad.is_game({"cls": "zen", "full": True}))     # (a fullscreen video isn't a game)
        self.assertFalse(pad.is_game({}))

    def test_by_process(self):
        import os
        self.assertFalse(pad.is_game({"cls": "python3", "pid": os.getpid()}))   # (this process: no Steam, no Wine)
        self.assertFalse(pad.is_game({"cls": "x", "pid": 999999999}))           # (gone)


if __name__ == "__main__":
    unittest.main()
