# How Atom Plasma is built

Atom Plasma themes a KDE Plasma 6 desktop from its wallpapers and replaces much of Plasma's own shell (bar,
launcher, tray, clock, notifications, panels) with its own. It has two halves that never call each other
directly:

- **The theme engine** (Python): reads the wallpapers, works out palettes and sizes, and writes files and
  settings that Plasma, KWin, apps and the shell read.
- **The shell** (QML, inside `plasmashell`, plus a little C++ and two KWin scripts): draws the bar, the
  launcher, the panels and the desk widgets, and recolours itself whenever the engine's files change.

They meet in files (JSON under `~/.local/state/rice` and `~/.cache/rice`, watched with inotify) and in a few
commands the shell runs (`rice.py ...`).

## The repository

| Path | What it is |
|---|---|
| `rice.py` | The command line: wallpapers, the bar's and the launcher's styles, install, doctor, displays, presets. Run `./rice.py` for the list. |
| `atom/` | The engine as a Python package: palettes (`palette.py`, `theme.py`), screens and sizes (`displays.py`, `screens.py`, `reconcile.py`), the bar's islands (`panel.py`), install and doctor, KWin and plasmashell scripting (`kwin.py`, `kwinscript.py`, `js/`). |
| `qml/Rice/` | The design system, a QML module (`import Rice`): `Tokens` (sizes, motion, radii), `RicePalette` (a screen's palette), shared controls, `WatchedJson`, Clawd, and the JavaScript helpers `C` (colour), `M` (motion) and `Session`. |
| `qml/Atom/` | The shell, a QML module (`import Atom`): `Shell` (the switchboard: which panel is open where), `Windows` (the task model), `Notify`, `Prefs` (settings), the sheet that panels grow on, the power page, backdrops, toasts, `Pad` + `Keyboard` (the game controller's on-screen keyboard, on the sheet). Panels live in `qml/Atom/panels/`. |
| `pkg/atom-native/` | `Atom.Native`, the C++ part of the shell: KWin blur regions, input masks, the in-process message bus (`Bus`, also on D-Bus), the tray host, the game controller, the shared file watcher (`FileWatch`), `WindowRest`. Built per user with `build.sh`. |
| `plasmoids/` | The Plasma widgets. They're thin: each draws its island and asks `Atom.Shell` for its panel. The launcher (`com.zinoxx.launcher`) is the biggest; its full-screen surface is `Stage.qml` and the components next to it. |
| `kwin/` | `rice_islands`, a KWin script (which screen shows the bar's islands), and `rice_window` and `rice_popups`, KWin effects in JavaScript (window and popup motion). |
| `lnf/` | The look-and-feel package: the splash and logout screens. They run outside plasmashell, so they import `Rice` by path. |
| `plasma-style/`, `templates/`, `tokens.py` | The Plasma Style generator, the shell and prompt templates, and the design tokens (defined in `atom/tokens.py`; `tokens.py` and every `rice.py` run write `qml/Rice/Tokens.qml`). |
| `systemd/` | User units: the display watcher, keyboard lighting, the update check. |
| `pkg/` | Packages built from source: `atom-native`, a fork of the rounded-corners effect, a BlueZ fix. |
| `tests/` | `python3 -m unittest discover -s tests`: the engine (golden outputs), QML run offscreen, and a qmllint pass. |
| `tools/` | Development tools: nested KWin sessions for testing the shell (`tools/nested/`), a uinput pointer (`pointer.py`), screenshot sheets. |
| `bin/` | Programs that units, hooks, widgets and shortcuts run by path: `displayd.py` (display watcher), `rgb.py` (keyboard lighting), `pad.py` (a game controller drives the desktop: evdev in, uinput out), `weather.py`, `agenda.py`, `update-check.py`, `wallhaven.py`, `battery-saver.py`, Claude Code's side (`clawd-hook.sh`, `clawd-intent.py`, `ask.sh`, `claude-statusline.sh`; `rice.py install` sets them in `~/.claude/settings.json`; `claude-usage.py`, the usage limits from Anthropic every 5 minutes), and small wrappers. They find the `atom` package one folder up. |

## How a change of wallpaper reaches the screen

1. `rice.py next` (or the Theme page) picks an image. `atom/theme.py` analyses it (OKLab), builds a palette
   and applies it everywhere it goes: the KDE colour scheme, the Plasma Style, terminals, VS Code, Zen, the
   keyboard lights. Each screen also gets its own palette file,
   `~/.local/state/rice/palette-<connector>.json`.
2. Every widget has a `RicePalette { output: Screen.name }`. Its `WatchedJson` sees the file change and
   reads it again (an `XMLHttpRequest`: no process), and every colour bound to it follows.

User settings live in `~/.config/atom-plasma/settings.json` over the repository's `settings.default.json`.
`Atom.Prefs` watches that file, so a setting changed by `rice.py` shows at once.

## Inside plasmashell

- **One switchboard.** `Atom.Shell` holds which panel is open (`kind`), on which screen, and the island it
  grew from. Bar widgets call `Shell.toggle(...)`; each screen's sheet window (`SheetWindow`) draws the panel.
  The launcher and the power page are full-screen surfaces of their own.
- **One set of islands.** Every screen has a bar, but KWin's `rice_islands` script shows the islands on one
  screen at a time and posts `{screen, covered, pointer}` to plasmashell over D-Bus (`Atom.Native` `Bus`,
  object `/Atom`, method `Post`). `Shell.bar` and `Shell.barShown(screen)` carry it to the widgets; widgets
  on a hidden bar stop their timers and reads.
- **The launcher** (`plasmoids/com.zinoxx.launcher`): `main.qml` is the island; `Stage.qml` is the
  full-screen home (focus, navigation, open and close), with `StageRoom` (the backdrop that follows the
  focus), `StageTopBar`, `StageSearch` and `LaunchFlight` beside it, the rows and tiles in `HomeRow` and
  `HomeTile`, and the data in `HomeModel` and `ThemeModel`. Each style (`ui/styles/NAME/`) has its own look;
  the Theme page (`ui/theme/ThemeStudio.qml` and its parts) is shared by every style: the stage gives it the
  keys, the wheel and the pad's Y, and wears the wallpaper and palette it previews.

## Rules the code follows

- **Nothing polls when it can watch.** Files are watched (`WatchedJson`, backed by one native inotify watcher
  for the whole process), D-Bus and KWin report changes, timers run only while something is shown.
- **No process per read.** Files are read with `XMLHttpRequest` (plasmashell runs with
  `QML_XHR_ALLOW_FILE_READ=1`); commands go through `RiceShell` only for actions.
- **Hidden things rest.** Bars whose islands are elsewhere stop their work; the launcher and the power page
  give their video memory back while a fullscreen window is up or after ten minutes closed (`WindowRest`).
- **Writes are atomic.** The engine writes to a temporary file and renames it (`util.write_if_changed`).
- **Never bind to `Bus.state`.** It has one change signal for every key; keep your own value and update it
  from `Bus.message`, as `Shell.bar` does.
- **Components take what they need as `required` properties**, and the qmllint test catches one that's
  missing (plasmashell only logs it, and the component silently doesn't show).
