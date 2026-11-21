# Changelog

## Unreleased

**Theme page, redesigned** (the same page in both launcher styles; designed in the Atom lab)
- Everything on one screen, nothing folded away. On the left, two panels of one kind: the screen you're
  editing (your desk to scale, the one you edit framed in the accent, "All screens" beside it) with its
  Wallpapers and Colours, then Everywhere (Saved looks, Launcher, Desktop, Lighting), each showing its
  value now. On the right, the section, whole.
- Wallpapers: a grid of every one, sorted by the accent it would give (a dot says which), filtered by mood,
  badged with the screens it's on. The one in focus previews on the desk map and on the whole page (its
  picture and its palette). Shuffle, the folder and finding more online sit in the header.
- Colours: the moods as pictures of what they make from the screen's hue, the three accents (the colour
  editor opens at a swatch), back to the wallpaper's, and intensity. Saved looks: each as its desk in
  miniature, plus this desk to save. Launcher and Desktop: every style as a picture over your wallpaper,
  sizes as tick sliders. Lighting: both keyboards side by side, each with its keys as they shine.
- Find more online: wallhaven inside the page. Describe what you'd like (or pick a recent search or an idea);
  the results are shaped for the screen you're editing and leave out what you have. Nothing is downloaded until
  you pick one: A adds it to your wallpapers, A again sets it. More brings the next ones. (`wallhaven.py
  --browse` / `--get`.) The old detailed theme panels are gone.
- One focus ring glides over it all: arrows or a pad's D-pad move it, A applies, B goes back to the sections
  and then out, LB/RB step the sections, PgUp/PgDn the screen, Y shuffles, X opens a look's or an accent's
  options. The pointer takes the focus where it rests.

**Bar**
- Docked (a window maximized or touching it), the islands fill the floor to its top: the launcher's jewel no
  longer stops short of it, and the icons sit in the floor's middle. The pins keep their size.

**Launcher styles** (new: settings `launcher.style`, `rice.py launcher style NAME`)
- Two launchers, each its own code: **Simplified** (the rows under a hero, as before; the default) and
  **Atom's** (new): your apps as an atom. Rings round a glass core that shows what has the focus: Pinned,
  Play (games with their art) and Recent on Home; categories, their apps and the app's own actions on Apps;
  a grid of Steam banners with play time and the library's buttons on Games; search as one ring of matches.
  Its Theme page is a dial of sections: your wallpapers as a colour wheel (one ring per mood, each where
  its colour is; the page wears the one you're on), sizes as gauges, choices as rings of options.
- Only the chosen style is loaded; a new choice applies the next time the launcher opens, and a style that
  fails to load falls back to Simplified. Any `ui/styles/NAME/Stage.qml` is a style.
- Simplified's top got the new look: the pages as words with a beam of accent light, a search field,
  plain theme and power buttons, the time with the date, on a gradient from the top edge.
- `rice.py walls-index`: every wallpaper's mood, hue and palette (for the colour wheel), cached.
- `rice.py launcher-data` now carries Steam's play time and last session for each game.

**Game controller** (new: `bin/pad.py`, `atom-plasma-pad.service`, feature `gamepad`)
- A controller drives the desktop: the left stick is the pointer, the right one scrolls, the D-pad and the
  buttons are the keys apps understand, Guide opens the launcher, View every window. Games get the
  controller to themselves.
- An on-screen keyboard (Atom Keyboard, on each screen's sheet) in the screen's palette: the active layout's
  keys from XKB, accented letters, typed as real key presses. It comes up on its own for a text field the
  controller clicked, drags out of the way by its bare parts (never from a key), and View sends it to the
  top of the screen and back.
- Atom Pad's input method (`pkg/atom-pad-im`, a small C program KWin starts as its input method): characters
  the layout can't type (accents on a US layout) go straight into the focused field. Where an app has no
  text-input support, the clipboard still carries them (and gets its own back).
- The launcher reads an Xbox controller's X and Y by their place (X opened the Theme page, Y the menu).

**Launcher**
- A left click on empty space no longer closes it (a missed tile did); a right click still does.

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
