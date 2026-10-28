#!/usr/bin/env python3
"""Fetch new wallpapers from wallhaven.cc into the collection (settings wallpaper_dir, else Pictures/Wallpapers).

    wallhaven.py [--dry-run] [--screen focused|<output>|<display id>] [count] [tags]

tags: comma-separated, e.g. "modern, clean, aesthetic". wallhaven finds nothing for
most multi-word queries, so each tag is searched on its own and the results are
ranked: pictures found under more of the tags first, then the tags take turns, each
giving its most favourited picture you don't have yet. So every click brings the
next best ones. Without tags, one of "wallhaven_queries" (settings.json) is used.

A tag with few results is helped along: vibe words ("cozy", "modern"...) are
translated into tags wallhaven knows (VIBES), a phrase is split into its words, and
otherwise the search widens from anime to general art (minus photography).

SFW only, shaped for the screen they're for (--screen, default the focused one; shape(): its aspect ratio,
portrait or not, and a minimum size from its resolution), anime category first (settings
"wallhaven_categories", default "010"). Character art is left out by default
(settings "wallhaven_exclude", default ["anime girls"]): scenery is the point,
unless the tags ask for people (girl, boy, character...). Pictures fetched before are remembered in
~/.cache/rice/wallhaven-seen.json, so ones you deleted don't come back.
Prints JSON: {"query", "tags", "saved": [paths], "thin": [tags that found nothing]};
--dry-run prints the picks instead of downloading them.
"""
import json
import random
import re
import sys
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from atom import util

SEEN = util.CACHE / "wallhaven-seen.json"
API = "https://wallhaven.cc/api/v1/search?"
UA = {"User-Agent": "plasma-rice/1.0"}
DEFAULT_QUERIES = ["landscape", "scenery", "night city", "sky", "sunset", "mountains", "lake"]
THIN = 12           # fewer results than this: try harder
MAX_PAGES = 3

# vibe words wallhaven has (almost) no pictures for -> tags it does have
VIBES = {
    "aesthetic": ["pastel", "lofi", "minimalism"],
    "cozy": ["room", "interior", "rain"], "cosy": ["room", "interior", "rain"], "comfy": ["room", "interior"],
    "chill": ["landscape", "clouds"], "calm": ["landscape", "sky"], "relaxing": ["landscape", "clouds"],
    "peaceful": ["nature", "landscape"], "serene": ["nature", "sky"],
    "modern": ["architecture", "city"], "urban": ["city", "night"],
    "futuristic": ["cyberpunk", "science fiction"], "scifi": ["science fiction", "cyberpunk"],
    "sci-fi": ["science fiction", "cyberpunk"],
    "retro": ["retrowave", "vaporwave"], "synthwave": ["retrowave"],
    "dreamy": ["clouds", "sky"], "moody": ["dark", "rain"], "gloomy": ["dark", "rain"],
    "melancholic": ["rain", "alone"], "sad": ["rain", "alone"], "lonely": ["alone", "night"],
    "vibrant": ["colorful"], "colourful": ["colorful"], "cinematic": ["landscape", "sunset"],
    "warm": ["sunset", "autumn"], "cold": ["snow"], "wintery": ["snow"], "fresh": ["spring", "nature"],
    "magical": ["stars", "night"], "minimal": ["minimalism"], "simple": ["minimalism"],
}


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
        return r.read()


def shape(d):
    """wallhaven's `ratios` and `atleast` for a display: its own aspect (and the ones close enough that the
    crop doesn't hurt), portrait for portrait screens, and a minimum size from its resolution."""
    if d is None:
        return "16x9", "2560x1440"
    w, h = (d.px_h, d.px_w) if d.rotation in (2, 8) else (d.px_w, d.px_h)
    a = w / max(1, h)
    ratios = ("9x16,9x18,10x16" if a < 0.8 else "1x1,5x4,4x3" if a < 1.2 else "4x3,5x4,16x10" if a < 1.45
              else "16x10,3x2,16x9" if a < 1.7 else "16x9" if a < 2.1 else "21x9,32x9,48x9")
    long = max(w, h)
    # the long side: the screen's own, but up to 1.5x upscaling is fine (good pictures stay findable), never
    # above 3840 (an 8K finds next to nothing at 7680). Landscape pictures go to a shared collection that any
    # screen may show later, so they're never below 2560; odd shapes (portrait, square, ultrawide) are for
    # screens like this one only, so their own size is enough
    floor = 2560 if "16x9" in ratios else min(long, 2560)
    want = min(3840, max(long / 1.5, floor))
    k = want / long
    return ratios, f"{round(w * k)}x{round(h * k)}"


class Search:
    """One wallhaven query, read a page at a time, most favourited first."""
    exclude = ""
    ratios, atleast = "16x9", "2560x1440"       # set from the target screen (shape())

    def __init__(self, q, cats):
        self.q, self.cats, self.page, self.last, self.items, self.total = q, cats, 0, 1, [], 0
        self.key = None     # tag aliases ("clean" = "minimalism") give the same results: same key

    def more(self):
        if self.page >= min(self.last, MAX_PAGES):
            return False
        self.page += 1
        params = {"q": self.q + Search.exclude, "categories": self.cats, "purity": "100", "atleast": Search.atleast,
                  "ratios": Search.ratios, "sorting": "favorites", "order": "desc", "page": self.page}
        d = json.loads(get(API + urllib.parse.urlencode(params)))
        self.items += d["data"]
        self.last = d["meta"]["last_page"]
        self.total = d["meta"]["total"]
        if self.key is None:
            self.key = (self.total, tuple(it["id"] for it in d["data"][:8]))
        return True


