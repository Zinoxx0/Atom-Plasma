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
  It gives a new screen the main screen's wallpaper, a desk clock, a bar and floating windows.
- **One set of islands, on the screen you're on.** Every screen has a bar, but the islands show on one at
  a time: the screen the pointer rests on, unless a fullscreen window (a game, a movie) covers it; then the
  free screen with the most pixels, the nearest on a tie (none at all when every screen is fullscreen).
  They follow the pointer at once, with a quick fade (a pointer just sweeping across a screen on the way
  somewhere else moves nothing; `kwin/rice_islands`, a KWin script; hidden bars keep their place, so no
  window ever resizes). The islands are notches on the screen's bottom edge, rounded only at the top; the
  launcher and the clock sit in the screen's corners. Five of them: the launcher, your pins, the meters
  (Claude's double ring with the time until its session resets, then the CPU/RAM/GPU rings: no numbers on
  the bar, they're in the popups), the status island (tray apps, the system's state, tiling, power) and
  the clock.
- **The bar docks under a window.** When a window is maximized or touches the bar, the islands fuse into
  one full-width bar that meets the window's edge: the gaps fill with the same glass, corners straighten,
  outlines and shadows give way to one hairline along the top. When the window lets go they come apart
  again. Nothing moves, only fills, corners and lines ease (Panel Colorizer's preset auto-loading switches
  between the two looks and its animations do the morph).
- **Bars fit their screen.** When a bar needs more room than its screen has (the islands moving from a
  desk monitor to the laptop panel), the pinned apps that don't fit fold into a folder tile that opens them
  in a popup, and come back as soon as there's room. It follows the bar's real room live: screens, tray
  icons, new pins.
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

- **Launcher** ("Atom Home": the jewel, Meta): that screen's windows fly into their pins and Home fades in
  on the frosted wallpaper, under the top band (never over it): pages Home, Games and Apps as rows of
  tiles, the focused row in front, the others behind it, smaller and see-through; a hero for
  whatever has the focus; typing searches. The pointer focuses what it rests on, not what it sweeps across on
  its way to the hero. The palette opens the Theme page (themes, wallpapers, colours, size, lighting), every
  setting in sight: each row's own tools in its header (shuffle, the folder, finding more online, intensity,
  the keyboards' brightness and power), an accent's colour edited at its tile, a look named where you save
  it, the screens (one, or all) on the desk map. Its size follows the screen's UI size, so a big monitor
  shows more, not the same bigger. A game controller drives it too (D-pad or stick to move, A to open,
  B to go back, LB/RB for the pages, X for an item's options, Y for the Theme page), as it does the power
  overlay; the hints at the bottom switch to its buttons once you use it.
  Other screens keep their windows; move the pointer to one and the launcher follows (your search comes
  along). Closing, or picking a window in the top band, brings the windows back where they were.
- **Finder** (KRunner's replacement): Alt+Space, Alt+F2, the Search key, the desktop menu's Run Command and
  typing on the bare desktop open the launcher's search on its own: the field and its results on one
  frosted glass plate at the top of the screen, over whatever is there (Alt+Shift+F2 searches the clipboard). The shell
  holds KRunner's place on the bus and KRunner's own daemon is masked (`rice.py install`).
- **Power** (the power island, or the launcher's power button): a ripple of blur spreads over every screen
  and the session's actions come up big on yours.
- **Out of the way**: while the launcher or the power page is open the windows are minimized (the launcher's
  screen; every screen for the power page) and come back when it closes, and the bar's islands leave the
  launcher's screen for another one, as they do for a fullscreen game.
- **Blur style** (Theme page): the launcher and the power page always wear the same backdrop: *Noisy matte*
  (your wallpaper frosted under a fine grain, a still matte finish that hides the windows) or *Clear blur* (a
  live blur of whatever is behind, like glass) or *No blur* (your wallpaper as it is, sharp, with only the dark
  shade that keeps text readable). `rice.py blur matte|clear|none`.
- **Status island** (replaces Plasma's system tray): your apps' tray icons with menus in the rice's look
  (a click brings the app's window back; the quiet ones rest on each other in a stack, and an app with news
  steps out of it), the system's state, and beads for apps with notifications you haven't seen. The stack
  (or a bead) opens the **Apps** panel: the notification history by app, then the apps in the background.
  The system's glyphs open the **control center**: Wi-Fi, Bluetooth, Do Not Disturb, night light, power
  profile, battery saver, volume and microphone, every screen's brightness, what's playing, the apps' own
  volumes and your room's lights. With a room light setup at home (a lamp bridge on `127.0.0.1:48723`, a strip and
  wallpaper-sync service on `127.0.0.1:48724`), a light button joins the island and opens the **Room**
  panel: each light's level, white, colour and moods, and Match wallpaper.
- **Notifications** grow out of the status island on the screen you're working on, one card per chat.
- **Clock island**: the calendar, with Portuguese holidays and your Google Calendar
  (`./agenda.py set-url <the calendar's secret iCal address>`; it stays in `~/.config/atom-plasma/secrets.json`).
- **Clipboard history** on Meta+V.

The shell needs a small native module (`pkg/atom-native`: blur behind the sheet, input masks, the tray host,
the bus the KWin script talks to, KRunner's place;
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

On the bar there is one Clawd at a time, in one of three places: standing on the meters island's roof
over the middle of Claude's ring, when nothing covers the space above it (his seat in the island closes
meanwhile); back inside the island, nearly as big, when a window does; in the popup while it's open.
Between them it jumps.

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
| `plasma-style/`, `kwin/`, `templates/`, `shell/` | Plasma Style generator, KWin effects and the islands script, config templates, shell rice |
| `systemd/` | user units: display watcher, keyboard lights, update check |
| `pkg/` | PKGBUILDs for patched dependencies (per-output rounded corners) and the shell's native module |
| `tests/` | `python3 -m unittest discover -s tests` (golden outputs, 20+ display topologies) |
| `tools/nested/` | a nested, isolated KWin + plasmashell with fake input, and the shell's tests in it (`test-*.sh`) |

Your settings live in `~/.config/atom-plasma/settings.json`, which overrides the repo's
`settings.default.json`. State lives in `~/.local/state/rice/` and caches in `~/.cache/rice/`.

## License

GPL-3.0-or-later (see `LICENSE`). The KWin effects in `kwin/` are adapted from KWin's own Scale and Fading
popups effects (GPL-2.0-or-later), and `pkg/` patches GPL projects (KDE-Rounded-Corners, BlueZ).
