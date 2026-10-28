"""Golden tests for Atom Plasma's pure parts: what a wallpaper turns into (palette, terminals, apps, the
desk layout, the bar islands, the Plasma Style, ...) must not change by accident.

    python3 -m unittest discover -s tests          run them (from ~/.config/plasma-rice)
    RICE_UPDATE=1 python3 -m unittest discover -s tests
                                                   accept the current output as the new golden

The fixtures are thumbnails of one wallpaper per mood. Nothing here touches the desktop: no plasmashell,
no KWin, no files outside a temporary folder.
"""
import gzip
import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path

import api

HERE = Path(__file__).resolve().parent
FIXTURES = sorted((HERE / "fixtures").glob("*.jpg"))
GOLDEN = HERE / "golden"
UPDATE = os.environ.get("RICE_UPDATE") == "1"
CFG = {"light_ui": True, "soft_tint": 0.6, "depth": 0.0}


def sha(text):
    return hashlib.sha256(text.encode() if isinstance(text, str) else text).hexdigest()


class Golden(unittest.TestCase):
    """Compares a value with tests/golden/<name>.json (RICE_UPDATE=1 rewrites it)."""

    def golden(self, name, value):
        f = GOLDEN / f"{name}.json"
        text = json.dumps(value, indent=1, sort_keys=True, ensure_ascii=False) + "\n"
        if UPDATE or not f.exists():
            GOLDEN.mkdir(exist_ok=True)
            f.write_text(text)
            return
        want = f.read_text()
        if text != want:
            self.fail(f"{name} changed from tests/golden/{name}.json (RICE_UPDATE=1 accepts it):\n"
                      + "\n".join(_diff(want, text)))


def _diff(a, b, n=12):
    import difflib
    return list(difflib.unified_diff(a.splitlines(), b.splitlines(), "golden", "now", lineterm="", n=1))[:n * 3]


_pal = {}


def palettes(fix):
    """Every variant a wallpaper is drawn in: its own mood (dark UI, then light UI on), and overrides."""
    if fix not in _pal:
        a = api.analyse(fix)
        _pal[fix] = {
            "analysis": a,
            "auto": api.build_v2(a, CFG),
            "dark_ui": api.build_v2(a, dict(CFG, light_ui=False)),
            "soft_default_tint": api.build_v2(a, {"light_ui": True}, {"mood": "soft"}),
            "override": api.build_v2(a, CFG, {"mood": "neon", "primary": "#ff3366", "intensity": 1.3}),
        }
    return _pal[fix]


class Palette(Golden):
    def test_palettes(self):
        for fix in FIXTURES:
            with self.subTest(fixture=fix.stem):
                self.golden(f"palette-{fix.stem}", palettes(fix))

    def test_fixture_moods(self):     # one fixture per mood, as named
        for fix in FIXTURES:
            self.assertEqual(api.mood_of(palettes(fix)["analysis"]), fix.stem.split("-")[0])

    def test_every_variant_has_the_keys_consumers_read(self):
        need = {"primary", "secondary", "tertiary", "on_primary", "background", "surface", "surface_lowest",
                "on_surface", "on_surface_variant", "muted", "outline", "outline_variant", "red", "green",
                "_mood", "_scheme", "_glow", "_edge"}
        for fix in FIXTURES:
            for name, p in palettes(fix).items():
                if name != "analysis":
                    self.assertLessEqual(need, set(p), f"{fix.stem}/{name}")


class Apps(Golden):
    def test_terminals_and_apps(self):
        for fix in FIXTURES:
            p = palettes(fix)["dark_ui"]
            with self.subTest(fixture=fix.stem):
                self.golden(f"apps-{fix.stem}", {
                    "ansi": api.ansi(p),
                    "kde_scheme": api.kde_scheme(palettes(fix)["auto"], "RiceA"),
                    "konsole": api.konsole(p), "konsole_tabs": api.konsole_tabs(p), "alacritty": api.alacritty(p),
                    "btop": api.btop(p), "mangohud": api.mangohud(p),
                    "zen": [api.zen_chrome(p), api.zen_content(p), api.zen_userjs(p, "user_pref(\"a\", 1);\n")],
                    "vscode_sha": sha(json.dumps(api.vscode(p), sort_keys=True)),
                })

    def test_templates(self):
        p = palettes(FIXTURES[0])["dark_ui"]
        with tempfile.TemporaryDirectory() as d:
            api.render_templates(p, d)
            out = {f.name: f.read_text() for f in sorted(Path(d).iterdir())}
        self.assertTrue(out)
        for name, text in out.items():      # (comments may show the syntax itself)
            code = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
            self.assertNotIn("{{", code, f"{name} has a placeholder left")
        self.golden("templates", out)
        ff = (api.ROOT / "templates/fastfetch.jsonc").read_text()
        self.golden("fastfetch", api.fill(ff, p, {"logo": "/x.png", "logo_type": "kitty", "logo_width": 20,
                                                   "accent3": p["teal"]}))


