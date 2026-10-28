"""The wallpapers: the collection, picking one (next / prev / random / a file), whether a file can be one at
all, its thumbnail, and the palette it gives (cached per image, settings and overrides)."""
import hashlib
import json
import random
import sys
from pathlib import Path

from . import palette, util
from .util import CACHE, STATE

WALLDIR = util.wallpaper_dir()          # settings.json wallpaper_dir, else Pictures/Wallpapers
THUMBS = CACHE / "thumbs-plasma"
CURRENT = STATE / "wallpaper"           # the last wallpaper picked: it drives the global theme


# what both Pillow (the palette, the layout) and ImageMagick (thumbnails, glass, the login screen) read here;
# the Dolphin menu's MimeType (~/.local/share/kio/servicemenus/rice.desktop) offers the same
EXTS = {".jpg", ".jpeg", ".png", ".webp"}


def walls():
    return sorted(p for p in WALLDIR.iterdir() if p.suffix.lower() in EXTS) if WALLDIR.is_dir() else []


def thumb(img):
    out = THUMBS / (img.stem + ".jpg")
    if not out.exists() or out.stat().st_mtime < img.stat().st_mtime:
        THUMBS.mkdir(parents=True, exist_ok=True)
        util.run("magick", str(img) + "[0]", "-resize", "480x270^", "-gravity", "center",
                 "-extent", "480x270", "-quality", "88", str(out))
    return out


def portrait(img):
    """Is this picture taller than wide? (None if it can't be read; only the header is.)"""
    from PIL import Image
    try:
        with Image.open(img) as im:
            return im.height > im.width
    except OSError:
        return None


def pick(arg, cur=None, taken=(), portrait_screen=None):
    """cur: the wallpaper next/prev step from (default: the last one picked);
    taken: wallpapers on other screens, which random avoids when it can;
    portrait_screen: True/False for a screen standing up or not: next, prev and random keep to pictures of
    the same orientation when the collection has any (None: any picture)."""
    ws = walls()
    if portrait_screen is not None and arg in ("next", "prev", "random"):
        fit = [w for w in ws if portrait(w) == portrait_screen]
        if fit:
            ws = fit if cur is None or cur in fit else sorted(fit + [cur])
    if cur is None or arg == "restore":
        try:
            cur = CURRENT.resolve(strict=True)
        except OSError:
            cur = None
    if arg in ("next", "prev"):
        if not ws:
            sys.exit("no wallpapers in " + str(WALLDIR))
        i = ws.index(cur) if cur in ws else -1
        return ws[(i + (1 if arg == "next" else -1)) % len(ws)]
    if arg == "random":
        return random.choice([w for w in ws if w != cur and w not in taken] or [w for w in ws if w != cur] or ws)
    if arg == "restore":
        return cur if cur and cur.exists() else (ws[0] if ws else sys.exit("no wallpaper"))
    p = Path(arg).expanduser().resolve()
    if not p.is_file():
        sys.exit(f"not a file: {p}")
    return p


def unusable(img):
    """Why `img` can't be a wallpaper here, or "" if it can."""
    if img.suffix.lower() not in EXTS:
        return f"isn't a supported format (only {', '.join(sorted(EXTS))})"
    try:
        from PIL import Image
        with Image.open(img) as im:
            if im.format == "JPEG":     # verify() only reads a JPEG's header: decode it, at a fraction of its size
                im.draft("RGB", (480, 270))
                im.load()
            else:                       # PNG: every chunk's CRC, without decoding 20 MB of pixels
                im.verify()
    except Exception as e:      # missing, unreadable, not an image, truncated
        return f"can't be read ({e})"
    return ""


PALETTE_SETTINGS = ("light_ui", "soft_tint", "depth")     # the settings build_v2 reads


def palette_for(img, cfg, ov=None):
    """palette v2 (the wallpaper's own colours and character: palette.analyse + build_v2), cached per
    image, palette settings and overrides (a pick touches up to three screens)."""
    ov = ov or {}
    cfg = {k: cfg[k] for k in PALETTE_SETTINGS if k in cfg}     # a bar or clock size change keeps the cache
    key = hashlib.sha1(json.dumps(["v2", str(img), img.stat().st_mtime, cfg, ov], sort_keys=True).encode()).hexdigest()[:16]
    f = CACHE / "palettes" / f"{key}.json"
    try:
        return json.loads(f.read_text())
    except (OSError, ValueError):
        pass
    p = palette.build_v2(palette.analyse(img), cfg, ov)
    util.write_if_changed(f, json.dumps(p))
    return p


def with_meta(p, img):
    return dict(p, _wallpaper=str(img), _thumb=str(thumb(img)))


def dark_twin(p, img, cfg, ov=None):
    """Terminals, VS Code, Zen, btop and the prompt stay dark in every mood: for a light palette,
    the same wallpaper drawn the dark way (graphite/soft, palette.build_v2 without light_ui)."""
    if p.get("_scheme") != "light" or not img:
        return p
    ov = {k: v for k, v in (ov or {}).items() if k != "mood"}
    return with_meta(palette_for(img, dict(cfg, light_ui=False), ov), img)