def resolve(tag, cats):
    """The searches that stand for one tag."""
    s = Search(tag, cats)
    s.more()
    if s.total >= THIN:
        return [s]
    out = [s] if s.total else []
    words = tag.lower().split()
    if tag.lower() in VIBES:
        out += [Search(t, cats) for t in VIBES[tag.lower()]]
    elif len(words) > 1:
        for w in words:
            out += resolve(w, cats)
    elif cats != "110":
        out.append(Search(tag + " -photography", "110"))
    for x in out:
        if not x.page:
            x.more()
    return [x for x in out if x.total]


def target(key):
    """The display the wallpapers are for (focused = KWin's active output), or None if it can't be told."""
    from atom import displays
    ds = displays.probe()
    if key == "focused":
        r = util.run("qdbus6", "org.kde.KWin", "/KWin", "org.kde.KWin.activeOutputName", quiet=True)
        key = r.stdout.strip() if r else ""
    return next((d for d in ds if key in (d.connector, d.id)), next((d for d in ds if d.primary), None))


def main():
    args = sys.argv[1:]
    dry = "--dry-run" in args
    args = [a for a in args if a != "--dry-run"]
    screen = "focused"
    if "--screen" in args:
        i = args.index("--screen")
        screen = args[i + 1] if i + 1 < len(args) else "focused"
        del args[i:i + 2]
    Search.ratios, Search.atleast = shape(target(screen))
    count = int(args[0]) if args else 6
    cfg = util.settings()
    WALLDIR = util.wallpaper_dir(cfg)
    query = args[1].strip() if len(args) > 1 else ""
    if not query:
        query = random.choice(cfg.get("wallhaven_queries") or DEFAULT_QUERIES)
    tags = [t.strip() for t in re.split(r"[,;]+", query) if t.strip()][:6]
    cats = cfg.get("wallhaven_categories") or "010"
    exclude = cfg.get("wallhaven_exclude", ["anime girls"])
    if not re.search(r"girl|boy|character|people|person|waifu|anime girls", query, re.I):
        Search.exclude = "".join(f' -"{t}"' for t in exclude)

    WALLDIR.mkdir(parents=True, exist_ok=True)
    try:
        seen = set(json.loads(SEEN.read_text()))
    except (OSError, ValueError):
        seen = set()
    have = {p.stem.removeprefix("wallhaven-") for p in WALLDIR.iterdir()}
    skip = seen | have

    per_tag = [resolve(t, cats) for t in tags]
    thin = [t for t, ss in zip(tags, per_tag) if not ss]

    def pool():
        """tag index -> its unseen pictures, most favourited first; plus how many tags found
        each, counting a tag only when it found it through a different search than the others"""
        lists, tags_of, keys_of = [], {}, {}
        for ss in per_tag:
            items = {}
            for s in ss:
                for it in s.items:
                    if it["id"] not in skip:
                        items[it["id"]] = it
                        keys_of.setdefault(it["id"], set()).add(s.key)
            ranked = sorted(items.values(), key=lambda it: -it.get("favorites", 0))
            for it in ranked:
                tags_of[it["id"]] = tags_of.get(it["id"], 0) + 1
            lists.append(ranked)
        return lists, {i: min(n, len(keys_of[i])) for i, n in tags_of.items()}

    lists, hits = pool()
    # not enough new ones on the first pages: read further
    while sum(len(l) for l in lists) < count * 2 and any(s.more() for ss in per_tag for s in ss):
        lists, hits = pool()

    picks, taken = [], set()
    for it in sorted({i["id"]: i for l in lists for i in l}.values(), key=lambda it: (-hits[it["id"]], -it.get("favorites", 0))):
        if hits[it["id"]] > 1 and len(picks) < count:          # found under several tags
            picks.append(it); taken.add(it["id"])
    while len(picks) < count and any(lists):
        for l in lists:                                        # then the tags take turns
            while l and l[0]["id"] in taken:
                l.pop(0)
            if l and len(picks) < count:
                it = l.pop(0)
                picks.append(it); taken.add(it["id"])

    if dry:
        print(json.dumps({"query": query, "tags": tags, "thin": thin,
                          "searches": [[f"{x.q} [{x.cats}] {x.total}" for x in ss] for ss in per_tag],
                          "picks": [{"id": it["id"], "fav": it.get("favorites"), "tags": hits[it["id"]],
                                     "thumb": it["thumbs"]["small"]} for it in picks]}, indent=1))
        return

    def fetch(it):
        url = it["path"]
        dest = WALLDIR / Path(urllib.parse.urlparse(url).path).name    # wallhaven-<id>.<ext>
        tmp = dest.with_name(dest.name + ".part")
        try:
            tmp.write_bytes(get(url))
            tmp.replace(dest)
            return str(dest)
        except OSError:
            tmp.unlink(missing_ok=True)
            return None

    with ThreadPoolExecutor(4) as ex:
        saved = [p for p in ex.map(fetch, picks) if p]
    SEEN.parent.mkdir(parents=True, exist_ok=True)
    SEEN.write_text(json.dumps(sorted(seen | have | {Path(p).stem.removeprefix("wallhaven-") for p in saved})))
    print(json.dumps({"query": query, "tags": tags, "saved": saved, "thin": thin}))


if __name__ == "__main__":
    main()