class Layout(Golden):
    def test_desk_layout(self):
        out = {}
        for fix in FIXTURES:
            for w, h in ((2560, 1440), (1536, 864)):
                L = api.place(fix, w, h)
                L.pop("_cost", None)
                out[f"{fix.stem}@{w}x{h}"] = L
        self.golden("layout", out)

    def test_upper_left_quadrant_stays_clear(self):     # the user's rule
        for fix in FIXTURES:
            for w, h in ((2560, 1440), (1536, 864)):
                for box in ("clock", "media"):
                    b = api.place(fix, w, h)[box]
                    self.assertFalse(b["x"] < w / 2 and b["y"] < h / 2, f"{fix.stem} {box} {b}")

    def test_rim(self):
        self.golden("rim", {fix.stem: api.rim(str(fix), palettes(fix)["auto"]) for fix in FIXTURES})


class Screens(Golden):
    @staticmethod
    def screen(name, x, y, w, h, main=False):
        return {"name": name, "x": x, "y": y, "w": w, "h": h, "main": main}

    def test_media_screen(self):
        s = self.screen
        three = [s("eDP-1", 0, 191, 1536, 864), s("DP-3", 1536, 0, 2259, 1271), s("HDMI-A-1", 3795, 18, 2226, 1252, True)]
        self.assertEqual(api.media_screen(three, {}), "DP-3")                      # the biggest beside the main bar
        self.assertEqual(api.media_screen(three, {"desk_media": "eDP-1"}), "eDP-1")
        self.assertEqual(api.media_screen(three, {"desk_media": "gone"}), "DP-3")
        self.assertEqual(api.media_screen(three[:1], {}), "eDP-1")                  # the only screen
        self.assertEqual(api.media_screen([three[0], three[2]], {}), "eDP-1")       # with two, the other one
        self.assertEqual(api.media_screen([], {}), "")

    def test_theme_args(self):
        self.assertEqual(api.theme_args(["theme", "set", "--primary", "#AABBCC", "--mood", "auto", "--intensity", "9"]),
                         {"primary": "#aabbcc", "mood": "auto", "intensity": 1.5})
        for bad in (["--primary", "red"], ["--mood", "angry"], ["--intensity", "lots"]):
            with self.assertRaises(SystemExit):
                api.theme_args(bad)

    def test_unusable(self):
        self.assertEqual(api.unusable(FIXTURES[0]), "")
        with tempfile.TemporaryDirectory() as d:
            broken = Path(d) / "broken.jpg"
            broken.write_bytes(FIXTURES[0].read_bytes()[:3000])
            self.assertIn("can't be read", api.unusable(broken))
            other = Path(d) / "x.jxl"
            other.write_bytes(b"\xff\x0a")
            self.assertIn("supported", api.unusable(other))


