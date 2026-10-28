# Atom Plasma

A KDE Plasma 6 rice driven by the wallpaper: every screen gets its own wallpaper and palette, and the
desktop follows. That covers the colour scheme, the Plasma Style, terminals, VS Code, Zen, window borders,
bar islands, the login screen and keyboard lighting.

> **Status:** personal setup, being refactored to work on any monitor layout and on other machines.
> Install steps are not automated yet (planned: `atom install` / `atom doctor`).

## What's inside

| Path | What |
| --- | --- |
| `atom/` | the Python library: palettes (OKLab moods), screens, KDE/KWin/apps theming, panels, boot/login theming |
| `rice.py` and friends | entry points (wallpaper picks, themes/presets, setup) |
| `qml/Rice/` | shared QML module: design tokens, per-screen palette, Clawd, controls |
| `plasmoids/` | widgets: launcher, Glimpse (task strip + top band), desk clock, system rings, Claude usage, session |
| `lnf/` | look-and-feel package: splash and logout screen |
| `plasma-style/` | generator for the "Rice" Plasma Style |
| `kwin/` | KWin effects for window and popup motion |
| `pkg/` | PKGBUILDs for patched dependencies (per-output rounded corners) |
| `systemd/`, `templates/`, `shell/` | user units, config templates, shell rice |
| `tests/` | golden tests: `python3 -m unittest discover -s tests` |

## Requirements (current)

Plasma 6.8 on Wayland, Python 3 with Pillow and numpy, ImageMagick, Panel Colorizer, Darkly, Klassy,
KWin better-blur-dx, Krohnkite (optional). The Arch/CachyOS-specific parts (update check, Limine/Plymouth
theming) are optional.
