"""The terminals: the ANSI colours (Konsole, Alacritty and VS Code's terminal share them), Konsole's
colour scheme, profile, tab bar and window chrome, and Alacritty's colours. Font, size, opacity and
padding come from settings.json "terminal" (defaults in LOOK)."""
import hashlib
import os
import pwd

from . import kde, palette, tokens, util
from .util import HOME

# shared by Konsole and Alacritty, so the two terminals look alike; settings.json "terminal" overrides
LOOK = {"font": tokens.TOKENS["font"]["mono"], "size": 11,     # pt: 14.7 px, a step above the UI's 13 px Inter
        "opacity": 0.85, "padding": tokens.TOKENS["space"]["lg"]}


def look(cfg=None):
    return dict(LOOK, **((cfg if cfg is not None else util.settings()).get("terminal") or {}))


ANSI = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]


CLAIM = 35      # degrees: how close a wallpaper accent must be to an ANSI hue to take its slot


APART = 15      # ...and how far it must stay from every other slot (blue and cyan sit only ~22 apart)


def ansi(p):
    """ANSI colours as (normal, bright, faint) per slot, for Konsole, Alacritty and VS Code's terminal.

    After HyDE's kitty mapping (blacks and whites from the surface ladder, the colours from the
    wallpaper's accents, brights lifted), with one difference: HyDE hands red/green/yellow to
    whatever accents the wallpaper has, so an error can come out teal. Here each accent claims
    only the ANSI hue it already resembles (within CLAIM degrees), so the terminal wears the
    wallpaper's exact colours where they fit and red still reads as red everywhere else."""
    lch, oklch = palette.to_oklch, palette.oklch
    slots = {n: lch(p[n]) for n in ANSI[1:7]}
    claimed = {}
    for role in ("primary", "tertiary", "secondary"):
        _, c, h = lch(p[role])
        if c < 0.05:                    # a grey accent has no colour to lend
            continue
        hues = {n: claimed[n][1] if n in claimed else slots[n][2] for n in slots}
        for n in sorted((n for n in slots if n not in claimed), key=lambda s: palette.hue_dist(h, slots[s][2])):
            if palette.hue_dist(h, slots[n][2]) > CLAIM:
                break
            if all(palette.hue_dist(h, hues[m]) >= APART for m in slots if m != n):
                claimed[n] = (c, h)
                break
    t = {}
    for n, (L, C, H) in slots.items():
        if n in claimed:
            C, H = max(claimed[n][0], C * 0.75), claimed[n][1]   # keep the slot's lightness tier
        normal = oklch(L, C, H) if n in claimed else p[n]
        t[n] = (normal, oklch(min(0.93, L + 0.07), C, H), oklch(L - 0.12, C * 0.9, H))
    # bright black is the ghost text (autosuggestions, comments): lifted to sit between outline and muted
    t["black"] = (p["surface_high"], palette.mix(p["outline"], p["muted"], 0.5), p["surface_container"])
    t["white"] = (p["on_surface_variant"], p["on_surface"], p["muted"])
    return t


def term(p):
    """ANSI (normal, bright) pairs for VS Code's terminal."""
    return {n: v[:2] for n, v in ansi(p).items()}


def konsole(p, lk=None):
    lk = lk or look()
    c, t = palette.rgb_csv, ansi(p)
    out = ["[Background]", f"Color={c(p['background'])}", "", "[BackgroundFaint]",
           f"Color={c(p['background'])}", "", "[BackgroundIntense]", f"Color={c(p['surface'])}", ""]
    for i, n in enumerate(ANSI):
        norm, bright, dim = t[n]
        out += [f"[Color{i}]", f"Color={c(norm)}", "", f"[Color{i}Faint]", f"Color={c(dim)}", "",
                f"[Color{i}Intense]", f"Color={c(bright)}", ""]
    out += ["[Foreground]", f"Color={c(p['on_surface'])}", "", "[ForegroundFaint]",
            f"Color={c(p['on_surface_variant'])}", "", "[ForegroundIntense]", f"Color={c(p['on_surface'])}", "",
            "[General]", "Blur=true", "ColorRandomization=false", "Description=Rice (wallpaper)",
            f"Opacity={lk['opacity']}", "Wallpaper=", ""]
    return "\n".join(out)


KONSOLE_PROFILE = """[Appearance]
ColorScheme={name}
Font={font},{size},-1,5,400,0,0,0,0,0,0,0,0,0,0,1

[Cursor Options]
CursorShape=1
CustomCursorColor={cursor}
CustomCursorTextColor={cursor_text}
UseCustomCursorColor=true

[General]
Command={shell}
DimValue=40
DimWhenInactive=true
Name={name}
Parent=FALLBACK/
SemanticInputClick=true
TerminalCenter=true
TerminalMargin={margin}

[Scrolling]
ScrollBarPosition=2
"""


