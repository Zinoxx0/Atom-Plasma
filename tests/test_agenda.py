"""agenda.py: Portuguese holidays (Easter-based ones included) and iCal events (recurrence, all-day,
time zones) as the clock's calendar reads them."""
import datetime as dt
import os
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
import agenda  # noqa: E402

FIX = ROOT / "tests/fixtures/agenda.ics"


class Holidays(unittest.TestCase):
    def test_easter(self):
        for y, want in ((2024, (3, 31)), (2025, (4, 20)), (2026, (4, 5)), (2027, (3, 28))):
            self.assertEqual(agenda.easter(y), dt.date(y, *want))

    def test_portugal_2026(self):
        h = agenda.holidays(2026)
        self.assertEqual(h[dt.date(2026, 4, 3)], "Good Friday")
        self.assertEqual(h[dt.date(2026, 6, 4)], "Corpus Christi")
        self.assertEqual(h[dt.date(2026, 6, 13)], "Santo António")
        self.assertEqual(h[dt.date(2026, 12, 8)], "Immaculate Conception")
        self.assertEqual(len(h), 14)
        self.assertNotIn(dt.date(2026, 6, 13), agenda.holidays(2026, ""))


class Events(unittest.TestCase):
    def setUp(self):
        self.tz = os.environ.get("TZ")
        os.environ["TZ"] = "Europe/Lisbon"
        import time
        time.tzset()

    def tearDown(self):
        import time
        if self.tz is None:
            os.environ.pop("TZ", None)
        else:
            os.environ["TZ"] = self.tz
        time.tzset()

    def test_ics(self):
        ev = agenda.events_from_ics(FIX.read_bytes(), dt.date(2026, 11, 1), dt.date(2026, 12, 1))
        study = [e for e in ev if e["title"] == "42 study group"]
        self.assertEqual([e["start"][:16] for e in study],
                         ["2026-11-02T18:00", "2026-11-09T18:00", "2026-11-16T18:00", "2026-11-23T18:00"])
        self.assertTrue(all(e["location"] == "42 Lisboa" and not e["allDay"] for e in study))
        off = next(e for e in ev if e["title"] == "ViVia offsite")
        self.assertEqual((off["start"], off["end"], off["allDay"]), ("2026-11-20", "2026-11-21", True))
        call = next(e for e in ev if e["title"] == "Call with the US")
        self.assertEqual(call["start"], "2026-11-10T15:00+00:00")       # Lisbon is UTC in November
        self.assertEqual(ev, sorted(ev, key=lambda x: (x["start"], x["title"])))
        self.assertEqual({e["calendar"] for e in ev}, {"Personal"})


if __name__ == "__main__":
    unittest.main()
