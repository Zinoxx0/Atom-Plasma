"""Display topologies: identity, arrangement checks and fixes, UI size. All pure: each case is built from
the JSON `kscreen-doctor -j` prints and parsed EDIDs, nothing asks the desktop.

    python3 -m unittest discover -s tests
"""
import tempfile
import unittest
from pathlib import Path

import api  # noqa: F401  (puts the repo on sys.path)
from atom import displays as D
from atom import util

ASUS4K = {"maker": "AUS", "product": "2755", "serial": "SBLMQS095780", "model": "VG27UQ1A", "mm_w": 600, "mm_h": 340}
ASUS2K = {"maker": "AUS", "product": "27fa", "serial": "S1LMQS102173", "model": "VG27AQA1A", "mm_w": 600, "mm_h": 340}
PANEL = {"maker": "CMN", "product": "1556", "serial": "", "model": "N156HMA-GA1", "mm_w": 340, "mm_h": 190}


def out(name, x, y, w, h, scale=1.0, mm=(0, 0), priority=2, rotation=1, mirror=0, typ=14, enabled=True):
    return {"name": name, "enabled": enabled, "connected": True, "pos": {"x": x, "y": y}, "scale": scale,
            "rotation": rotation, "priority": priority, "type": typ, "replicationSource": mirror,
            "sizeMM": {"width": mm[0], "height": mm[1]}, "currentModeId": "m",
            "modes": [{"id": "m", "size": {"width": w, "height": h}, "refreshRate": 60}]}


def topo(*outs, edid=None):
    return D.parse({"outputs": list(outs)}, edid or {})


def today(dp_x=1536, hdmi_x=3795):
    """This machine on 2026-10-28 (dp_x=1504: the overlap that made the maximize preview a band)."""
    return topo(out("eDP-1", 0, 195, 1920, 1080, 1.25, (344, 193), typ=7),
                out("DP-1", dp_x, 0, 3840, 2160, 1.7, (597, 336), priority=3),
                out("HDMI-A-1", hdmi_x, 18, 2560, 1440, 1.15, (597, 336), priority=1),
                edid={"eDP-1": PANEL, "DP-1": ASUS4K, "HDMI-A-1": ASUS2K})


def apply(ds, moves):
    for d in ds:
        if d.connector in moves:
            d.x, d.y = moves[d.connector]
    return ds


class Identity(unittest.TestCase):
    def test_ids_survive_a_connector_rename(self):
        a = {d.connector: d.id for d in today()}
        renamed = topo(out("DP-3", 1536, 0, 3840, 2160, 1.7), edid={"DP-3": ASUS4K})
        self.assertEqual(a["DP-1"], renamed[0].id)
        self.assertEqual(a["DP-1"], "AUS-2755-SBLMQS095780")
        self.assertEqual(a["eDP-1"], "CMN-1556")            # a panel without a serial: maker and product

    def test_identical_serialless_twins_get_the_connector(self):
        twin = dict(ASUS2K, serial="")
        ds = topo(out("DP-1", 0, 0, 1920, 1080), out("DP-2", 1920, 0, 1920, 1080), edid={"DP-1": twin, "DP-2": twin})
        self.assertEqual(sorted(d.id for d in ds), ["AUS-27fa@DP-1", "AUS-27fa@DP-2"])

    def test_no_edid_falls_back_to_the_connector(self):
        self.assertEqual(topo(out("HDMI-A-2", 0, 0, 1920, 1080))[0].id, "conn:HDMI-A-2")

    def test_edid_parse(self):
        b = bytearray(128)
        b[0:8] = b"\x00\xff\xff\xff\xff\xff\xff\x00"
        b[8], b[9] = 0x06, 0xB3                             # AUS (5-bit letters)
        b[10], b[11] = 0x55, 0x27
        b[12:16] = (0x01010101).to_bytes(4, "little")       # "no serial" filler
        b[21], b[22] = 60, 34
        b[54:72] = b"\x00\x00\x00\xfc\x00" + b"VG27UQ1A\n    "
        b[72:90] = b"\x00\x00\x00\xff\x00" + b"SBLMQS095780\n"
        e = D.parse_edid(bytes(b))
        self.assertEqual((e["maker"], e["product"], e["model"], e["serial"], e["mm_w"]),
                         ("AUS", "2755", "VG27UQ1A", "SBLMQS095780", 600))

    def test_registry_maps_old_connector_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            old = D.REGISTRY
            D.REGISTRY = Path(tmp) / "displays.json"
            try:
                D.remember(topo(out("DP-3", 0, 0, 3840, 2160, 1.7), edid={"DP-3": ASUS4K}), now=1)
                ds = today()
                moved = D.remember(ds, now=2)
                self.assertEqual(moved, {"AUS-2755-SBLMQS095780": "DP-3"})
                self.assertEqual(D.id_for("DP-3", ds), "AUS-2755-SBLMQS095780")     # gone connector -> its monitor
                self.assertEqual(D.id_for("DP-1", ds), "AUS-2755-SBLMQS095780")
                self.assertEqual(D.id_for("CMN-1556", ds), "CMN-1556")
                self.assertEqual(D.id_for("DP-9", ds), "")
            finally:
                D.REGISTRY = old


