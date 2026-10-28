"""The re-theme: from one wallpaper (and its screen's hand-picked colours) to the whole desktop; picking
wallpapers onto screens; loading themes (presets); the Theme page's data and the hand-picked colours."""
import json
import subprocess
import sys
from pathlib import Path

from . import apps, displays, icons, kde, kwin, palette, presets, screens, terminals, tokens, util, walls
from .util import HOME, ROOT, STATE

OV_KEYS = ("mood", "primary", "secondary", "tertiary", "intensity")
TEMPLATES = {  # template in ~/.config/plasma-rice/templates -> output; {{name}} = palette colour
    "starship.toml": HOME / ".config/starship.toml",
    "shell.zsh": HOME / ".config/zsh/rice-colors.zsh",     # read by shell/rice.zsh
}
SPLASH_PALETTE = HOME / ".local/share/plasma/look-and-feel/com.zinoxx.rice/contents/splash/palette.js"


def fail(msg):
    """Stop before anything changed, and say why where it was asked from (a shortcut or Dolphin has no terminal)."""
    util.notify("Theme not changed", msg, icon="dialog-error")
    sys.exit(f"rice.py: {msg}")


def focused_output():
    """The output KWin calls active (it follows the pointer)."""
    return util.run("qdbus6", "org.kde.KWin", "/KWin", "org.kde.KWin.activeOutputName").stdout.strip()


# ---------------------------------------------------------------- hand-picked colours
def theme_args(args):
    """--mood/--primary/... from `theme set` into an overrides dict ("auto" or "" drops a key)."""
    out = {}
    for k in OV_KEYS:
        flag = "--" + k
        if flag in args:
            i = args.index(flag)
            v = args[i + 1] if i + 1 < len(args) else ""
            if v in ("auto", ""):       # back to the wallpaper's own
                out[k] = "auto"
                continue
            if k == "mood":
                if v not in palette.MOODS + ("auto", ""):
                    sys.exit(f"mood is one of {', '.join(palette.MOODS)} or auto")
            elif k == "intensity":
                try:
                    v = max(0.3, min(1.5, float(v)))
                except ValueError:
                    sys.exit("intensity is a number, 1 = the wallpaper's own")
            elif v and not (len(v) == 7 and v.startswith("#") and all(c in "0123456789abcdefABCDEF" for c in v[1:])):
                sys.exit(f"{flag} takes a #rrggbb colour")
            out[k] = v.lower() if isinstance(v, str) else v
    return out


def theme_show(s, cfg):
    """What the Theme page needs for one screen."""
    img = Path(s["image"]) if s["image"] else None
    if not img or not img.is_file():
        return {"screen": s["name"], "image": ""}
    ov = presets.overrides().get(s["id"], {})
    auto = walls.palette_for(img, cfg)
    cur = walls.palette_for(img, cfg, ov) if ov else auto
    roles = ("primary", "secondary", "tertiary")
    return {"screen": s["name"], "id": s["id"], "image": str(img), "thumb": str(walls.thumb(img)),
            "mood": cur["_mood"], "scheme": cur["_scheme"], "autoMood": auto["_mood"],
            "detected": cur["_analysis"]["mood"], "moods": list(palette.MOODS), "lightUi": bool(cfg.get("light_ui")),
            "swatches": cur["_swatches"], "overrides": ov,
            "auto": {r: auto[r] for r in roles}, "current": {r: cur[r] for r in roles},
            "surface": cur["background"], "fg": cur["on_surface"]}


def theme_command(sub, target, args):
    """`rice.py theme show|set|reset [--screen X|all] [--mood M] [--primary HEX] ...`: show prints JSON;
    set/reset change the hand-picked colours and re-theme everything from the wallpapers as they are."""
    if sub not in ("show", "set", "reset"):
        sys.exit("rice.py theme show|set|reset")
    if sub != "show":
        util.hold_lock()        # before overrides.json is read: a re-theme running now may be writing it
    ss, cfg = screens.screens(), util.settings()
    if not ss:
        sys.exit("couldn't map the screens (is plasmashell running?)")
    asked = target
    if target == "focused":
        target = focused_output() or "all"
    pickd = [s for s in ss if target in ("all", s["name"], s["id"])]
    if not pickd:
        if asked != "focused":      # a name given by hand: a typo must not edit another screen
            sys.exit(f"no screen named {target!r} (have: {', '.join(s['name'] for s in ss)})")
        pickd = ss[:1]              # KWin's active output isn't one of the mapped screens
    if sub == "show":
        print(json.dumps(theme_show(pickd[0], cfg) if target != "all" else [theme_show(s, cfg) for s in ss]))
        return
    ovs = presets.overrides()
    for s in pickd:
        if sub == "reset":
            ovs.pop(s["id"], None)
        else:
            cur = dict(ovs.get(s["id"], {}), **theme_args(args))
            ovs[s["id"]] = {k: v for k, v in cur.items() if v not in ("", "auto", None)}
    presets.save_overrides(ovs)
    pick("restore", "all")