def konsole_tabs(p, lk=None):
    """Tab bar stylesheet (Konsole shows the bar only with 2+ tabs): quiet pills, the current one an
    accent wash with a hairline, the way the bar's islands mark an open popup. Konsole puts the tabs
    in document mode, so the QTabBar spans the window: painting it like the terminal (same colour,
    same opacity) makes tabs and terminal one surface instead of Darkly's darker translucent strip."""
    lk = lk or look()
    r = lambda h, a: f"rgba({palette.rgb_csv(h)}, {round(a * 255)})"   # noqa: E731
    al, rad, sp = tokens.TOKENS["alpha"], tokens.TOKENS["radius"], tokens.TOKENS["space"]
    return f"""/* Generated by ~/.config/plasma-rice/rice.py from the wallpaper palette. Do not edit. */
QTabBar {{ background: {r(p['background'], lk['opacity'])}; }}
QTabBar::tab {{
    background: transparent; color: {p['muted']};
    border: 1px solid transparent; border-radius: {rad['sm']}px;
    padding: {sp['xs']}px {sp['md']}px; margin: {sp['sm']}px {sp['xxs']}px {sp['xxs']}px {sp['xxs']}px;
    min-width: 7em; max-width: 22em;
}}
QTabBar::tab:first {{ margin-left: {lk['padding'] - sp['xs']}px; }}
QTabBar::tab:hover:!selected {{ background: {r(p['on_surface'], al['hover'])}; color: {p['on_surface_variant']}; }}
QTabBar::tab:selected {{
    background: {r(p['primary'], al['selected'])}; color: {p['on_surface']};
    border-color: {r(p['primary'], al['outlineStrong'] + 0.1)};
}}
"""


def apply_konsole(p):
    """Konsole caches schemes and profiles by name, so each palette gets fresh
    names (Rice-<hash>); running sessions on a Rice profile are switched over D-Bus. SemanticInputClick: a
    click in the command line moves the cursor there (the shell marks where it starts: shell/rice.zsh).
    Also keeps the window chrome off for good: no menu bar or toolbars (new windows read
    the saved window state, which a window rewrites when it closes), tabs only when needed."""
    d = HOME / ".local/share/konsole"
    c, lk = palette.rgb_csv, look()
    scheme = konsole(p, lk)
    profile = KONSOLE_PROFILE.format(name="{name}", font=lk["font"], size=lk["size"], margin=lk["padding"],
                                     shell=pwd.getpwuid(os.getuid()).pw_shell or "/bin/sh",
                                     cursor=c(p["primary"]), cursor_text=c(p["on_primary"]))
    name = "Rice-" + hashlib.sha1((scheme + profile).encode()).hexdigest()[:6]
    util.write_if_changed(d / f"{name}.colorscheme", scheme)
    util.write_if_changed(d / f"{name}.profile", profile.replace("{name}", name))
    util.write_if_changed(d / "rice-tabs.css", konsole_tabs(p, lk))
    kde.kde_set("konsolerc", {"Desktop Entry": {"DefaultProfile": f"{name}.profile"}})
    konsole_chrome(live=False)  # menu bar, toolbars, tab bar (rice-tabs.css); the open windows just below
    for k in open_konsoles():   # one pass over the running Konsoles: their toolbars, then their sessions
        k.hide_toolbars()
        for path in k.sessions:
            if str(k.call(path, "org.kde.konsole.Session", "profile") or "").startswith("Rice"):
                k.call(path, "org.kde.konsole.Session", "setProfile", f"ColorScheme={name}")
    # keep the current and previous generation only (and drop the pre-rice Tokyo Night profile)
    gens = sorted(d.glob("Rice-*.profile"), key=lambda f: f.stat().st_mtime, reverse=True)
    for old in gens[2:]:
        old.unlink(missing_ok=True)
        (d / (old.stem + ".colorscheme")).unlink(missing_ok=True)
    for stale in ("Tokyo Night.profile", "TokyoNight.colorscheme"):
        (d / stale).unlink(missing_ok=True)


def alacritty(p, lk=None):
    """Colours plus the look shared with Konsole (font, padding, cursor, opacity); alacritty.toml
    imports this file and leaves those keys to it."""
    lk = lk or look()
    t = ansi(p)
    font, size, pad = lk["font"], lk["size"], lk["padding"]
    out = ["# Generated by ~/.config/plasma-rice/rice.py. Do not edit.",
           "[window]", f"opacity = {lk['opacity']}", "blur = true",
           f"padding = {{ x = {pad}, y = {pad} }}", "dynamic_padding = true", "",
           "[font]", f"size = {float(size)}"]
    out += [f'{k} = {{ family = "{font}", style = "{s}" }}'
            for k, s in (("normal", "Regular"), ("bold", "Bold"), ("italic", "Italic"), ("bold_italic", "Bold Italic"))]
    out += ["", "[cursor]", 'style = { shape = "Beam", blinking = "Off" }', "unfocused_hollow = true",
            "thickness = 0.15", "", "[colors.primary]",
            f'background = "{p["background"]}"', f'foreground = "{p["on_surface"]}"', "",
            "[colors.cursor]", f'cursor = "{p["primary"]}"', f'text = "{p["on_primary"]}"', "",
            "[colors.selection]", f'background = "{p["primary_container"]}"',
            f'text = "{p["on_primary_container"]}"', ""]
    for section, idx in (("normal", 0), ("bright", 1), ("dim", 2)):
        out.append(f"[colors.{section}]")
        out += [f'{n} = "{t[n][idx]}"' for n in ANSI]
        out.append("")
    return "\n".join(out)


