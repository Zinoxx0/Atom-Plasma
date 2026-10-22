#!/usr/bin/env python3
"""Atom Plasma: set a wallpaper and re-theme the desktop from it.

    rice.py <image>          set a specific image
    rice.py next|prev        step through the wallpaper collection (settings wallpaper_dir)
    rice.py random           pick a random one
    rice.py restore          re-apply the current wallpaper's theme
    rice.py screens-changed  after screens are plugged in or out: each screen's palette, the desktop
                             clock that carries Clawd, the bars' islands and clock sizes, window borders
    rice.py setup            the one-shot settings that don't follow the wallpaper (window chrome, Dolphin,
                             Darkly): run once, and again only to put them back
    rice.py thumbs           (re)build picker thumbnails
    rice.py walls            the picker's list: wallpaper file names, one per line (thumbnails built)
    rice.py check FILE...    can these be wallpapers (format and readable)? names the ones that can't
    rice.py wallpaper-dir    where the collection is
    rice.py page             everything the Theme page shows, as one JSON (wallpapers, screens, themes)
    rice.py screens          JSON list of screens and their wallpapers (for the picker)
    rice.py preset save|load|delete <name>
                             presets: every screen's wallpaper (and the one that drives the
                             theme) under a short name, to switch whole looks at once
    rice.py presets          JSON list of the presets, with thumbnails (for the picker)
    rice.py theme show       JSON for the Theme page: a screen's mood, wallpaper swatches, accents
                             (auto and current) and its overrides
    rice.py theme set [--mood M|auto] [--primary HEX] [--secondary HEX] [--tertiary HEX]
                      [--intensity F]
                             hand-picked colours for a screen (--screen, default focused; or all),
                             re-themed live. They last until a new wallpaper is picked on that
                             screen, unless saved: `preset save` keeps them (a preset is a theme)
    rice.py theme reset      back to the wallpaper's own colours

    --screen all|focused|<output>   which screens get the wallpaper (default: focused,
                                    the one KWin reports as active; kglobalaccel caches
                                    a shortcut's Exec line until relogin, so this default
                                    is what plain `rice.py next` shortcuts get)

Each screen keeps its own wallpaper. The last one picked drives the global theme
(colour scheme, terminals, window borders); each bar's islands and the widgets on
it follow their own screen's wallpaper (palette-<output>.json + Colorizer over D-Bus).
The work is done by the atom package (atom/__init__.py lists its parts); what goes wrong is logged to
~/.local/state/rice/rice.log, and a re-theme that couldn't apply a step exits non-zero naming it.

Writes / applies:
    ~/.local/state/rice/palette.json            global palette (last wallpaper picked)
    ~/.local/state/rice/palette-<output>.json   per-screen palette for the widgets on that bar, with
                                                `_layout` (where the desktop clock and music card sit on that
                                                wallpaper) and `_desk` (com.zinoxx.desk)
    ~/.local/share/color-schemes/Rice{A,B}.colors  KDE colour scheme (alternated so
                                                Plasma always sees a "new" scheme)
    ~/.local/share/konsole/Rice-<hash>.*        Konsole scheme + profile, hot-swapped into open sessions
    ~/.config/alacritty/plasma-rice.toml
    templates/*                                 e.g. ~/.config/starship.toml
    kwinrc [Round-Corners]                      gradient window border (primary -> tertiary), per screen
    the icon theme, the look-and-feel's splash palette, VS Code, btop, MangoHud, Zen, fastfetch,
    keyboards on Automatic (rgb.py), the login screen's stage (boot.py)
Settings: ~/.config/plasma-rice/settings.json: soft_tint (how far the soft mood's surfaces lean toward
Tokyo Night's indigo), depth (extra darkness for dark surfaces), light_ui (light wallpapers turn the
desktop light: frosted Plasma Style "Rice-Light", a light KDE scheme, white-frost islands and popups;
terminals and apps keep a dark twin palette), bar_scale (the size of a bar's widgets), top_scale (the
Glimpse band at the top), clock_size (the bar clock's points), icon_theme, desk_media (the screen whose
desktop clock carries the music card and Clawd; by default the only screen, else one beside the main
bar's), weather {"city": ...} (weather.py), terminal {font, size, opacity, padding}, wallpaper_dir,
wallhaven_* (wallhaven.py), update_check (update-check.py); each size is one factor for every screen or
{output: factor}. The current-wallpaper symlink is ~/.local/state/rice/wallpaper.
"""
import json
import sys
from pathlib import Path

from atom import presets, screens, theme, util, walls


def main(args):
    target = "focused"
    if "--screen" in args:
        i = args.index("--screen")
        if i + 1 >= len(args) or args[i + 1].startswith("--"):
            sys.exit("--screen takes all, focused or an output name")
        target = args[i + 1]
        del args[i:i + 2]
    arg = args[0] if args else "random"
    util.STATE.mkdir(parents=True, exist_ok=True)

    if arg == "thumbs":
        for w in walls.walls():
            walls.thumb(w)
    elif arg == "walls":      # the picker's list (file names, thumbnails built): one list of formats, walls.EXTS
        for w in walls.walls():
            walls.thumb(w)
            print(w.name)
    elif arg == "check":      # servicemenu.sh: can these files be wallpapers? names the ones that can't
        bad = [f"{f}: {why}" for f in args[1:] if (why := walls.unusable(Path(f).expanduser()))]
        if bad:
            sys.exit("\n".join(bad))
    elif arg == "wallpaper-dir":
        print(walls.WALLDIR)
    elif arg == "page":
        print(json.dumps(theme.page()))
    elif arg == "screens":
        print(json.dumps(theme.screens_info()))
    elif arg == "presets":
        print(json.dumps(theme.presets_info()))
    elif arg == "screens-changed":     # plugged in or out: palettes, bars and borders follow (com.zinoxx.desk asks)
        theme.screens_changed()
    elif arg == "setup":
        theme.setup()
    elif arg == "theme":
        theme.theme_command(args[1] if len(args) > 1 else "show", target, args)
    elif arg == "preset":
        sub, name = (args[1:3] + ["", ""])[:2]
        if sub not in ("save", "load", "delete"):
            sys.exit("rice.py preset save|load|delete <name>")
        util.hold_lock()
        if sub == "save":
            presets.preset_save(name, screens.screens())
        elif sub == "delete":
            presets.preset_delete(name)
        else:
            theme.pick("", target, preset=name)
    elif arg.startswith("-"):
        sys.exit(__doc__)
    else:       # next | prev | random | restore | an image
        theme.pick(arg, target)


if __name__ == "__main__":
    main(sys.argv[1:])