# ---------------------------------------------------------------- the pieces of a re-theme
def render_templates(p):
    """templates/* for this palette ({{name}}, {{name.rgb}}: util.fill)."""
    for name, out in TEMPLATES.items():
        src = ROOT / "templates" / name
        if src.exists():
            util.write_if_changed(out, util.fill(src.read_text(), p, name))


def apply_rgb():
    """Keyboards on Automatic follow the new accents (rgb.py writes only those whose colours changed).
    In the background: a keyboard is no reason to make the theme wait. Only with keyboard_lights on."""
    from . import caps
    if not caps.feature("keyboard_lights"):
        return
    subprocess.Popen([sys.executable, str(ROOT / "rgb.py"), "apply"], stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


def stage_login(p, img):
    """The login screen follows the theme: its wallpaper, colours and Plasma Style are staged for the copier
    that `boot.py login` installs (a system unit; the greeter can't read ~). Skipped until it's installed."""
    from . import caps
    if not caps.feature("login_theme") or not Path("/etc/systemd/system/atom-plasma-greeter.path").exists():
        return
    from . import boot      # numpy and PIL: only imported here, off the path of the quick commands
    boot.stage_greeter(img, kde.STYLE.get(p.get("_scheme"), "Rice"))


def write_palettes(p, tp):
    """palette.json (the theme's), Alacritty's colours, the templates and the splash's palette."""
    util.write_if_changed(STATE / "palette.json", json.dumps(p, indent=2) + "\n")
    util.write_if_changed(HOME / ".config/alacritty/plasma-rice.toml", terminals.alacritty(tp))
    render_templates(tp)
    util.write_if_changed(SPLASH_PALETTE, ".pragma library\n// Written by ~/.config/plasma-rice/rice.py\n"
                          f"var wallpaper = {json.dumps(p.get('_wallpaper', ''))};\n"
                          f"var colors = {json.dumps({k: v for k, v in p.items() if not k.startswith('_')})};\n")


def retheme(ss, img, cfg):
    """Everything from the theme-driving wallpaper `img` (with its screen's hand-picked colours). Each step
    stands alone: one that fails is logged and the others still run. Returns the failed steps."""
    lead_ov = presets.overrides().get(presets.lead_screen(ss), {}) if ss else {}
    p = walls.with_meta(walls.palette_for(img, cfg, lead_ov), img)
    tp = walls.dark_twin(p, img, cfg, lead_ov)        # terminals and apps stay dark
    steps = [
        # per-screen palettes first: the widgets re-read theirs when the colour scheme changes below
        ("screens", screens.apply_screens, ss, cfg, p),
        ("palettes", write_palettes, p, tp),
        ("Plasma Style", kde.apply_style, p),
        ("colour scheme", kde.apply_scheme, p),
        ("login screen", stage_login, p, img),
        ("window borders", kwin.apply_kwin, p),
        ("Konsole", terminals.apply_konsole, tp),
        ("icons", icons.apply, tp["primary"], cfg.get("icon_theme", "Papirus-Rice")),
        ("apps", apps.apply, tp),
        ("keyboards", apply_rgb),
    ]
    failed = []
    for name, fn, *args in steps:
        try:
            fn(*args)
        except Exception as e:
            util.warn("%s: %s: %s", name, type(e).__name__, e)
            failed.append(name)
    return failed


# ---------------------------------------------------------------- picks
def preset_prepare(name, ss):
    """Puts a preset's wallpapers on every screen but the one that drives the theme (presets.plan: the same
    monitor, else by role, else the main screen's), and its hand-picked colours (or none) in place, and returns
    (that image, that screen's connector, the preset's name), which pick() then themes from like any other pick.
    A wallpaper that's gone or unusable leaves that screen as it is."""
    p = presets.find_preset(presets.presets(), name)
    if not p:
        sys.exit(f"no preset named {name!r}")
    want = {i: w for i, w in presets.plan(p, ss).items() if not walls.unusable(Path(w["image"]))}
    if not want:
        sys.exit(f"none of {p['name']!r}'s wallpapers can be shown any more")
    by_id = {s["id"]: s for s in ss}
    # the theme's lead screen if it's here, else the screen showing the theme's wallpaper, else the main one
    lead = p.get("lead") if p.get("lead") in want else \
        next((i for i, w in want.items() if w["image"] == p.get("theme")),
             next((s["id"] for s in ss if s["main"] and s["id"] in want), next(iter(want))))
    presets.save_overrides({i: w["overrides"] for i, w in want.items() if w["overrides"]})
    for i, w in want.items():
        if i != lead and by_id[i]["image"] != w["image"]:
            screens.set_images([by_id[i]], Path(w["image"]))
            by_id[i]["image"] = w["image"]
    return want[lead]["image"], by_id[lead]["name"], p["name"]


def pick(arg, target="focused", preset=""):
    """A wallpaper (next | prev | random | restore | a file) on the target screens (all | focused | an
    output), or a theme (preset) loaded, then the whole re-theme. Exits non-zero if a step failed."""
    util.hold_lock()
    tokens.write()      # qml/Rice/Tokens.qml, from the design tokens
    ss = screens.screens()
    if preset:      # load: the other screens first, then the lead one themes everything like a pick
        arg, target, preset = preset_prepare(preset, ss)
    if target == "focused":
        target = focused_output() or "all"
    chosen = [s for s in ss if target in ("all", s["name"], s["id"])]
    if ss and not chosen:
        sys.exit(f"no screen named {target!r} (have: {', '.join(s['name'] for s in ss)})")

    one = chosen[0] if len(chosen) == 1 else None
    img = walls.pick(arg, cur=Path(one["image"]).resolve() if one and one["image"] else None,
                     taken={Path(s["image"]).resolve() for s in ss if s["image"]})
    if why := walls.unusable(img):      # before anything changes: a file the palette can't read would leave a half theme
        fail(f"{img.name} {why}")
    if arg != "restore" and chosen:
        if not preset:      # a new wallpaper: back to its own colours (a loaded preset brings its own)
            presets.save_overrides({i: v for i, v in presets.overrides().items() if i not in {s["id"] for s in chosen}})
        focused = focused_output()
        lead = one if one else next((s for s in chosen if s["name"] == focused), chosen[0])
        presets.set_lead(lead["id"])
    cfg = util.settings()
    tmp = STATE / "wallpaper.tmp"
    tmp.unlink(missing_ok=True)
    tmp.symlink_to(img)
    tmp.replace(walls.CURRENT)

    if arg != "restore":
        if ss:
            screens.set_images(chosen, img)
            for s in chosen:
                s["image"] = str(img)
        else:   # couldn't map screens: old behaviour, every desktop
            util.run("plasma-apply-wallpaperimage", str(img))
        kde.set_lockscreen(img)

    failed = retheme(ss, img, cfg)
    if arg != "restore":
        where = one["label"] if one and len(ss) > 1 else "all screens" if len(ss) > 1 else ""
        util.notify("Theme updated", f"Preset “{preset}”" if preset else img.name + (f" · {where}" if where else ""),
                    icon=walls.thumb(img))  # not the full image: plasmashell decodes the icon
    if failed:
        sys.exit(f"rice.py: not applied: {', '.join(failed)} (see {util.LOG_FILE})")


def screens_changed():
    """Screens plugged in, out or rearranged: the whole rice on every screen (atom/reconcile.py), and an odd
    arrangement (overlaps, a screen apart) offered a fix in a notification. That notification waits for an
    answer, so it runs in the background and the rest goes on."""
    subprocess.Popen([sys.executable, str(ROOT / "rice.py"), "displays", "--ask"], stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    from . import reconcile
    reconcile.run()


# ---------------------------------------------------------------- UI size
def ui_info(ds=None, cfg=None):
    """The Theme page's Size controls: the settings and, per screen, its standard and effective size."""
    cfg = util.settings() if cfg is None else cfg
    ds = displays.probe() if ds is None else ds
    ui = cfg.get("ui") or {}
    own = cfg.get("displays") or {}
    return {"auto": ui.get("auto", True), "size": ui.get("size", 1.0),
            "screens": [{"name": d.connector, "id": d.id, "label": d.label, "title": d.name,
                         "standard": displays.comfort(d), "size": displays.ui_scale(d, cfg),
                         "own": (own.get(d.id) or {}).get("size"), "scaleAdvice": displays.scale_advice(d)}
                        for d in ds]}


def ui_set(args, screen=None):
    """`rice.py ui set`: change the UI size settings, then apply them everywhere (palettes, bars, clocks)."""
    def val(flag):
        i = args.index(flag)
        return args[i + 1] if i + 1 < len(args) else ""

    util.hold_lock()
    cfg = util.user_settings()
    ui = cfg.setdefault("ui", {})
    if "--auto" in args:
        ui["auto"] = val("--auto").lower() in ("1", "true", "on", "yes")
    if "--size" in args:
        try:
            ui["size"] = round(max(0.5, min(2.5, float(val("--size")))), 2)
        except ValueError:
            sys.exit("--size is a number (1 = the standard size)")
    if "--own" in args:
        ds = displays.probe()
        key = screen or focused_output()
        d = next((d for d in ds if key in (d.connector, d.id)), None)
        if not d:
            sys.exit(f"no screen {key!r}")
        own = cfg.setdefault("displays", {}).setdefault(d.id, {})
        v = val("--own")
        if v in ("auto", ""):
            own.pop("size", None)
        else:
            try:
                own["size"] = round(max(0.6, min(3.5, float(v))), 2)
            except ValueError:
                sys.exit("--own is a number or auto")
        cfg["displays"] = {k: v for k, v in cfg["displays"].items() if v}
    util.save_settings(cfg)
    from . import reconcile
    reconcile.run()


def setup():
    """The one-shot desktop settings that don't follow the wallpaper: window chrome, Dolphin, Darkly."""
    kwin.setup_chrome()
    apps.setup()


# ---------------------------------------------------------------- what the picker shows
def screens_info(ss=None):
    """Screens left to right, for the picker: screens() plus each one's thumbnail, whether it drives the
    theme, its hand-picked colours and its accent."""
    ss = screens.screens() if ss is None else ss
    lead, ovs = presets.lead_screen(ss), presets.overrides()
    for s in ss:
        s["thumb"] = str(walls.thumb(Path(s["image"]))) if s["image"] else ""
        s["lead"] = s["id"] == lead                     # its wallpaper drives the system theme
        s["overrides"] = ovs.get(s["id"], {})           # hand-picked colours
        s["accent"] = (util.load_json(STATE / f"palette-{s['name']}.json") or {}).get("primary", "")
    return ss


def presets_info(ss=None):
    """The themes, each with its thumbnails and whether it's the one on screen right now. `thumbs` maps the
    screens now (connectors) to what loading it would put there; `layout` is what it was saved on (with each
    saved screen's thumbnail) and `plan` how it maps onto the screens now (same / role / mirror)."""
    ss = screens.screens() if ss is None else ss
    on = presets.current_theme(ss, presets.overrides())
    by_id = {s["id"]: s for s in ss}
    out = []
    for p in presets.presets():
        plan = presets.plan(p, ss)
        layout = [dict(e, thumb=str(walls.thumb(Path(e["image"]))) if Path(e["image"]).is_file() else "")
                  for e in p.get("layout", [])]
        out.append(dict(p, layout=layout, current=p["name"] == on,
                        overrides=any(e.get("overrides") for e in layout),
                        thumbs={by_id[i]["name"]: str(walls.thumb(Path(w["image"])))
                                for i, w in plan.items() if Path(w["image"]).is_file()},
                        plan={by_id[i]["name"]: {"how": w["how"], "from": w["from"]} for i, w in plan.items()}))
    return out


def page():
    """Everything the Theme page shows, in one go (one process instead of three)."""
    ss = screens.screens()
    ds = displays.probe()
    issues = displays.check(ds)
    fix = displays.proposal(ds) if issues["overlaps"] or issues["apart"] else ""
    try:
        current = str(walls.CURRENT.resolve(strict=True))
    except OSError:
        current = ""
    return {"dir": str(walls.WALLDIR), "current": current,
            "walls": [{"name": w.name, "path": str(w), "thumb": str(walls.thumb(w))} for w in walls.walls()],
            "screens": screens_info([dict(s) for s in ss]), "presets": presets_info(ss),
            "presetLen": presets.PRESET_LEN, "moods": list(palette.MOODS), "ui": ui_info(ds),
            "arrangement": {"problem": displays.describe(issues, ds), "fix": fix}}
