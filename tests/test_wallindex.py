"""atom/wallindex.py: the colour wheel's index (cached by size and mtime; unreadable files listed apart)."""
import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from atom import wallindex


class WallIndex(unittest.TestCase):
    def test_build_cache_and_bad(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            red, blue = d / "red.png", d / "blue.jpg"
            Image.new("RGB", (64, 36), (220, 30, 40)).save(red)
            Image.new("RGB", (64, 36), (30, 60, 220)).save(blue)
            broken = d / "broken.png"
            broken.write_bytes(b"not a picture")
            out = d / "index.json"
            data = wallindex.build([red, blue, broken], out=out, settings={}, workers=1)
            self.assertEqual(sorted(data["walls"]), ["blue.jpg", "red.png"])
            self.assertIn("broken.png", data["bad"])
            r, b = data["walls"]["red.png"], data["walls"]["blue.jpg"]
            self.assertTrue(r["pal"]["primary"].startswith("#"))
            self.assertNotEqual(round(r["hue"]), round(b["hue"]))
            # unchanged files are not analysed again (a planted marker survives)
            j = json.loads(out.read_text())
            j["walls"]["red.png"]["marker"] = 1
            out.write_text(json.dumps(j))
            again = wallindex.build([red, blue, broken], out=out, settings={}, workers=1)
            self.assertEqual(again["walls"]["red.png"].get("marker"), 1)


if __name__ == "__main__":
    unittest.main()
