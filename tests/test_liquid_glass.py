"""Unit tests for the unified material styles (panel.py Colorizer looks & compiled optical QSB shaders)."""
import unittest

from atom import panel, util

PAL = {
    "background": "#12131a",
    "surface_lowest": "#0b0c12",
    "on_surface": "#e6e8f4",
    "primary": "#7aa2f7",
    "secondary": "#bb9af7",
    "tertiary": "#7dcfff",
    "red": "#f7768e",
    "_scheme": "dark",
}


class MaterialStylesTests(unittest.TestCase):
    def test_all_seven_bar_styles_registered(self):
        expected = ("solid", "satin", "aurora", "matte", "clear", "liquid", "none")
        for st in expected:
            self.assertIn(st, panel.BAR_STYLES)
            self.assertEqual(panel.bar_style({"bar": {"style": st}}), st)
        self.assertEqual(panel.bar_style({"bar": {"style": "unknown"}}), "solid")
        self.assertNotIn("fluted", panel.BAR_STYLES)

    def test_shader_bar_styles_free_and_docked(self):
        for st in ("liquid", "aurora"):
            keep, blur = panel.BAR_STYLES[st]
            self.assertLess(keep, 0.15)
            self.assertTrue(blur)
            free = panel.island_style(PAL, PAL["primary"], states=True, docked=False, style=st)
            normal = free["normal"]
            self.assertTrue(normal["blurBehind"])
            self.assertLess(normal["backgroundColor"]["alpha"], 0.08)
            self.assertEqual(normal["border"]["color"]["alpha"], 0.0)
            self.assertEqual(normal["borderSecondary"]["color"]["alpha"], 0.0)
            self.assertGreater(free["hovered"]["borderSecondary"]["color"]["alpha"], 0.4)
            self.assertGreater(free["expanded"]["borderSecondary"]["color"]["alpha"], 0.7)
            self.assertGreater(free["needsAttention"]["borderSecondary"]["color"]["alpha"], 0.6)

            docked = panel.island_style(PAL, PAL["primary"], states=True, docked=True, style=st)
            docked_solid = panel.island_style(PAL, PAL["primary"], states=True, docked=True, style="solid")
            self.assertEqual(docked, docked_solid)

            free_launcher = panel.launcher_style(PAL, docked=False, style=st)
            self.assertTrue(free_launcher["normal"]["blurBehind"])
            self.assertEqual(free_launcher["normal"]["border"]["color"]["alpha"], 0.0)
            self.assertGreater(free_launcher["hovered"]["border"]["color"]["alpha"], 0.5)
            self.assertEqual(
                panel.launcher_style(PAL, docked=True, style=st),
                panel.launcher_style(PAL, docked=True, style="solid"),
            )

    def test_satin_bar_style_uses_opaque_grain_tile(self):
        keep, blur = panel.BAR_STYLES["satin"]
        self.assertGreaterEqual(keep, 0.9)
        self.assertFalse(blur)
        free = panel.island_style(PAL, PAL["primary"], states=True, docked=False, style="satin")
        bg = free["normal"]["backgroundColor"]
        self.assertEqual(bg["sourceType"], 6)
        self.assertTrue(bg["image"]["source"].startswith("file://"))
        self.assertFalse(free["normal"]["blurBehind"])

    def test_compiled_qsb_shaders_present_and_fresh(self):
        atom_qml = util.ROOT / "qml/Atom"
        for name in ("liquid_backdrop.frag", "aurora_backdrop.frag", "liquid_glass.frag"):
            frag = atom_qml / name
            qsb = atom_qml / (name + ".qsb")
            self.assertTrue(frag.exists(), f"missing {frag}")
            self.assertTrue(qsb.exists(), f"missing {qsb}")
            self.assertGreater(qsb.stat().st_size, 1000)
            self.assertGreaterEqual(qsb.stat().st_mtime, frag.stat().st_mtime - 1.0,
                                    f"{qsb.name} is older than {frag.name}")


if __name__ == "__main__":
    unittest.main()
