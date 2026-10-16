#!/usr/bin/env python3
"""Rebuild the Plasma panels as HyDE-style islands (Panel Colorizer).

Main panel (screen 0), left to right:
  [launcher · wallpaper]  [tasks] ........ [Claude] [system rings] [tray] [clock] [power]
Other screens: [launcher] [tasks] ........ [clock] [show desktop]
[launcher] is com.zinoxx.launcher (replaces Kickoff); [tasks] is Glimpse (com.zinoxx.glimpse):
pinned apps here, open windows in its top strip.
A stock task manager found on a bar is replaced by it, pins included.

Islands are the groups of widgets between org.kde.plasma.panelspacer widgets.
Widgets are added through plasmashell's scripting API; the order is then
written to AppletOrder with plasmashell stopped (it is read-only at runtime).
Safe to re-run: it only adds what is missing.
"""
import copy
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tokens import TOKENS  # noqa: E402

HOME = Path.home()
APPLETSRC = HOME / ".config/plasma-org.kde.plasma.desktop-appletsrc"
PRESET = Path("/usr/share/plasma/plasmoids/luisbocanegra.panel.colorizer/contents/ui/presets/Blur Widgets/settings.json")
COLORIZER = "luisbocanegra.panel.colorizer"
SPACER = "org.kde.plasma.panelspacer"
TASKS = "com.zinoxx.glimpse"
LAUNCHER = "com.zinoxx.launcher"           # replaces Kickoff (favourites are Plasma's shared ones)
LEGACY_TASKS = ["org.kde.plasma.icontasks", "org.kde.plasma.taskmanager"]
ISLAND_RADIUS = TOKENS["radius"]["md"]     # islands share the windows' corner radius


def widget_settings(p=None):
    """Island look. Without a palette the colours follow the KDE colour scheme; with one
    (rice.py passes each screen's) they are fixed to it, so every bar matches its own wallpaper."""
    if p:
        return island_style(p, p["primary"], states=False)
    ws = json.loads(PRESET.read_text())["globalSettings"]["widgets"]
    w = ws["normal"]
    w["enabled"] = True
    w["blurBehind"] = True
    w["backgroundColor"].update(enabled=True, sourceType=1, systemColor="backgroundColor",
                                systemColorSet="View", alpha=0.72)
    w["foregroundColor"]["enabled"] = False
    w["radius"] = {"enabled": True, "corner": {k: ISLAND_RADIUS for k in ("topLeft", "topRight", "bottomRight", "bottomLeft")}}
    w["margin"] = {"enabled": True, "side": {"left": 0, "right": 0, "top": 4, "bottom": 4}}
    w["spacing"] = 6
    w["border"].update(enabled=True, width=1, customSides=False)
    w["border"]["color"].update(enabled=True, sourceType=1, systemColor="highlightColor",
                                systemColorSet="View", alpha=0.32)
    w["shadow"]["background"].update(enabled=True, size=6, xOffset=0, yOffset=2)
    w["shadow"]["background"]["color"].update(sourceType=0, custom="#000000", alpha=0.45)
    w["shadow"]["foreground"]["enabled"] = False
    w["borderSecondary"]["enabled"] = False

    hovered = copy.deepcopy(w)
    hovered["backgroundColor"]["alpha"] = 0.82
    hovered["border"]["color"]["alpha"] = 0.6
    expanded = copy.deepcopy(w)
    expanded["backgroundColor"]["alpha"] = 0.86
    expanded["border"]["color"]["alpha"] = 0.85
    ws.update(normal=w, hovered=hovered, expanded=expanded)
    return ws


def mix(a, b, t):
    """a blended toward b by t, as #rrggbb."""
    a, b = (tuple(int(c.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)) for c in (a, b))
    return "#%02x%02x%02x" % tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def argb(c, alpha):
    return "#%02x%s" % (round(alpha * 255), c.lstrip("#"))


