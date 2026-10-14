# Agent C: apps and windows (milestone 4)

Read `agents/COMMON.md` first. You don't restart plasmashell or KWin; you may load/unload/reconfigure KWin
EFFECTS over D-Bus (`qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect|unloadEffect|reconfigureEffect <id>`)
and run `qdbus6 org.kde.KWin /KWin reconfigure` when a setting needs it (then check the journal for Krohnkite
errors; never touch the Krohnkite script itself). You may open and close test windows (konsole, dolphin).

## You own
- In `~/.config/plasma-rice/rice.py`, ONLY these functions: `ansi`, `konsole`, `apply_konsole`, `alacritty`,
  `apply_kwin` (the orchestrator won't edit them meanwhile). `apps.py`. `templates/` (starship etc.).
- KDE configs: konsolerc, ~/.local/state/konsolestaterc, ~/.local/share/konsole/*, dolphinrc, darklyrc,
  klassy/klassyrc, kwinrc ([Effect-*], [Plugins] for effects, [Round-Corners], Better Blur DX settings),
  fastfetch config (~/.config/fastfetch/), alacritty config, ~/.local/share/kwin/effects/ (new JS effects).
Not yours: plasmoids, Plasma Style, panel/build.py, tokens.py (read it: radius md 14 = windows).

## Tasks
1. Konsole: hide the menu bar and both toolbars for good (konsolerc + konsolestaterc; make sure new windows
   respect it), tab bar only when needed with a pill-tab stylesheet generated from the palette
   (TabBarUseUserStyleSheet), margin 16 and centred text, dim when inactive (subtle), JetBrainsMono Nerd Font
   (check the size reads well vs the UI's Inter 13 px), ANSI colours mapped from the palette's accent tiers
   (look at HyDE's kitty mapping: blacks from surfaces, brights lifted), remove the stale "Tokyo Night" profile
   (make sure the default profile is the generated one). Opacity ~0.85 with blur.
2. Alacritty: its blur doesn't work on KWin 6.7 (old protocol only): add it to Better Blur DX's force-blur
   WindowClasses (currently "zen\ndolphin"), and align its font/padding/cursor with Konsole.
3. Dolphin + Darkly: tidy toolbar (fewer buttons, no clutter), Places panel styling, view opacity tuned so text
   stays readable over the wallpaper, sensible preview size, no status-bar clutter.
4. Window decoration: Klassy and ShapeCorners must agree: one radius (tokens radius md 14) and one corner shape
   (ShapeCorners squircle vs Klassy round: pick one that matches; check that shadows follow the clipped corner).
   Simplify buttons: app menu/icon on the left, minimize/maximize/close on the right (today "MFSE" / "HIAX").
   Titlebar font from tokens (Inter), sensible height; a subtle accent-tinted shadow on the active window if Klassy
   supports it.
5. KWin motion, smooth and subtle (user's choice): write JS effects in ~/.local/share/kwin/effects/:
   `rice_window` (window open: fade + scale 0.96 -> 1, OutCubic; close: fade + 0.98, InCubic; ~200/160 ms at normal
   speed; use animationTime()) based on /usr/share/kwin-wayland/effects/scale/contents/code/main.js (copy + rename
   Id), and `rice_popups` (menus/tooltips/dropdowns: fade + 4 px slide) based on fadingpopups. Turn off Burn My
   Windows' glide (kwin6_effect_glide) and stock scale/fadingpopups if they'd double up; keep magiclamp (minimize
   into the Glimpse pills). Test by opening/closing konsole windows and right-click menus; record a few frames
   (spectacle) if possible.
6. Blur strength: Better Blur DX strength 11 is high (DP-3's frames are copied between GPUs): try 8, compare looks
   (screenshots), keep the lower one unless it clearly looks worse.
7. fastfetch config: boxed sections, palette-coloured keys, a nice logo (Konsole can show sixel images: test
   `fastfetch --logo-type sixel` with a small Clawd/wallpaper-square image; fall back to a text logo), plus a
   starship prompt refinement (templates/) keeping it fast.
8. Icons and cursor: install candidates (`sudo pacman -S --needed tela-circle-icon-theme-dracula
   tela-circle-icon-theme-purple` or similar from extra; `paru -S --needed bibata-cursor-theme`), then render a
   side-by-side comparison image (offscreen, from the icon/cursor files: ~16 common apps + folders; cursors as PNGs)
   of current Papirus-Rice vs Tela-circle variants and Simp1e-Tokyo-Night vs Bibata. Do NOT switch the user's
   theme: the user picks at the check-in.

## Done means
Konsole/Dolphin/Alacritty screenshots before/after, decoration close-ups (active/inactive, maximized), the effect
running without journal errors, the icon/cursor comparison image, all in `~/.cache/rice/shots/agent-c/`. Rerunning
`rice.py restore` must reproduce your Konsole/Alacritty/KWin results (generated, not hand-edited, where rice.py
generates them). Report per COMMON.md.
