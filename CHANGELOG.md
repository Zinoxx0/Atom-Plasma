# Changelog

## Unreleased

**Theme page**
- Hovering from one wallpaper to the next fades straight between them (it cut back to the wallpaper in use
  first), each one once its picture has loaded; items that show the same picture (colours, sizes) leave it
  alone.
- Every group is closed whenever the page opens, and it opens on what's in use. Your themes sit above the
  groups; the Taskbar group lives inside Desktop.
- Sizes are sliders in steps of 0.05, from 0.80× to 1.80×: the launcher's, and the top bar's, which now has a
  size of its own (it followed the taskbar's; `rice.py top size F`, settings `top.size`); the taskbar's size
  moved into the Taskbar group.
- "Blur style" is now "Backdrop style", with a fourth style, *Noisy only*: the sharp wallpaper under the
  grain (`rice.py backdrop matte|clear|noise|none`; `rice.py blur` still works). Settings move from
  `blur.style` to `backdrop.style` and from `ui.top` to `top.size` on their own (state version 3).

**CI**
- The test job installs libplasma (for qmllint) and the iCal libraries (for the calendar test).

## 1.0.0 (2026-11-15)

The first release: a KDE Plasma 6.8 (Wayland) desktop themed from its wallpapers, with its own shell.

**Theme engine** (`rice.py`, `atom/`)
- Palettes from each wallpaper (OKLab analysis, five moods), applied to KDE, the Plasma Style, KWin's borders,
  terminals, VS Code, Zen, btop, MangoHud, fastfetch, the boot surface, the login screen and RGB keyboards.
- Every screen gets the whole rice when screens come and go (`atom-plasma-displayd`), at a size worked out
  from each monitor's pixel density and viewing distance. Themes (presets) follow monitors between setups.

**Shell** (`qml/Atom`, `pkg/atom-native`, `plasmoids/`, `kwin/`)
- A bar of glass islands that shows on one screen at a time and docks under maximized windows.
- Atom Home: a full-screen launcher with Home, Games, Apps and a Theme page, driven by keyboard, pointer or a
  game controller; its search replaces KRunner.
- A status island with the tray, a control center, notifications by app, the clipboard history, a calendar
  with your Google Calendar, a power page, Glimpse (the task strip), desk widgets and room lights.
- Clawd, Claude Code's creature, on the bar and the desk, fed by Claude Code's hooks and status line.

**For contributors**
- `docs/ARCHITECTURE.md` and `CONTRIBUTING.md`; tests for the engine (golden outputs), QML run offscreen, a
  qmllint pass, the game controller (opt-in), and nested KWin sessions for the shell (`tools/nested/`).
- `rice.py install` sets everything up and migrates older setups (the programs moved to `bin/`, Clawd's
  hooks); `rice.py doctor` checks it.