def konsole_chrome(live=True):
    """Konsole's window chrome: no menu bar or toolbars, tabs only when needed, styled by rice-tabs.css
    (written by rice.py). A Konsole started before a change writes its old settings and window state
    back when it closes, so rice.py runs this every time and `apps.py konsole-chrome` fits login.
    Toolbar visibility lives in the saved window state, which every window rewrites on close.
    live: also hide the toolbars of the windows open now (apply_konsole does that in its own pass)."""
    kde.kde_set("konsolerc", {
        "MainWindow": {"MenuBar": "Disabled", "ToolBarsMovable": "Disabled"},
        "TabBar": {"TabBarVisibility": "ShowTabBarWhenNeeded", "TabBarUseUserStyleSheet": True,
                   "TabBarUserStyleSheetFile": (HOME / ".local/share/konsole/rice-tabs.css").as_uri(),
                   # no close button inside the pills (middle-click or Ctrl+Shift+W closes a tab),
                   # no Search Tabs bolt in the corner
                   "CloseTabOnMiddleMouseButton": True, "CloseTabButton": "None",
                   "SearchTabsButton": "HideSearchTabsButton", "ExpandTabWidth": False},
    })
    staterc = HOME / ".local/state/konsolestaterc"
    state = kde.kde_read(staterc).get(("MainWindow",), {}).get("State")
    if state:
        kde.kde_set(staterc, {"MainWindow": {"State": qt_toolbars_hidden(state, TOOLBARS)}})
    # hide them in open windows too, so what those write back on close is already right
    if live:
        for k in open_konsoles():
            k.hide_toolbars()


TOOLBARS = ("mainToolBar", "sessionToolbar")


class open_konsoles:
    """The running Konsoles on the session bus, one D-Bus connection for all of them (no qdbus6 process
    per window and session): `for k in open_konsoles(): k.sessions, k.windows, k.call(path, iface, method)`."""
    def __init__(self):
        try:
            import dbus
            self.bus = dbus.SessionBus()
            self.names = [str(n) for n in self.bus.list_names() if str(n).startswith("org.kde.konsole")]
        except Exception as e:      # no session bus (a login script too early, a test)
            util.log("Konsole over D-Bus: %s", e)
            self.names = []

    def __iter__(self):
        for svc in self.names:
            yield _Konsole(self.bus, svc)


class _Konsole:
    def __init__(self, bus, svc):
        self.bus, self.svc = bus, svc
        self.sessions = [f"/Sessions/{n}" for n in self.children("/Sessions")]
        self.windows = [f"/konsole/{n}" for n in self.children("/konsole") if n.startswith("MainWindow_")]

    def children(self, path):
        import xml.etree.ElementTree as ET
        xml = self.call(path, "org.freedesktop.DBus.Introspectable", "Introspect")
        try:
            return [n.get("name") for n in ET.fromstring(str(xml)).findall("node")] if xml else []
        except ET.ParseError:
            return []

    def call(self, path, iface, method, *args):
        """One method call (2 s at most: a Konsole that hangs mustn't hold up the theme); None on failure."""
        try:
            return getattr(self.bus.get_object(self.svc, path, introspect=False), method)(
                *args, dbus_interface=iface, timeout=2)
        except Exception as e:      # the window or session went away meanwhile
            util.log("Konsole %s %s.%s: %s", self.svc, path, method, e)
            return None

    def hide_toolbars(self):
        for w in self.windows:
            for bar in TOOLBARS:
                self.call(w, "org.kde.konsole.KXmlGuiWindow", "setToolBarVisible", bar, False)


def qt_toolbars_hidden(state_b64, names):
    """A QMainWindow saveState() blob (base64) with the named toolbars marked hidden. Each toolbar is
    stored as its objectName (QString: UTF-16BE) followed by a flags byte whose low bit means shown."""
    import base64
    state = bytearray(base64.b64decode(state_b64))
    for name in names:
        enc = name.encode("utf-16-be")
        i = state.find(len(enc).to_bytes(4, "big") + enc)
        if i >= 0:
            state[i + 4 + len(enc)] &= 0xFE
    return base64.b64encode(bytes(state)).decode()