def island_style(p, acc, states=True):
    """Obsidian glass: a dark body, a breath lighter at the top, a white sheen along the top
    edge, a hairline outline in the island's accent and a soft neutral shadow. Text and
    icons keep their own colours. Hovering brightens the outline; an open popup lights it
    fully and adds a faint accent glow; attention turns it red. states=False: no state
    changes (islands holding several widgets, which would light up only the hovered part)."""
    ws = json.loads(PRESET.read_text())["globalSettings"]["widgets"]
    w = ws["normal"]
    bg = p["background"]

    def color(c, alpha):
        return {"enabled": True, "sourceType": 0, "custom": c, "alpha": alpha}

    def look(lift, edge, sheen, glow=None):
        o = copy.deepcopy(w)
        o["enabled"] = True
        o["blurBehind"] = True
        o["backgroundColor"].update(enabled=True, sourceType=5, alpha=1)
        top = mix(mix(bg, "#ffffff", 0.035 + lift), acc, 0.05)
        o["backgroundColor"]["gradient"] = {"orientation": 1, "stops": [
            {"color": argb(top, 0.80), "position": 0},
            {"color": argb(mix(bg, "#ffffff", lift / 2), 0.72), "position": 1}]}
        o["foregroundColor"]["enabled"] = False
        o["radius"] = {"enabled": True, "corner": {k: ISLAND_RADIUS for k in ("topLeft", "topRight", "bottomRight", "bottomLeft")}}
        o["margin"] = {"enabled": True, "side": {"left": 0, "right": 0, "top": 4, "bottom": 4}}
        o["spacing"] = 6
        o["border"].update(enabled=True, width=1, customSides=False)
        o["border"]["color"].update(color(acc, edge))
        o["borderSecondary"].update(enabled=True, customSides=True)
        o["borderSecondary"]["custom"]["widths"] = {"left": 0, "right": 0, "top": 1, "bottom": 0}
        o["borderSecondary"]["color"].update(color("#ffffff", sheen))
        o["shadow"]["background"].update(enabled=True, size=glow[1] if glow else 12, xOffset=0, yOffset=glow[2] if glow else 4)
        o["shadow"]["background"]["color"].update(color(glow[0], glow[3]) if glow else color("#000000", 0.38))
        o["shadow"]["foreground"]["enabled"] = False
        return o

    out = {"normal": look(0, 0.26, 0.07)}
    if states:
        out["hovered"] = look(0.025, 0.55, 0.10)
        out["expanded"] = look(0.04, 0.85, 0.12, glow=(acc, 14, 3, 0.24))
        out["needsAttention"] = look(0.02, 0.75, 0.08, glow=(p.get("red", "#f38ba8"), 12, 3, 0.2))
        out["needsAttention"]["border"]["color"].update(color(p.get("red", "#f38ba8"), 0.75))
    return out


# inner side padding for lone widgets that would otherwise touch the island's edge
PADS = {"org.kde.plasma.digitalclock": 10, "org.kde.plasma.showdesktop": 5}


def island_overrides(p, panel):
    """Colorizer overrides lighting the islands' outlines with one gradient across the bar,
    primary on the left to tertiary on the right (the top band's rim, mirrored), and padding
    lone clock/show-desktop widgets (PADS)."""
    overrides, assoc = {}, []
    isl = islands(panel)
    for n, group in enumerate(isl):
        t = n / max(1, len(isl) - 1)
        acc = mix(p["primary"], p.get("tertiary", p["primary"]), t)
        pad = max((PADS.get(w, 0) for _, w in group), default=0) if len(group) == 1 else 0
        name = f"Island {n}"
        overrides[name] = island_style(p, acc, states=len(group) == 1)
        if pad:
            for o in overrides[name].values():
                o["margin"] = {"enabled": True, "side": dict(o["margin"]["side"], left=pad, right=pad)}
        assoc += [{"id": i, "name": w, "presets": [name]} for i, w in group]
    return {"overrides": overrides, "associations": assoc}


