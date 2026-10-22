"""Atom Plasma's library. The scripts in ~/.config/plasma-rice (rice.py, apps.py, boot.py, rgb.py, ...) are
the entry points the widgets, units and shortcuts run; the work happens here.

    util       folders, settings.json, safe writes, running commands, the log, templates, fonts
    palette    wallpaper -> palette (palette v2: moods, accents, surfaces, terminal colours)
    tokens     design tokens -> qml/Rice/Tokens.qml
    walls      the wallpaper collection: picking, checking, thumbnails, palettes (cached)
    presets    themes (presets) and hand-picked colours (overrides)
    screens    outputs and desktops, per-screen palettes, glass, desk layout, bar islands and clocks
    theme      the re-theme and picks, the Theme page's data, hand-picked colour commands
    kde        KDE config files, the colour scheme, the Plasma Style variant, the lock screen
    kwin       window border colours; window chrome (once, `rice.py setup`)
    terminals  ANSI colours, Konsole, Alacritty
    vscode     VS Code's Rice theme
    apps       btop, MangoHud, Zen, fastfetch; Dolphin and Darkly setup
    icons      the icon theme (Papirus-Rice folder colours when that's the theme)
    layout     where the desk's clock and music card sit on a wallpaper
    panel      the bar islands (Panel Colorizer), and rebuilding the bars
    style      the Plasma Style "Rice" / "Rice-Light" generator
    boot       Limine, Plymouth and the login screen
"""
