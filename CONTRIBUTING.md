# Contributing

Thanks for helping. Start with [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): it says what each part is and
how they talk to each other.

## What you need

- KDE Plasma 6.8 on Wayland (the shell runs inside `plasmashell` and talks to KWin).
- Python 3 with Pillow, numpy, dbus-python and PyGObject.
- Qt 6 tools: `qt6-declarative` (for `qml6` and `qmllint`), and CMake, Ninja and a C++20 compiler for
  `Atom.Native`.

## Setting up

```sh
git clone https://github.com/Zinoxx0/Atom-Plasma ~/.config/plasma-rice
cd ~/.config/plasma-rice
./rice.py install            # links the widgets, effects and units into this checkout, sets plasmashell's environment
pkg/atom-native/build.sh     # builds Atom.Native into ~/.local/lib/qt6/qml
# log out and back in once
./rice.py doctor             # checks that everything is in place
```

Everything installed is a link into the checkout, so your edits are live after a reload.

## Seeing your change

| You changed | To see it |
|---|---|
| QML (`plasmoids/`, `qml/`) | `systemctl --user restart plasma-plasmashell` |
| `pkg/atom-native` | `pkg/atom-native/build.sh`, then restart plasmashell |
| a KWin script or effect | KWin caches scripts by path: load a copy from a new path (`Scripting.loadDeclarativeScript`), or log out and in |
| the engine (`atom/`, `rice.py`) | run the command again (e.g. `./rice.py restore`) |

Try shell changes in a **nested session** first: `tools/nested/run.sh` starts KWin and Plasma inside a window,
with their own configuration, so a mistake can't break your desktop. The `tools/nested/test-*.sh` scripts
drive one part each (the launcher, the panels, the tray, the notifications...) and exit 0 when it works. Read
`tools/nested/run.sh` for the options (screen size, two screens, a fractional scale).

While plasmashell runs, `journalctl --user -u plasma-plasmashell -f` shows QML errors. A component that fails
to load is only logged there; it simply doesn't show.

## Tests

```sh
python3 -m unittest discover -s tests
```

- Engine tests compare against golden files in `tests/golden/`. If you changed an output on purpose, check
  the diff and accept it with `RICE_UPDATE=1 python3 -m unittest discover -s tests`.
- `tests/test_qmllint.py` runs Qt 6's `qmllint` over all QML and fails on mistakes that break a component at
  load time (a missing required property, a syntax error, a duplicate binding).
- `tests/test_clawd.py` and `tests/test_barfit.py` run QML offscreen. They need OpenGL through a display
  (your session, or `xvfb-run` on a server).
- `tests/test_gamepad.py` plugs in a pretend game controller (uinput) for a few seconds, so it runs only with
  `RICE_DEVICE_TESTS=1` (and write access to `/dev/uinput`). Run it when you touch `Atom.Native`'s `Gamepad`.
  To catch memory errors, build a copy with `-fsanitize=address` and run it with that copy's `libasan.so`
  preloaded (`ATOM_NATIVE_QML=<its qml folder>`).

Run the tests before every commit.

## Conventions

**QML**

- Import the shared modules by name: `import Rice`, `import Atom`, `import Atom.Native`. (Only `lnf/`, which
  runs outside plasmashell, imports `Rice` by path.)
- A component's inputs are `required property` declarations; pass what it needs, not the whole parent, when
  you reasonably can.
- In new code, qualify names: `root.width`, `stage.rice`, not a bare `rice` found by scope. qmllint warns
  about unqualified access; older files still have plenty, so don't reformat them in passing.
- Colours come from the screen's palette (`RicePalette`) and sizes and durations from `Tokens` (use
  `Tokens.ms(...)` so the user's animation speed applies). Don't hard-code either.
- Don't poll. Watch files with `WatchedJson`, listen to D-Bus or KWin, and run timers only while something
  is visible. A widget on a hidden bar (`Shell.barShown(screen)` is false) should do nothing.
- Don't bind to `Bus.state`: it changes as a whole. Keep your own value, updated from `Bus.message`.

**Python**

- The work lives in the `atom` package. `rice.py` is the command line; a program that something else runs by
  path (a unit, a widget, a shortcut, a Claude Code hook) goes in `bin/`, stays small, and finds `atom` one
  folder up. Widgets call it as `$HOME/.config/plasma-rice/bin/<name>` (the installer links a clone kept
  elsewhere there).
- Run commands with `util.run(...)` (an argument list, a timeout, failures logged), never `shell=True`.
- Write files other parts read with `util.write_if_changed` or `util.save_json`: they write a temporary file
  and rename it, so a reader never sees half a file.
- Log with `util.log` and `util.warn` (they go to `~/.local/state/rice/rice.log`).

**Commits**

- One finished, tested step per commit. The message says what changed and why, in plain words.