def colorizer_settings():
    g = json.loads(PRESET.read_text())["globalSettings"]
    g["widgets"] = widget_settings()
    w = g["widgets"]["normal"]

    g["panel"]["normal"]["enabled"] = False
    g["trayWidgets"]["normal"]["enabled"] = False
    g["nativePanel"] = {"background": {"enabled": True, "opacity": 0, "shadow": False},
                        "floatingDialogs": True, "floatingDialogsAllowOverride": True}
    g["stockPanelSettings"] = {k: {"enabled": False, "value": v} for k, v in (
        ("screen", 0), ("position", "bottom"), ("alignment", "center"), ("lengthMode", "fill"),
        ("visibility", "none"), ("opacity", "adaptive"), ("floating", True), ("thickness", 44), ("visible", True))}
    # the stock clock has no inner padding, so its text touched the island border;
    # associations (which widget gets it) are filled in per panel by the JS below
    g["configurationOverrides"] = {"overrides": {CLOCK_PAD: clock_padding(w)}, "associations": []}
    return g


CLOCK_PAD = "Clock padding"


def clock_padding(normal):
    """Colorizer drops every key an override leaves out, so list them all: sections with
    enabled=false fall back to the global settings (colours included), only the margin differs."""
    def defer(d):
        return {k: ({"enabled": False} if "enabled" in v else defer(v)) if isinstance(v, dict) else v
                for k, v in d.items()}
    o = defer(normal)
    o["margin"] = {"enabled": True, "side": dict(normal["margin"]["side"], left=10, right=10)}
    return {"normal": o}


def clock_overrides(clock_id):
    return {"overrides": {CLOCK_PAD: clock_padding(colorizer_settings()["widgets"]["normal"])},
            "associations": [{"id": clock_id, "name": "org.kde.plasma.digitalclock", "presets": [CLOCK_PAD]}]}


def shell(js):
    return subprocess.run(["qdbus6", "org.kde.plasmashell", "/PlasmaShell",
                           "org.kde.PlasmaShell.evaluateScript", js],
                          check=True, capture_output=True, text=True).stdout.strip()


