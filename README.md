# Atom Plasma

A KDE Plasma 6 rice driven by the wallpaper. Every screen gets its own wallpaper and palette, and the
desktop follows them: the colour scheme, Plasma Style, bar islands, terminals, VS Code, Zen, window borders,
the login screen and keyboard lighting. It's built to hold up on whatever is plugged in: one laptop panel,
seven monitors, a portrait 4K next to an 8K and an 800×800 panel.

## Install

```sh
git clone https://github.com/Zinoxx0/Atom-Plasma ~/.config/plasma-rice   # or anywhere: install links it there
cd ~/.config/plasma-rice
./rice.py install --dry-run      # what it would do
./rice.py install                # links, user units, plasmashell's environment, shortcuts
# log out and back in once, then:
./rice.py setup                  # window chrome, effects, Dolphin, Darkly (once)
./rice.py random                 # pick a wallpaper: everything themes from it
./rice.py doctor                 # is everything in place?
```

`install` is safe to re-run and never overwrites files it didn't create. It links the widgets, the
look-and-feel and the KWin effects into this repo, so `git pull` is the update. Anything that needs root
(the login-screen copier, the Razer udev rule, boot theming) is printed for you to run yourself.

**Needs:** Plasma 6.8 on Wayland, Python 3 with Pillow, numpy, dbus-python and PyGObject, plus ImageMagick
and Panel Colorizer. Optional: Darkly, Klassy, KWin better-blur-dx, Krohnkite (tiling), Claude Code
(Clawd), Limine and Plymouth (boot theming), Plasma Login Manager (login screen).

## Screens

- **Every screen gets the whole rice.** When screens are plugged in, unplugged, moved or rescaled,
  `atom-plasma-displayd` (a user unit that sleeps until KWin or udev reports a change) runs the reconciler.
  It gives a new screen the main screen's wallpaper, a desk clock, a bar (the main bar on Plasma's primary
  screen, a secondary one elsewhere) and floating windows.
- **Monitors are known by their EDID** (maker, model, serial), not by connector. A monitor keeps its
  colours, size and place in your themes when it moves to another port. Run `./rice.py displays` to see them.
- **Odd arrangements get flagged.** Overlapping screens shrink each other's maximize area, and a screen
  apart from the others can't be reached by the pointer. You get a notification, and a chip on the Theme
  page, with a one-click fix. Nothing moves until you click.
- **UI size is standardised.** Each screen gets the size that looks the same from where you sit: the CSS
  reference pixel worked out from the screen's pixel density and a typical viewing distance for its kind
  (a laptop panel up close, a desk monitor, a TV across the room). A 1080p laptop panel gets a smaller UI,
  and an 8K left at scale 1 a much bigger one. You can change it in the launcher under Theme → Size
  (Automatic or one size everywhere, an overall size, and a per-screen override).

## Features

Each feature is `auto` (on when the machine has what it needs), `on` or `off`. Set them under `features` in
`~/.config/atom-plasma/settings.json`, and see what's on with `./rice.py doctor`:

| Feature | Needs |
| --- | --- |
| `claude`: Clawd and Claude usage on the bar, desk and popups | Claude Code |
| `tiling`: per-screen auto-tiling, a bar toggle, Meta+Alt+T | Krohnkite |
| `islands`: the bar's glass islands | Panel Colorizer |
| `keyboard_lights`: keyboard RGB in the screen's accents | an ASUS laptop (asusd) or a Razer keyboard |
| `battery_saver`: the launcher's battery saver card | a battery |
| `update_check`: a daily check for important updates | Arch/CachyOS and Claude Code |
| `boot_theme` / `login_theme`: boot menu, splash and login screen | Limine + Plymouth / Plasma Login Manager |

## Commands

```
rice.py next|prev|random|<image> [--screen focused|all|<output>]   a wallpaper, and the theme from it
rice.py preset save|load|delete <name>                             themes: every screen's look, by monitor
rice.py theme show|set|reset ...                                   hand-picked colours per screen
rice.py ui show|set ...                                            UI size
rice.py tiling toggle|tile|float [--screen ...]                    auto-tiling per screen
rice.py displays [--fix]                                           monitors, arrangement, sizes
rice.py install | doctor | setup                                   install, check, one-time settings
```

Shortcuts: Meta+Alt+N / B / R for the next, previous or a random wallpaper; Meta+Shift+W opens the Theme
page; Meta+Alt+T toggles tiling.

## Layout of the repo

| Path | What |
| --- | --- |
| `atom/` | the Python library: displays, reconcile, palettes (OKLab moods), screens, presets, KDE/KWin/apps theming, panels, tiling, caps, install, doctor |
| `rice.py`, `displayd.py`, ... | entry points |
| `qml/Rice/` | shared QML: design tokens, the per-screen palette, Clawd, controls |
| `plasmoids/` | the launcher, Glimpse (task strip and top band), desk clock, system rings, Claude usage, session, tiling toggle |
| `lnf/` | look-and-feel: splash and logout screen |
| `plasma-style/`, `kwin/`, `templates/`, `shell/` | Plasma Style generator, KWin effects, config templates, shell rice |
| `systemd/` | user units: display watcher, keyboard lights, update check |
| `pkg/` | PKGBUILDs for patched dependencies (per-output rounded corners) |
| `tests/` | `python3 -m unittest discover -s tests` (golden outputs, 20+ display topologies) |

Your settings live in `~/.config/atom-plasma/settings.json`, which overrides the repo's
`settings.default.json`. State lives in `~/.local/state/rice/` and caches in `~/.cache/rice/`.

## License

GPL-3.0-or-later (see `LICENSE`). The KWin effects in `kwin/` are adapted from KWin's own Scale and Fading
popups effects (GPL-2.0-or-later), and `pkg/` patches GPL projects (KDE-Rounded-Corners, BlueZ).
