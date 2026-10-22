"""KWin: the window border colours that follow each screen's palette (apply_kwin, on every re-theme), and
the rest of the window chrome, set once by setup_chrome() (`rice.py setup`): those aren't palette-driven,
so a change made in System Settings stays changed until setup runs again."""
from . import kde, palette, tokens, util
from .util import HOME, ROOT, STATE

KWIN_EFFECTS = {   # effect id -> on; rice_* live in plasma-rice/kwin (setup_chrome links them for KWin)
    "rice_window": True,            # open/close: fade + small scale (replaces glide / scale)
    "rice_popups": True,            # menus, tooltips: fade + short slide (replaces fadingpopups)
    "kwin6_effect_glide": False, "scale": False, "fadingpopups": False,
    # rounded corners + window border: the local build (pkg/kwin-effect-rounded-corners-rice) that
    # colours each window's border from its own screen's palette, under its own id
    "kwin4_effect_shapecorners": False, "kwin4_effect_shapecorners_rice": True,
}
CORNERS = "kwin4_effect_shapecorners_rice"
BLUR_CLASSES = ["zen", "dolphin", "Alacritty"]   # force-blurred: these don't ask for blur KWin 6.7 understands
FX = "org.kde.kwin.Effects"


def effects(method, *args):
    return util.run("qdbus6", "org.kde.KWin", "/Effects", f"{FX}.{method}", *args)


def apply_kwin(p):
    """The active window's gradient border (primary -> tertiary, HyDE style), in the palette of the screen
    the window is on ([Round-Corners][Output <name>], read by the patched local build; `p`, the theme's
    palette, is the fallback)."""
    c = palette.rgb_csv
    corners = kde.kde_set("kwinrc", {"Round-Corners": {
        "OutlineColor": c(p["primary"]), "OutlineColor2": c(p["tertiary"]),
        "InactiveOutlineColor": c(p["outline_variant"]), "InactiveOutlineColor2": c(p["outline_variant"])}})
    for f in sorted(STATE.glob("palette-*.json")):
        sp = util.load_json(f)
        if not sp:
            continue
        corners |= kde.kde_set("kwinrc", {("Round-Corners", f"Output {f.stem.removeprefix('palette-')}"): {
            "OutlineColor": c(sp["primary"]), "OutlineColor2": c(sp["tertiary"]),
            "InactiveOutlineColor": c(sp["outline_variant"])}})
    if corners:
        effects("reconfigureEffect", CORNERS)


def setup_chrome():
    """Window chrome, once. ShapeCorners clips every window to the windows radius (tokens md); Klassy draws
    the titlebar and a neutral shadow with the same round corner (a squircle clip would leave Klassy's
    round shadow peeking out at the corners; a tinted shadow can't follow the screen). The rice's window
    motion effects on, the blur settings, and the rice effects linked where KWin finds them."""
    r = tokens.TOKENS["radius"]["md"]
    corners = kde.kde_set("kwinrc", {"Round-Corners": {
        "Size": r, "InactiveCornerRadius": r, "UseSquircleShape": False, "UseNativeDecorationShadows": True}})
    blur = kde.kde_set("kwinrc", {"Effect-better-blur-dx": {"BlurStrength": 8, "WindowClasses": "\n".join(BLUR_CLASSES)}})
    deco = kde.kde_set("kwinrc", {"org.kde.kdecoration2": {"ButtonsOnLeft": "M", "ButtonsOnRight": "IAX"}})
    deco |= kde.kde_set("klassy/klassyrc", {
        "Windeco": {"WindowCornerRadius": r},
        "ShadowStyle": {"ShadowSizeActive": "ShadowLarge", "ShadowStrengthActive": 230,
                        "ShadowColorActive": "0,0,0",
                        "ShadowSizeInactive": "ShadowMedium", "ShadowStrengthInactive": 150,
                        "ShadowColorInactive": "0,0,0"}})
    kde.kde_set("kwinrc", {"Plugins": {f"{e}Enabled": on for e, on in KWIN_EFFECTS.items()}})
    if corners:
        effects("reconfigureEffect", CORNERS)
    if blur:
        effects("reconfigureEffect", "better_blur_dx")
    if deco:    # decorations only re-read their settings on a KWin reconfigure (scripts stay as they are)
        util.run("qdbus6", "org.kde.KWin", "/KWin", "org.kde.KWin.reconfigure")
    installed = HOME / ".local/share/kwin/effects"
    for src in (ROOT / "kwin").iterdir():
        link = installed / src.name
        if link.is_symlink() or link.exists():
            continue
        installed.mkdir(parents=True, exist_ok=True)
        link.symlink_to(src)
    loaded = set(effects("loadedEffects").stdout.split())
    for e, on in KWIN_EFFECTS.items():
        if on != (e in loaded):
            effects("loadEffect" if on else "unloadEffect", e)