JS = r"""
var SETTINGS = %(settings)s;
var out = {};
function add(p, plugin, cfg) {
    var w = p.addWidget(plugin);
    for (var group in (cfg || {})) {
        w.currentConfigGroup = group.split("/");
        for (var k in cfg[group]) w.writeConfig(k, cfg[group][k]);
    }
    return w;
}
function spacer(p) { return add(p, "%(spacer)s", {"General": {"expanding": false, "length": 8}}); }
panels().forEach(function (p) {
    var main = p.screen === 0;
    var have = {};
    p.widgets().forEach(function (w) { (have[w.type] = have[w.type] || []).push(w); });
    var ids = {};
    function one(plugin, cfg) {
        var w = (have[plugin] || [])[0] || add(p, plugin, cfg);
        ids[plugin] = w.id;
        return w;
    }
    // existing pieces
    one("%(launcher)s"); one("org.kde.plasma.digitalclock");
    (have["org.kde.plasma.kickoff"] || []).forEach(function (w) { w.remove(); });
    // tasks: Glimpse takes over a stock task manager, pinned apps included
    var LEGACY = %(legacy)s, old = [];
    LEGACY.forEach(function (t) { old = old.concat(have[t] || []); });
    var legacy = old[0], pins = [];
    if (legacy) {
        legacy.currentConfigGroup = ["General"];
        pins = legacy.readConfig("launchers") || [];
        if (typeof pins === "string") pins = pins ? pins.split(",") : [];
    }
    one("%(tasks)s", {"General": {"launchers": pins}});
    // the wallpaper picker lives inside the launcher now (Meta+Shift+W, the wheel over the emblem)
    old = old.concat(have["com.zinoxx.wallpicker"] || []);
    old.forEach(function (w) { w.remove(); });
    var clock = (have["org.kde.plasma.digitalclock"] || [])[0];
    if (clock) {
        clock.currentConfigGroup = ["Appearance"];
        clock.writeConfig("showDate", true);
        clock.writeConfig("dateDisplayFormat", "BesideTime");
        clock.writeConfig("dateFormat", "custom");
        clock.writeConfig("customDateFormat", "ddd d");
        clock.writeConfig("use24hFormat", 2);
        // the size is per bar (bigger on scaled bars), so only a fresh clock gets the default
        var fresh = String(clock.readConfig("autoFontAndSize")) !== "false";
        clock.writeConfig("autoFontAndSize", false);
        clock.writeConfig("fontFamily", "Inter Display");
        clock.writeConfig("fontWeight", 700);
        if (fresh) clock.writeConfig("fontSize", 11);
    }
    if (main) {
        one("org.kde.plasma.systemtray");
        one("com.zinoxx.claudeusage");
        one("com.zinoxx.sysstats");
        one("com.zinoxx.session");
    } else {
        one("org.kde.plasma.showdesktop");
    }
    var pc = one("%(colorizer)s");
    var settings = JSON.parse(JSON.stringify(SETTINGS));
    settings.configurationOverrides.associations = [{"id": ids["org.kde.plasma.digitalclock"],
        "name": "org.kde.plasma.digitalclock", "presets": ["%(clockpad)s"]}];
    pc.currentConfigGroup = ["General"];
    pc.writeConfig("globalSettings", JSON.stringify(settings));
    pc.writeConfig("islandsEnabled", true);
    pc.writeConfig("islandSeparatorWidget", "%(spacer)s");
    pc.writeConfig("hideWidget", true);
    pc.writeConfig("isEnabled", true);
    pc.writeConfig("animatePropertyChanges", true);     // hover and popup states ease in
    pc.writeConfig("animationDuration", 220);
    // spacers: keep one expanding, make sure there are enough small ones
    var spacers = have["%(spacer)s"] || [];
    var expanding = spacers[0] || add(p, "%(spacer)s");
    expanding.currentConfigGroup = ["General"];
    expanding.writeConfig("expanding", true);
    var small = spacers.slice(1).map(function (w) { return w.id; });
    var need = main ? 6 : 2;
    while (small.length < need) small.push(spacer(p).id);
    ids.expanding = expanding.id;
    ids.small = small;
    out[p.id] = ids;
});
print(JSON.stringify(out));
"""


PANELS_JS = r"""
var out = [];
panels().forEach(function (p) {
    if (p.screen < 0) return;
    var g = screenGeometry(p.screen), pc = null, clock = null, widgets = [];
    p.widgets().forEach(function (w) {
        if (w.type === "%(colorizer)s") pc = w.id;
        if (w.type === "org.kde.plasma.digitalclock") clock = w.id;
        widgets.push({id: w.id, type: w.type});
    });
    if (pc !== null) out.push({panel: p.id, screen: p.screen, x: g.x, y: g.y, colorizer: pc, clock: clock, widgets: widgets});
});
print(JSON.stringify(out));
"""


def panels():
    """Panels with a Colorizer: id, Plasma screen index, logical position, colorizer/clock widget ids."""
    return json.loads(shell(PANELS_JS % {"colorizer": COLORIZER}))


def islands(panel):
    """The panel's islands, left to right: lists of (widget id, plugin) between spacers."""
    order = subprocess.run(["kreadconfig6", "--file", APPLETSRC.name, "--group", "Containments",
                            "--group", str(panel["panel"]), "--group", "General", "--key", "AppletOrder"],
                           capture_output=True, text=True).stdout.strip()
    types = {w["id"]: w["type"] for w in panel.get("widgets", [])}
    ids = [int(i) for i in order.split(";") if i.strip().isdigit() and int(i) in types]
    ids += [i for i in types if i not in ids]
    out, cur = [], []
    for i in ids:
        if types[i] == SPACER:
            if cur:
                out.append(cur)
            cur = []
        elif types[i] != COLORIZER:
            cur.append((i, types[i]))
    return out + ([cur] if cur else [])


