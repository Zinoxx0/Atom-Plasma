"""Papirus-Rice: Papirus-Dark with folder icons in the Papirus colour closest to
the wallpaper accent. Lives in ~/.local/share/icons, so no root is needed
(papirus-folders would rewrite /usr/share/icons instead)."""
import json
import re
import subprocess
from collections import Counter
from pathlib import Path

import palette

SRC = Path("/usr/share/icons/Papirus")
DST = Path.home() / ".local/share/icons/Papirus-Rice"
STATE = Path.home() / ".local/state/rice/papirus-colors.json"
SKIP = {"black", "white", "grey", "yaru"}   # neutral; only used for grey wallpapers


def papirus_colors():
    """name -> dominant fill colour of its 64px folder icon (cached)."""
    try:
        return json.loads(STATE.read_text())
    except (OSError, ValueError):
        pass
    out = {}
    for f in (SRC / "64x64/places").glob("folder-*.svg"):
        m = re.fullmatch(r"folder-([a-z]+)\.svg", f.name)
        if not m or f.is_symlink():
            continue
        fills = re.findall(r"fill:\s*(#[0-9a-fA-F]{6})|fill=\"(#[0-9a-fA-F]{6})\"", f.read_text())
        fills = [a or b for a, b in fills]
        if fills:
            out[m.group(1)] = Counter(c.lower() for c in fills).most_common(1)[0][0]
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(out, indent=1))
    return out


def nearest(accent):
    L, C, H = palette.to_oklch(accent)
    best, bestd = "blue", 1e9
    for name, hexc in papirus_colors().items():
        l2, c2, h2 = palette.to_oklch(hexc)
        if (name in SKIP) != (C < 0.03):
            continue
        dh = min(abs(H - h2), 360 - abs(H - h2)) / 180
        d = dh * 2 + abs(C - c2) * 3 + abs(L - l2) * 0.5
        if d < bestd:
            best, bestd = name, d
    return best


def index_theme():
    src = (SRC / "index.theme").read_text()
    sections = {}
    for block in re.split(r"\n(?=\[)", src):
        head = re.match(r"\[([^\]]+)\]", block)
        if head:
            sections[head.group(1)] = block
    dirs = [d for d in sections if d.endswith("/places") and d.count("/") == 1]
    body = ["[Icon Theme]", "Name=Papirus-Rice", "Comment=Papirus-Dark with wallpaper-coloured folders",
            "Inherits=Papirus-Dark,breeze-dark,hicolor", "Directories=" + ",".join(dirs), ""]
    body += [sections[d].strip() + "\n" for d in dirs]
    return "\n".join(body)


def use_theme(theme):
    """Make `theme` the active icon theme (plasma-changeicons also tells running apps)."""
    now = subprocess.run(["kreadconfig6", "--file", "kdeglobals", "--group", "Icons", "--key", "Theme"],
                         capture_output=True, text=True).stdout.strip()
    if now != theme:
        subprocess.run(["/usr/lib/plasma-changeicons", theme], capture_output=True, check=False)


def apply(accent, theme="Papirus-Rice"):
    """Point the folder icons at the colour nearest `accent`. Returns (colour, changed).
    Any other theme (settings icon_theme) has fixed folder colours, so it is only made active."""
    if theme != "Papirus-Rice":
        use_theme(theme)
        return None, False
    use_theme(theme)
    color = nearest(accent)
    marker = DST / ".color"
    if marker.exists() and marker.read_text() == color:
        return color, False
    DST.mkdir(parents=True, exist_ok=True)
    (DST / "index.theme").write_text(index_theme())
    pat = re.compile(rf"^((?:folder|user)(?:-[a-z]+)*?)-{color}((?:-[a-z0-9-]+)?\.svg)$")
    for places in SRC.glob("*/places"):
        out = DST / places.parent.name / "places"
        out.mkdir(parents=True, exist_ok=True)
        for old in out.iterdir():
            if old.is_symlink():
                old.unlink()
        for f in places.iterdir():
            m = pat.match(f.name)
            if m:
                (out / (m.group(1) + m.group(2))).symlink_to(f)
    marker.write_text(color)
    # drop the icon cache and tell running apps to reload icons
    for cache in Path.home().joinpath(".cache").glob("icon-cache.kcache"):
        cache.unlink(missing_ok=True)
    subprocess.run(["dbus-send", "--session", "--type=signal", "/KIconLoader",
                    "org.kde.KIconLoader.iconChanged", "int32:0"], check=False)
    return color, True
