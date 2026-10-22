#!/usr/bin/env python3
"""Weather for the desktop clock (com.zinoxx.desk): Open-Meteo, no API key, cached in
~/.cache/rice/weather.json and refreshed at most every 15 minutes.

    weather.py              print the weather (fetching first when the cache is stale)
    weather.py --force      fetch now

Place: settings.json "weather": {"city": "Lisbon"} (default Lisbon, the system timezone's city),
geocoded once through Open-Meteo and remembered with its coordinates.
"""
import fcntl
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
CACHE = Path.home() / ".cache/rice"
OUT = CACHE / "weather.json"
PLACE = CACHE / "weather-place.json"
MAX_AGE = 15 * 60
HOURS = 6


def get(url):
    with urllib.request.urlopen(url, timeout=10) as r:
        return json.loads(r.read().decode())


def place(city):
    try:
        p = json.loads(PLACE.read_text())
        if p.get("query") == city:
            return p
    except (OSError, ValueError):
        pass
    r = get("https://geocoding-api.open-meteo.com/v1/search?" + urllib.parse.urlencode({"name": city, "count": 1}))
    hit = (r.get("results") or [None])[0]
    if not hit:     # a ValueError, not an exit: main() keeps the last forecast
        raise ValueError(f"no place called {city!r}")
    p = {"query": city, "name": hit["name"], "lat": hit["latitude"], "lon": hit["longitude"]}
    PLACE.write_text(json.dumps(p))
    return p


def fetch():
    try:
        cfg = json.loads((HERE / "settings.json").read_text())
    except (OSError, ValueError):
        cfg = {}
    p = place((cfg.get("weather") or {}).get("city", "Lisbon"))
    q = {"latitude": p["lat"], "longitude": p["lon"], "timezone": "auto", "forecast_days": 2,
         "current": "temperature_2m,apparent_temperature,weather_code,is_day",
         "hourly": "temperature_2m,weather_code,precipitation_probability,is_day",
         "daily": "temperature_2m_max,temperature_2m_min"}
    r = get("https://api.open-meteo.com/v1/forecast?" + urllib.parse.urlencode(q))
    cur, hr, day = r["current"], r["hourly"], r["daily"]
    now = cur["time"][:13]                          # "2026-10-16T19"
    i = next((k for k, t in enumerate(hr["time"]) if t[:13] > now), 0)
    hours = [{"h": hr["time"][k][11:13], "temp": round(hr["temperature_2m"][k]), "code": hr["weather_code"][k],
              "day": hr["is_day"][k], "pop": hr["precipitation_probability"][k]}
             for k in range(i, min(i + HOURS, len(hr["time"])))]
    out = {"place": p["name"], "updated": int(time.time()),
           "now": {"temp": round(cur["temperature_2m"]), "feels": round(cur["apparent_temperature"]),
                   "code": cur["weather_code"], "day": cur["is_day"]},
           "hi": round(day["temperature_2m_max"][0]), "lo": round(day["temperature_2m_min"][0]), "hours": hours}
    tmp = OUT.with_suffix(".tmp")
    tmp.write_text(json.dumps(out))
    tmp.replace(OUT)
    return out


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    force = "--force" in sys.argv
    with open(CACHE / "weather.lock", "w") as lock:      # three desktops ask at once: one fetch
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            data = json.loads(OUT.read_text())
            fresh = time.time() - data.get("updated", 0) < MAX_AGE
        except (OSError, ValueError):
            data, fresh = None, False
        if force or not fresh:
            try:
                data = fetch()
            except (OSError, ValueError, KeyError) as e:     # offline: keep the last one
                if data is None:
                    sys.exit(f"weather: {e}")
    print(json.dumps(data))


if __name__ == "__main__":
    main()
