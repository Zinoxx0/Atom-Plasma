"""Every wallpaper as the theme engine sees it, for the launcher's colour wheel (Atom's Theme page): its mood, its hue,
how light and how colourful it is, and the palette a re-theme would build from it (to preview the page in it).

`rice.py walls-index` writes ~/.cache/rice/walls-index.json, analysing only new or changed files (keyed by name, size
and mtime; ~0.3 s a wallpaper, in parallel), and says where it is. A file the engine can't read is listed under `bad`.
"""
import json
import os
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from . import util, walls

OUT = util.CACHE / "walls-index.json"
VERSION = 1


def _palette_keys(p):
    """What the preview needs: every colour role, the scheme and the mood."""
    return {k: v for k, v in p.items() if (isinstance(v, str) and v.startswith("#")) or k in ("_scheme", "_mood", "_glow")}


def analyse(path, settings):
    from . import palette
    a = palette.analyse(str(path))
    p = palette.build_v2(a, settings)
    return {"mood": palette.mood_of(a), "hue": round(a["hue"], 1), "L": round(a["L"], 3), "C": round(a["C"], 3),
            "pal": _palette_keys(p), "thumb": str(walls.thumb(Path(path)))}


def _job(args):
    path, settings = args
    try:
        return path, analyse(path, settings), None
    except Exception as e:          # a file the engine can't open (a broken PNG chunk, ...)
        return path, None, type(e).__name__


def build(files=None, out=OUT, settings=None, workers=None):
    settings = util.settings() if settings is None else settings
    files = list(walls.walls()) if files is None else [Path(f) for f in files]
    try:
        old = json.loads(Path(out).read_text())
        if old.get("version") != VERSION or old.get("light_ui") != bool(settings.get("light_ui")):
            old = {}
    except (OSError, ValueError):
        old = {}
    known = old.get("walls", {})
    bad = {}
    entries, todo = {}, []
    for f in files:
        try:
            st = f.stat()
        except OSError:
            continue
        sig = f"{st.st_size}:{int(st.st_mtime)}"
        if known.get(f.name, {}).get("sig") == sig:
            entries[f.name] = known[f.name]
        elif old.get("bad", {}).get(f.name) == sig:
            bad[f.name] = sig
        else:
            todo.append((f, sig))
    if todo:
        with ProcessPoolExecutor(max_workers=workers or max(1, (os.cpu_count() or 2) - 1)) as ex:
            for (f, sig), (_, res, err) in zip(todo, ex.map(_job, [(f, settings) for f, _ in todo])):
                if res is None:
                    bad[f.name] = sig
                else:
                    entries[f.name] = dict(res, sig=sig, path=str(f))
    data = {"version": VERSION, "light_ui": bool(settings.get("light_ui")), "walls": entries, "bad": bad}
    util.write_if_changed(out, json.dumps(data, sort_keys=True, separators=(",", ":")))
    return data


def write():
    """`rice.py walls-index`: bring the index up to date; says where it is."""
    build()
    return str(OUT)
