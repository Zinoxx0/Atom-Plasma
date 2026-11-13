"""atom/home.py: the launcher's data (Steam's art per game, KActivities' usage per app)."""
import sqlite3
import tempfile
import unittest
from pathlib import Path

from atom import home


class HomeData(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        apps = self.tmp / "applications"
        apps.mkdir()
        (apps / "Yakuza 0.desktop").write_text("[Desktop Entry]\nName=Yakuza 0\nExec=steam steam://rungameid/638970\n")
        (apps / "org.kde.konsole.desktop").write_text("[Desktop Entry]\nName=Konsole\nExec=konsole\n")
        sub = apps / "kde"
        sub.mkdir()
        (sub / "game.desktop").write_text("[Desktop Entry]\nExec=steam steam://rungameid/42\n")
        cache = self.tmp / "librarycache"
        flat = cache / "638970"
        flat.mkdir(parents=True)
        for n in ("library_600x900.jpg", "library_hero.jpg", "logo.png", "header.jpg"):
            (flat / n).write_bytes(b"x")
        hashed = cache / "42" / "0a1b"
        hashed.mkdir(parents=True)
        (hashed / "library_capsule.jpg").write_bytes(b"x")
        (cache / "42" / "ff09").mkdir()
        (cache / "42" / "ff09" / "library_hero.jpg").write_bytes(b"x")
        db = self.tmp / "database"
        c = sqlite3.connect(db)
        c.execute("create table ResourceScoreCache (usedActivity, initiatingAgent, targettedResource, scoreType, cachedScore, firstUpdate, lastUpdate)")
        rows = [(":global", "a", "applications:org.kde.konsole.desktop", 0, 10.5, 1, 100),
                ("x", "b", "applications:org.kde.konsole.desktop", 0, 2.0, 1, 300),
                (":global", "a", "file:///home/x.txt", 0, 5, 1, 400)]
        c.executemany("insert into ResourceScoreCache values (?,?,?,?,?,?,?)", rows)
        c.commit()
        c.close()
        self.apps, self.cache, self.db = [apps], cache, db

    def test_games_and_their_art(self):
        d = home.build(self.apps, self.cache, self.db)
        y = d["games"]["Yakuza 0.desktop"]
        self.assertEqual(y["appid"], "638970")
        self.assertTrue(y["portrait"].endswith("library_600x900.jpg"))
        self.assertTrue(y["header"].endswith("header.jpg"))
        g = d["games"]["kde-game.desktop"]           # a subfolder's file: its id joins the path with '-'
        self.assertTrue(g["portrait"].endswith("library_capsule.jpg"))      # hashed subfolders, the older name
        self.assertTrue(g["hero"].endswith("library_hero.jpg"))
        self.assertNotIn("logo", g)
        self.assertNotIn("org.kde.konsole.desktop", d["games"])

    def test_usage_adds_up_activities(self):
        u = home.build(self.apps, self.cache, self.db)["usage"]
        self.assertEqual(u["org.kde.konsole.desktop"], {"last": 300, "score": 12.5})
        self.assertEqual(len(u), 1)                  # files aren't apps

    def test_missing_sources_are_empty(self):
        d = home.build([], self.tmp / "nope", self.tmp / "nodb")
        self.assertEqual(d, {"games": {}, "usage": {}})


if __name__ == "__main__":
    unittest.main()
