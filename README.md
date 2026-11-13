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
- **Bars fit their screen.** When a bar needs more room than its screen has (the main bar moving from a
  desk monitor to the laptop panel), its widgets give things up in a fixed order, least useful first, and
  take them back as soon as there's room: the CPU/RAM/GPU numbers (the rings stay), then the Claude
  numbers, then the pinned apps that don't fit fold into a folder tile that opens them in a popup, and
  last of all the battery's %. It follows the bar's real room live: screens, tray icons, new pins.
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

## The shell

The bar's widgets are islands, and their panels all open on one morphing sheet per screen: it grows out of
the island you clicked, glides to the next one while you point along the bar, and folds back into its
island when it closes (`qml/Atom`, hosted by the `com.zinoxx.shell` widget on every bar).

- **Launcher** (the jewel, Meta): that screen's windows fly into their pins, its bar fades away, and the
  launcher presents itself on the bare wallpaper: the jewel lifts into a search capsule, pinned apps come
  out as glass bubbles and the app library as category decks that open as folders. Other screens keep
  their windows; move the pointer to one and the launcher follows (your search comes along). Closing, or
  picking a window in the top band, brings the windows back where they were.
- **Power** (the power island, or the launcher's power button): a ripple of blur spreads over every screen
  and the session's actions come up big on yours.
- **Status island** (replaces Plasma's system tray): your apps' tray icons with menus in the rice's look
  (a click brings the app's window back; the quiet ones stand in a stack of stairs that fans out under the
  pointer, and an app with news steps out of it), the system's state, and beads for apps with
  notifications you haven't seen. It opens the **control
  center**: Wi-Fi, Bluetooth, Do Not Disturb, night light, power profile, battery saver, volume and
  microphone, every screen's brightness, what's playing, the apps' own volumes, your room's lights, and the
  notification history. With a room light setup at home (a lamp bridge on `127.0.0.1:48723`, a strip and
  wallpaper-sync service on `127.0.0.1:48724`), a light button joins the island and opens the **Room**
  panel: each light's level, white, colour and moods, and Match wallpaper.
- **Notifications** grow out of the status island on the screen you're working on, one card per chat.
- **Clock island**: the calendar, with Portuguese holidays and your Google Calendar
  (`./agenda.py set-url <the calendar's secret iCal address>`; it stays in `~/.config/atom-plasma/secrets.json`).
- **Clipboard history** on Meta+V.

The shell needs a small native module (`pkg/atom-native`: blur behind the sheet, input masks, the tray host;
`rice.py install` builds it into `~/.local/lib/qt6/qml`; needs `libdbusmenu-lxqt`) and, for the calendar,
`python-icalendar` and `python-recurring-ical-events`. After a Qt or Frameworks upgrade, rebuild it with
`pkg/atom-native/build.sh`.

## Clawd

The Claude island (and, on one screen, the desk clock) is home to Clawd, Claude Code's creature, in pixel
art. It shows what Claude Code is doing (typing, thinking, running commands, reading, on the web, handing
work to subagents, compacting), what its last answer was about, and how much of your usage limits is left:
it tires as a window fills up and dozes by an hourglass when one runs out. Off duty it never sleeps: it
has thirty hobbies, picked by the hour, the season and the weather, a new one every five minutes, each
with a little project that moves on while you watch (a scarf gets longer, a marshmallow turns golden, a
snowman gets its hat), and now and then someone drops by (a bird, a falling leaf, a ghost at Halloween).
Hover it for a hello, stroke it back and forth, click it for one of its acts; a double click opens Claude
Code in a terminal. Every Clawd on every screen does the same thing at the same moment.

Each one is a single canvas, repainted only when its picture changes, and it holds still behind a
fullscreen window (`qml/Rice/Clawd.qml`; the art is in `ClawdArt.js`, the acts and hobbies in
`ClawdActs.js`). To look at them while changing them, `tools/clawd/sheet.qml` renders contact sheets.

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

Shortcuts: Meta opens the launcher; Meta+V the clipboard's history; Meta+Alt+N / B for the next or previous
wallpaper, Meta+Alt+Shift+N for a random one (rebind in System Settings → Shortcuts); Meta+Shift+W opens the
Theme page; Meta+Alt+T toggles tiling.

## Layout of the repo

| Path | What |
| --- | --- |
| `atom/` | the Python library: displays, reconcile, palettes (OKLab moods), screens, presets, KDE/KWin/apps theming, panels, tiling, caps, install, doctor |
| `rice.py`, `displayd.py`, ... | entry points |
| `qml/Rice/` | shared QML: design tokens, the per-screen palette, Clawd (its art and its acts), controls |
| `qml/Atom/` | the shell: its switchboard, the morphing sheet, panels (calendar, control center, clipboard...), notification cards, the power overlay |
| `plasmoids/` | the launcher, Glimpse (task strip and top band), desk clock, the clock and status islands, system rings, Claude usage, session, tiling toggle, the shell's host |
| `agenda.py` | the calendar's data: holidays and your Google Calendar |
| `lnf/` | look-and-feel: splash and logout screen |
| `plasma-style/`, `kwin/`, `templates/`, `shell/` | Plasma Style generator, KWin effects, config templates, shell rice |
| `systemd/` | user units: display watcher, keyboard lights, update check |
| `pkg/` | PKGBUILDs for patched dependencies (per-output rounded corners) and the shell's native module |
| `tests/` | `python3 -m unittest discover -s tests` (golden outputs, 20+ display topologies) |
| `tools/nested/` | a nested, isolated KWin + plasmashell with fake input, and the shell's tests in it (`test-*.sh`) |

Your settings live in `~/.config/atom-plasma/settings.json`, which overrides the repo's
`settings.default.json`. State lives in `~/.local/state/rice/` and caches in `~/.cache/rice/`.

## License

GPL-3.0-or-later (see `LICENSE`). The KWin effects in `kwin/` are adapted from KWin's own Scale and Fading
popups effects (GPL-2.0-or-later), and `pkg/` patches GPL projects (KDE-Rounded-Corners, BlueZ).