class Chrome(Golden):
    def test_tokens_qml(self):
        self.golden("tokens-qml", api.tokens_qml())

    def test_bar_islands(self):
        out = {}
        for fix in FIXTURES:
            p = palettes(fix)["auto"]
            out[fix.stem] = {"island": sha(json.dumps(api.island_style(p, p["primary"], states=True, fg=True), sort_keys=True)),
                             "quiet": sha(json.dumps(api.island_style(p, p["tertiary"], states=False), sort_keys=True)),
                             "launcher": sha(json.dumps(api.launcher_style(p), sort_keys=True))}
        self.golden("islands", out)

    def test_plasma_style(self):
        out = {}
        with tempfile.TemporaryDirectory() as d:
            for variant in ("dark", "light"):
                root = api.build_style(variant, d)
                out[variant] = {str(f.relative_to(root)): sha(gzip.decompress(f.read_bytes()) if f.suffix == ".svgz"
                                                              else f.read_bytes())       # (gzip stamps the time)
                                for f in sorted(root.rglob("*")) if f.is_file()}
        self.golden("plasma-style", out)

    def test_limine_header(self):
        conf = ("timeout: 5\n# CachyOS Limine theme\nterm_palette: 1;2\ncomment: hi\n\n/CachyOS\n"
                "    protocol: linux\n    path: boot():/vmlinuz#abc\n")
        block = ["# Rice Limine theme", "wallpaper: boot():/limine-rice.png", "# end Rice Limine theme"]
        out = api.limine_conf(conf, block)
        self.assertTrue(out.endswith(conf[conf.index("/CachyOS"):]), "the entries must stay byte-identical")
        self.golden("limine", out)

    def test_keyboard_colours(self):
        p = palettes(FIXTURES[0])["auto"]
        self.golden("rgb", {"vivid": [api.vivid(p[r]) for r in ("primary", "tertiary")],
                            "led": api.led(p["primary"]),
                            "frame": api.key_frame([p["primary"], p["tertiary"]], 2, 5)})


class UpdateCheck(Golden):
    """update-check.py's pure parts: what Claude must look up, what it's told, what the report and the
    notice say. UPS is a slice of a real CachyOS update list."""
    UPS = {
        "kwin": ("6.8.1-1.1", "6.8.1-2.1", "repo"),
        "linux-cachyos": ("7.2.11-1", "7.3.0-4", "repo"),
        "linux-cachyos-headers": ("7.2.11-1", "7.3.0-4", "repo"),
        "linux-cachyos-nvidia-open": ("7.2.11-1", "7.3.0-4", "repo"),
        "linux-cachyos-lts": ("6.18.40-1", "6.18.41-1", "repo"),
        "linux-firmware": ("1:20260916-1", "1:20261019-1", "repo"),
        "linux-firmware-nvidia": ("1:20260916-1", "1:20261019-1", "repo"),
        "linux-api-headers": ("6.19-1", "6.20-1", "repo"),
        "lib32-mesa": ("3:26.2.4-1", "3:26.2.5-1", "repo"),
        "mesa": ("3:26.2.4-1", "3:26.2.5-1", "repo"),
        "nss": ("3.131.1-1.1", "3.132-1.1", "repo"),
        "nss-mdns": ("0.15.1-1", "0.15.2-1", "repo"),
        "polkit-kde-agent": ("6.8.1-1", "6.8.2-1", "repo"),
        "webkit2gtk-4.1": ("2.54.1-1", "2.54.2-1", "repo"),
        "spotifast-bin": ("0.13.3-1", "0.14.2-1", "aur"),
    }
    HOLDS = {"spotifast-bin": {"skip": "0.14.1-1", "why": "segfaults in the NVIDIA EGL driver", "have": "0.13.3-1"}}

    def test_must_check(self):
        must = api.must_check(self.UPS, self.HOLDS)
        self.assertEqual([name for name, _ in must],
                         ["linux-firmware", "linux-cachyos-lts", "linux-cachyos", "mesa", "nss", "spotifast-bin"])
        self.golden("update-must-check", must)
        # a rebuild is never a must-check item, and a held package at its skipped version isn't either
        self.assertEqual(api.must_check({"kwin": self.UPS["kwin"], "spotifast-bin": ("0.13.3-1", "0.14.1-1", "aur")},
                                        self.HOLDS), [])

    def test_advisories(self):
        groups = [{"name": "AVG-1", "packages": ["linux"], "status": "Fixed", "fixed": "7.3.0-1", "severity": "High",
                   "type": "privilege escalation", "issues": ["CVE-2026-1"]},
                  {"name": "AVG-2", "packages": ["nss"], "status": "Fixed", "fixed": "3.131.1-1", "severity": "High",
                   "type": "x", "issues": []},                                  # already installed
                  {"name": "AVG-3", "packages": ["mesa"], "status": "Not affected", "fixed": "3:26.2.5-1",
                   "severity": "Low", "type": "x", "issues": []}]
        hits = api.advisories(groups, self.UPS)
        self.assertEqual(len(hits), 1)
        self.assertTrue(hits[0].startswith("- linux-cachyos: AVG-1"), hits[0])  # Arch's linux covers CachyOS's

    def test_prompt(self):
        news = "- Arch, Sun, 19 Oct 2026: News (https://archlinux.org/news/x/)"
        full, must = api.update_prompt(self.UPS, sorted(self.UPS), self.HOLDS, "none", news, "2026-10-25")
        self.assertEqual(len(must), 6)
        daily, must = api.update_prompt(self.UPS, ["mesa", "lib32-mesa", "kwin"], self.HOLDS, "none", news, "2026-10-25")
        self.assertEqual([name for name, _ in must], ["mesa"])
        self.golden("update-prompt", {"full": full.splitlines(), "daily": daily.splitlines()})

    def test_report(self):
        verdict = {"important": False, "report": "Nothing qualifies.",
                   "checked": [{"name": "mesa", "finding": "Bug fixes only.", "source": "https://docs.mesa3d.org/"},
                               {"name": "lib32-mesa", "finding": "Same release.", "source": "https://docs.mesa3d.org/"},
                               {"name": "nss", "finding": "Looked at the NSS release notes; none yet.", "source": ""}]}
        must = api.must_check({n: self.UPS[n] for n in ("mesa", "lib32-mesa", "nss")}, {})
        text = api.update_report("2026-10-25 20:00", "scheduled", self.UPS, ["lib32-mesa", "mesa", "nss"], verdict,
                                 must, ["search: mesa 26.2.5 release notes"])
        self.assertIn("## Must-check items with no source\n\n- nss ", text)
        self.assertNotIn("**lib32-mesa**", text)                                 # folded into mesa's entry
        self.golden("update-report", text.splitlines())

    def test_notice_keys(self):
        self.assertEqual(api.notice_keys("m", {"kwin": "6.8.1-2.1", "mesa": "3:26.2.5-1"}),
                         {"kwin=6.8.1", "mesa=3:26.2.5"})                       # a rebuild is no news
        self.assertTrue(next(iter(api.notice_keys("m", {}))).startswith("msg:"))
        self.assertEqual(api.notified({"notified": ["kwin=6.8.1-1.1", "nss=3.132", "msg:ab12"]}),
                         {"kwin=6.8.1", "nss=3.132", "msg:ab12"})



