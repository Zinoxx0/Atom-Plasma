"""Auto-tiling per screen (Krohnkite): which screens tile, kept by display id, floating by default.

Krohnkite must never be unloaded or reloaded inside a running session (a second load comes up broken:
"Qt.createQmlObject(): Missing parent object" until KWin restarts), so it stays loaded and a screen is
switched between its Tile and Floating layouts. Krohnkite acts on the screen of the focused window; to switch
another screen, a one-shot KWin script focuses that screen's desktop window, invokes the layout shortcut and
gives focus back.

Krohnkite only reads which screens float (kwinrc [Script-krohnkite] screenDefaultLayout) when it loads at
login, and a screen it hasn't seen comes up tiled. So that list is rewritten from the state for every
connector a floating monitor has used, and a screen plugged in mid-session is set live (apply_new()).
Entries name the layout by index: Krohnkite 0.9.9.2's FloatingLayout id has a trailing space, so
"DP-1:floating" never matches.

State: ~/.local/state/rice/tiling.json {"tile": [display ids], "available": bool, "screens": {connector:
"tile"|"float"}} (`screens` is for the bar toggles, which know their screen by connector).
"""
import xml.etree.ElementTree as ET
from pathlib import Path

from . import displays, kwinscript, util
from .util import HOME, RUNTIME, STATE

STATE_FILE = STATE / "tiling.json"
SEEN = RUNTIME / "atom-tiling-seen"         # connectors set this session (cleared at reboot)
SCRIPT = HOME / ".local/share/kwin/scripts/krohnkite"


def state():
    return util.load_json(STATE_FILE, {}) or {}


def tiled_ids():
    return set(state().get("tile", []))


def available():
    return SCRIPT.is_dir()


def loaded():
    r = util.run("qdbus6", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.isScriptLoaded", "krohnkite",
                 quiet=True)
    return r is not None and r.stdout.strip() == "true"


def float_index():
    """FloatingLayout's place in Krohnkite's layout list: the enabled layouts (order > 0) by their order, as
    Krohnkite builds it. Defaults come from its own config file (an update that adds layouts is followed),
    kwinrc holds the user's changes."""
    ns = "{http://www.kde.org/standards/kcfg/1.0}"
    try:
        root = ET.parse(SCRIPT / "contents/config/main.xml").getroot()
    except (OSError, ET.ParseError):
        return 8
    layouts = []
    for e in root.iter(ns + "entry"):
        name = e.get("name", "")
        if name.endswith("LayoutOrder"):
            default = (e.findtext(ns + "default", "0") or "0").strip()
            r = util.run("kreadconfig6", "--file", "kwinrc", "--group", "Script-krohnkite", "--key", name,
                         "--default", default, quiet=True)
            try:
                order = int((r.stdout if r else "").strip() or default)
            except ValueError:
                order = 0
            if order > 0:
                layouts.append((order, name))
    names = [n for _, n in sorted(layouts, key=lambda t: t[0])]
    return names.index("floatingLayoutOrder") if "floatingLayoutOrder" in names else 8


def write_defaults(ds, tile):
    """Krohnkite's screenDefaultLayout: every connector a floating monitor has used (from the registry), so it
    comes up floating at the next login wherever it's plugged in."""
    reg = displays.registry()
    conns = set()
    for i, e in reg.items():
        if i not in tile:
            conns.update(e.get("connectors", []))
    conns.update(d.connector for d in ds if d.id not in tile)
    conns -= {d.connector for d in ds if d.id in tile}          # a connector a tiled monitor is on now
    idx = float_index()
    value = ",".join(f"{c}:{idx}" for c in sorted(conns))
    args = ["kwriteconfig6", "--file", "kwinrc", "--group", "Script-krohnkite", "--key", "screenDefaultLayout"]
    util.run(*(args + ([value] if value else ["--delete"])))


LAYOUT_JS = """
var target = null;
workspace.screens.forEach(function (o) { if (o.name === %(conn)s) target = o; });
if (!target) { answer("no-screen"); }
else {
    var before = workspace.activeWindow, desk = null;
    workspace.stackingOrder.forEach(function (w) { if (w.desktopWindow && w.output === target) desk = w; });
    if (desk) workspace.activeWindow = desk;
    callDBus("org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component", "invokeShortcut",
             %(shortcut)s, function () {
        if (before && before !== desk) workspace.activeWindow = before;
        answer(desk ? "ok" : "no-desktop");
    });
}
"""


def set_live(conn, tile):
    """Switch one screen's layout now, without moving focus for good."""
    import json
    js = LAYOUT_JS % {"conn": json.dumps(conn),
                      "shortcut": json.dumps("KrohnkiteTileLayout" if tile else "KrohnkiteFloatingLayout")}
    return kwinscript.run(js, answer=True) == "ok"


def publish(ds, tile, ok=True):
    util.save_json(STATE_FILE, {"tile": sorted(tile), "available": ok and available(),
                                "screens": {d.connector: "tile" if d.id in tile else "float" for d in ds}})


def ensure_loaded(ds, tile):
    """Krohnkite on (first use in a session): loads with the screens' layouts already right."""
    if loaded():
        return True
    write_defaults(ds, tile)
    util.run("kwriteconfig6", "--file", "kwinrc", "--group", "Plugins", "--key", "krohnkiteEnabled", "true")
    util.run("qdbus6", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.start")
    return loaded()


def set_mode(key, mode, ds=None):
    """`mode` tile | float | toggle for one screen (a connector or display id; "focused" = the focused
    window's screen). Returns the new mode."""
    ds = displays.probe() if ds is None else ds
    if key == "focused":
        key = focused_screen() or ""
    d = next((d for d in ds if key in (d.connector, d.id)), None)
    if not d:
        raise SystemExit(f"no screen {key!r} (have: {', '.join(x.connector for x in ds)})")
    tile = tiled_ids()
    on = (d.id not in tile) if mode == "toggle" else mode == "tile"
    (tile.add if on else tile.discard)(d.id)
    publish(ds, tile)
    write_defaults(ds, tile)
    if not available():
        return "tile" if on else "float"
    if loaded():
        set_live(d.connector, on)
    else:
        ensure_loaded(ds, tile)
    seen = _seen()
    seen.add(d.connector)
    _save_seen(seen)
    return "tile" if on else "float"


def focused_screen():
    """The focused window's screen (Krohnkite's notion of the current screen; KWin's activeOutputName
    follows the pointer instead)."""
    return kwinscript.run("answer(workspace.activeWindow ? workspace.activeWindow.output.name"
                          " : workspace.activeScreen.name);", answer=True) or ""


def _seen():
    try:
        return set(SEEN.read_text().split())
    except OSError:
        return set()


def _save_seen(s):
    util.write_if_changed(SEEN, "\n".join(sorted(s)) + "\n")


def apply_new(ds):
    """Screens Krohnkite hasn't had this session get their layout live (a new one would tile, since Krohnkite
    tiles screens it doesn't know); the state file and the login defaults follow the screens now."""
    tile = tiled_ids()
    publish(ds, tile)
    if not available():
        return
    write_defaults(ds, tile)
    if not loaded():
        return
    seen = _seen()
    if not seen:        # the first run of a session: Krohnkite loaded with the login defaults, already right
        _save_seen({d.connector for d in ds})
        return
    for d in ds:
        if d.connector not in seen and set_live(d.connector, d.id in tile):
            seen.add(d.connector)
    _save_seen(seen)