class Arrangement(unittest.TestCase):
    def assertSound(self, ds):
        issues = D.check(ds)
        self.assertEqual(issues, {"overlaps": [], "apart": []}, issues)

    def test_today_is_sound(self):
        self.assertSound(today())
        self.assertEqual(D.proposal(today()), "")

    def test_the_overlap_that_made_the_band(self):
        ds = today(dp_x=1504, hdmi_x=3763)
        self.assertEqual(D.check(ds)["overlaps"], [["eDP-1", "DP-1", 32.0, 864.0]])
        self.assertSound(apply(ds, D.fix(ds)))

    def test_a_gap_is_closed(self):
        ds = topo(out("DP-1", 0, 0, 1920, 1080, priority=1), out("DP-2", 2400, 100, 1920, 1080))
        self.assertEqual(D.check(ds)["apart"], ["DP-2"])
        moved = D.fix(ds)
        self.assertEqual(moved, {"DP-2": (1920, 100)})
        self.assertSound(apply(ds, moved))

    def test_seven_in_a_row(self):
        ds = topo(*[out(f"DP-{i}", i * 1920, 0, 1920, 1080, priority=1 if i == 3 else 2) for i in range(7)])
        self.assertSound(ds)
        self.assertEqual(D.shared_edges(ds[3], ds), {"left", "right"})

    def test_stacked_screens_share_top_and_bottom(self):
        ds = topo(out("DP-1", 0, 0, 2560, 1440, priority=1), out("DP-2", 320, 1440, 1920, 1080))
        self.assertSound(ds)
        low = next(d for d in ds if d.connector == "DP-2")
        self.assertEqual(D.shared_edges(low, ds), {"top"})          # Glimpse can't use this top edge

    def test_odd_trio(self):
        """A portrait 4K, an 8K at scale 2 and an 800x800 panel, all touching."""
        ds = topo(out("DP-1", 0, 0, 3840, 2160, 1.5, (336, 597), rotation=2),
                  out("DP-2", 1440, 0, 7680, 4320, 2.0, (697, 392), priority=1),
                  out("HDMI-A-1", 5280, 0, 800, 800, 1.0, (200, 200)))
        self.assertSound(ds)
        portrait = ds[0]
        self.assertEqual((portrait.w, portrait.h), (1440, 2560))
        self.assertTrue(portrait.portrait)
        self.assertEqual(portrait.label, "4K portrait")
        self.assertEqual(ds[1].label, "8K")

    def test_two_by_two_grid(self):
        ds = topo(out("A", 0, 0, 1920, 1080, priority=1), out("B", 1920, 0, 1920, 1080),
                  out("C", 0, 1080, 1920, 1080), out("D", 1920, 1080, 1920, 1080))
        self.assertSound(ds)
        self.assertEqual(D.shared_edges(ds[0], ds), {"right", "bottom"})

    def test_mirrors_overlap_by_design(self):
        ds = topo(out("eDP-1", 0, 0, 1920, 1080, priority=1, typ=7), out("HDMI-A-1", 0, 0, 1920, 1080, mirror=1))
        self.assertSound(ds)
        self.assertEqual(D.fix(ds), {})

    def test_a_fix_never_leaves_negative_positions(self):
        ds = today(dp_x=1504, hdmi_x=3763)
        moved = D.fix(ds)
        self.assertTrue(all(x >= 0 and y >= 0 for x, y in moved.values()), moved)

    def test_one_screen_needs_nothing(self):
        ds = topo(out("eDP-1", 0, 0, 1920, 1080, typ=7))
        self.assertSound(ds)
        self.assertTrue(ds[0].primary)