class ClawdIntent(unittest.TestCase):
    """clawd-intent.py: what Claude's answer was about (Clawd's pose after it), from the answer and the
    tools its turn used."""
    EDIT, LOOK, RUN = ["Read", "Edit", "Bash"], ["WebSearch", "WebFetch", "Read"], ["Bash", "Bash"]

    def kind(self, text, tools=(), background=()):
        return api.answer_kind(text, list(tools), list(background))

    def test_running(self):
        self.assertEqual(self.kind("Started it.", self.RUN, [{"id": "b1"}]), "running")
        self.assertEqual(self.kind("The second dry run is going. It should take about a minute.", self.RUN), "running")
        self.assertNotEqual(self.kind("I've stopped the checks; nothing else is running.", self.RUN), "running")

    def test_question(self):
        self.assertEqual(self.kind("Two ways to go.\n\nWhich one do you want?"), "question")
        self.assertEqual(self.kind("It's ready, but I can't run sudo, so please run this in your own terminal:"), "question")
        # an offer of a next step after finished work isn't one
        self.assertEqual(self.kind("The overhaul is done and live.\n\nNothing is committed yet; want me to commit it?", self.EDIT), "done")
        self.assertEqual(self.kind("Here's how it works.\n\nIf you'd like, I can look it up.", self.LOOK), "found")
        self.assertNotEqual(self.kind("It expands to `x < 0 ? -x : x`, a ternary.", self.LOOK), "question")

    def test_outcomes(self):
        self.assertEqual(self.kind("Tiling is back on now. The toggle was broken by a bug.", self.EDIT), "fixed")
        self.assertEqual(self.kind("Your own widget was the cause: its bob kept the GPU busy.", self.EDIT), "fixed")
        self.assertEqual(self.kind("I couldn't get the build to work: the linker fails.", self.RUN), "stuck")
        self.assertEqual(self.kind("Nothing is broken; the shell crashed once and restarted itself.", self.RUN), "found")
        self.assertEqual(self.kind("The islands now have a glass look on all three bars.", self.RUN), "done")
        self.assertEqual(self.kind("The cause is a stale cache in the launcher, and here is why. " * 20, self.LOOK), "found")
        self.assertEqual(self.kind("Pick 2."), "chat")


if __name__ == "__main__":
    unittest.main()