def colorizer_apply(panel, patch):
    """Replace top-level sections of one panel's Colorizer settings (e.g. widgets,
    configurationOverrides) in one write through plasmashell's scripting API; the widget
    picks it up live. (Its D-Bus route silently drops messages over ~50 KB, and per-island
    overrides are bigger than that.)"""
    js = """
var patch = %s;
panels().forEach(function (p) {
    if (p.id !== %d) return;
    p.widgets("%s").forEach(function (w) {
        w.currentConfigGroup = ["General"];
        var g = {};
        try { g = JSON.parse(w.readConfig("globalSettings") || "{}"); } catch (e) {}
        for (var k in patch) g[k] = patch[k];
        w.writeConfig("globalSettings", JSON.stringify(g));
        w.reloadConfig();
        print("ok");
    });
});
""" % (json.dumps(patch), panel["panel"], COLORIZER)
    try:
        return "ok" in shell(js)
    except subprocess.CalledProcessError:
        return False


def colorizer_set(panel, path, value):
    """Edit one panel's Colorizer settings live through its D-Bus service (it saves them too)."""
    svc = f"{COLORIZER}.c{panel['panel']}.w{panel['colorizer']}"
    return subprocess.run(["qdbus6", svc, "/preset", "property", f"{path} {json.dumps(value)}"],
                          capture_output=True, text=True).returncode == 0


def order_for(ids, main):
    s = list(ids["small"])
    k = lambda name: ids[name]
    if main:
        seq = [k(LAUNCHER), s[0],
               k(TASKS), ids["expanding"],
               k("com.zinoxx.claudeusage"), s[1], k("com.zinoxx.sysstats"), s[2],
               k("org.kde.plasma.systemtray"), s[3], k("org.kde.plasma.digitalclock"), s[4],
               k("com.zinoxx.session"), k(COLORIZER)]
        extra = s[5:]
    else:
        seq = [k(LAUNCHER), s[0], k(TASKS), ids["expanding"],
               k("org.kde.plasma.digitalclock"), s[1], k("org.kde.plasma.showdesktop"), k(COLORIZER)]
        extra = s[2:]
    return seq + extra


def main():
    js = JS % {"settings": json.dumps(colorizer_settings()), "spacer": SPACER, "colorizer": COLORIZER,
               "clockpad": CLOCK_PAD, "tasks": TASKS, "legacy": json.dumps(LEGACY_TASKS), "launcher": LAUNCHER}
    ids = json.loads(shell(js))
    print("widgets:", json.dumps(ids))

    # plasmashell owns appletsrc while running: stop it, set the order, start it again
    subprocess.run(["systemctl", "--user", "stop", "plasma-plasmashell.service"], check=True)
    time.sleep(1)
    rc = APPLETSRC.name
    for pid, panel_ids in ids.items():
        screen = subprocess.run(["kreadconfig6", "--file", rc, "--group", "Containments", "--group", pid,
                                 "--key", "lastScreen"], capture_output=True, text=True).stdout.strip()
        order = ";".join(str(i) for i in order_for(panel_ids, screen == "0"))
        subprocess.run(["kwriteconfig6", "--file", rc, "--group", "Containments", "--group", pid,
                        "--group", "General", "--key", "AppletOrder", order], check=True)
        print(pid, "->", order)
    subprocess.run(["systemctl", "--user", "start", "plasma-plasmashell.service"], check=True)

    # the settings above use scheme colours; rice.py pushes each screen's own palette to its
    # bar through the Colorizer D-Bus services once they are up
    for _ in range(30):
        if f"{COLORIZER}.c" in subprocess.run(["qdbus6"], capture_output=True, text=True).stdout:
            break
        time.sleep(0.5)
    time.sleep(1)
    subprocess.run([str(HOME / ".config/plasma-rice/rice.py"), "restore"], check=False)


if __name__ == "__main__":
    main()