class Size(unittest.TestCase):
    def comfort(self, *a, **k):
        return D.comfort(topo(out(*a, **k))[0])

    def test_standard_sizes(self):
        ds = {d.connector: d for d in today()}
        laptop, k4, qhd = (D.comfort(ds[c]) for c in ("eDP-1", "DP-1", "HDMI-A-1"))
        self.assertLess(laptop, k4)                         # a 1080p laptop panel, seen close: smaller
        self.assertAlmostEqual(k4, qhd, delta=0.05)         # the 27" 4K and 27" 1440p look alike
        self.assertTrue(0.75 <= laptop <= 1.0 and 0.85 <= k4 <= 1.1, (laptop, k4))

    def test_an_8k_left_at_scale_1_gets_a_big_ui(self):
        big = self.comfort("DP-1", 0, 0, 7680, 4320, 1.0, (697, 392))
        self.assertGreaterEqual(big, 2.5)
        self.assertEqual(D.ui_scale(topo(out("DP-1", 0, 0, 7680, 4320, 1.0, (697, 392)))[0], {}), big)
        self.assertIsNotNone(D.scale_advice(topo(out("DP-1", 0, 0, 7680, 4320, 1.0, (697, 392)))[0]))

    def test_unknown_physical_size_is_guessed_from_resolution(self):
        self.assertTrue(0.8 <= self.comfort("HDMI-A-1", 0, 0, 1920, 1080, 1.0, (16, 9)) <= 1.2)
        self.assertGreater(self.comfort("HDMI-A-1", 0, 0, 7680, 4320, 1.0), 2.0)

    def test_a_tv_is_seen_from_further(self):
        """A 55" 4K TV at scale 1 seen from the couch needs ~2.5x (TVs ship at 200-250 %); at that scale it's
        standard."""
        tv = self.comfort("HDMI-A-1", 0, 0, 3840, 2160, 1.0, (1210, 680))
        self.assertTrue(2.0 <= tv <= 3.0, tv)
        self.assertAlmostEqual(self.comfort("HDMI-A-1", 0, 0, 3840, 2160, 2.5, (1210, 680)), 1.0, delta=0.1)

    def test_settings(self):
        d = today()[1]
        auto = D.comfort(d)
        self.assertEqual(D.ui_scale(d, {}), round(auto, 2))
        self.assertEqual(D.ui_scale(d, {"ui": {"size": 1.2}}), round(auto * 1.2, 2))
        self.assertEqual(D.ui_scale(d, {"ui": {"auto": False, "size": 1.3}}), 1.3)
        self.assertEqual(D.ui_scale(d, {"ui": {"size": 1.2}, "displays": {d.id: {"size": 1.5}}}), 1.5)
        self.assertEqual(D.ui_scale(d, {"ui": {"auto": False, "size": 9}}), 3.5)

    def test_seam_free_scales(self):
        ds = {d.connector: d for d in today()}
        self.assertEqual(D.seam_free(ds["DP-1"]), 1.6)      # 3840 / 1.7 = 2258.82 -> 1.6 gives 2400 x 1350
        self.assertIsNone(D.seam_free(ds["eDP-1"]))         # 1920 / 1.25 = 1536: already whole


class Themes(unittest.TestCase):
    """presets.plan: a theme saved on some screens, loaded on others."""
    LAYOUT = [{"id": "L", "x": 0, "y": 0, "main": False, "image": "/w/laptop.jpg"},
              {"id": "K", "x": 1536, "y": 0, "main": False, "image": "/w/4k.jpg", "overrides": {"mood": "neon"}},
              {"id": "Q", "x": 3795, "y": 0, "main": True, "image": "/w/1440.jpg"}]

    def screens(self, *spec):
        return [{"id": i, "x": x, "main": m, "name": i.lower()} for i, x, m in spec]

    def test_same_setup(self):
        plan = api.presets.plan({"layout": self.LAYOUT}, self.screens(("L", 0, False), ("K", 1536, False), ("Q", 3795, True)))
        self.assertEqual({i: (w["image"], w["how"]) for i, w in plan.items()},
                         {"L": ("/w/laptop.jpg", "same"), "K": ("/w/4k.jpg", "same"), "Q": ("/w/1440.jpg", "same")})
        self.assertEqual(plan["K"]["overrides"], {"mood": "neon"})

    def test_laptop_alone_gets_its_own(self):
        plan = api.presets.plan({"layout": self.LAYOUT}, self.screens(("L", 0, True)))
        self.assertEqual(plan["L"]["image"], "/w/laptop.jpg")

    def test_another_machine_maps_by_role(self):
        plan = api.presets.plan({"layout": self.LAYOUT}, self.screens(("A", 0, True), ("B", 1920, False)))
        self.assertEqual((plan["A"]["image"], plan["A"]["how"], plan["A"]["from"]), ("/w/1440.jpg", "role", "Q"))
        self.assertEqual((plan["B"]["image"], plan["B"]["how"]), ("/w/laptop.jpg", "role"))   # then left to right

    def test_more_screens_than_saved_mirror_the_main_one(self):
        one = [{"id": "L", "x": 0, "main": True, "image": "/w/laptop.jpg"}]
        plan = api.presets.plan({"layout": one}, self.screens(("L", 0, False), ("K", 1536, False), ("Q", 3795, True)))
        self.assertEqual(plan["L"]["how"], "same")
        self.assertEqual({i: (w["image"], w["how"]) for i, w in plan.items() if i != "L"},
                         {"K": ("/w/laptop.jpg", "mirror"), "Q": ("/w/laptop.jpg", "mirror")})


if __name__ == "__main__":
    unittest.main()
