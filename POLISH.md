# Polish pass: live handoff file

Read this first when resuming. The full plan is `~/.claude/plans/stateless-sauteeing-map.md`.
Goal: HyDE-level polish on KDE Plasma (bars/islands, widgets, launcher, Glimpse top band, Konsole,
Dolphin, decorations/motion, lock/logout/login, boot). Vibe: clean, modern, detailed, animated, tech-y,
not cold or cyberpunk.

## How to resume
1. `git status` in `~/.config/plasma-rice`, `~/.local/share/plasma/plasmoids`,
   `~/.local/share/plasma/look-and-feel`. Uncommitted edits = an interrupted agent or step: review the diff
   before keeping it (`git diff`), never blindly commit.
2. Check the milestone table and the "Agents" table below; re-brief any agent whose work isn't integrated.
3. `~/.config/plasma-rice/ask.sh --status` shows a pending "!" check-in for the user.
4. Do "Next step".

## Milestones
| # | Area | Owner | Status |
|---|------|-------|--------|
| 0.1 | "!" attention over Clawd | orchestrator | done 2026-10-14 (ask.sh, verified both bars + Done button) |
| 0.2 | Safety net (git x3, backup tarball) | orchestrator | done 2026-10-14 |
| 0.3 | Baseline screenshots + perf | orchestrator | done 2026-10-14 (~/.cache/rice/shots/baseline) |
| 0.4 | Design tokens + shared QML module | orchestrator | done 2026-10-15 (tokens.py, qml/Rice, token sheet) |
| 0.5 | Plasma 6.8 upgrade (own step when it lands) | orchestrator | done 2026-10-16: arrived via cachy-update, AUR plugins rebuilt (kara dropped: unused, won't build), rebooted 14:15, verified (effects, Colorizer, bars, bands, no QML errors) |
| 1 | Shell surfaces (Plasma Style, bars, popups) | agent A | integrated 2026-10-16 (commits 8354c03, 9a39a11); check-in pending |
| 2 | Glimpse opened band v2 | agent B | integrated 2026-10-15 (commit in plasmoids repo); check-in raised |
| 3 | Launcher, logout, lock | agent A | integrated 2026-10-16 (a90a187, 94e8301; kdeglobals LookAndFeelPackage=com.zinoxx.rice); live check pending |
| 4 | Konsole, Dolphin, decorations, KWin motion | agent C | integrated 2026-10-16 (3d187d8); check-in pending |
| 5 | Boot chain (Limine, Plymouth, login, splash) | agent C + orchestrator | applied 2026-10-16 (4e26020; limine header + limine-mkinitcpio run by orchestrator, both initramfs contain the rice theme); rebooted 12:18, logs clean |
| 6 | Consistency sweep, perf, memory | orchestrator | done 2026-10-16 (shots/m6, perf 11.3 W vs 15.9 W baseline) |

## Agents
| Agent | Brief | Owns | State | Last commit |
|-------|-------|------|-------|-------------|
| A shell | agents/A-shell.md (M1, done) then agents/A-launcher.md (M3, done) | plasma-style/build.py, plasmoids session/sysstats/claudeusage/wallpicker, qml/Rice/{Clawd,Ring}.qml + new Rice files | done | M1 8354c03 9a39a11, M3 a90a187 94e8301 |
| B glimpse | agents/B-glimpse.md (M2) | plasmoid com.zinoxx.glimpse | done, integrated | Glimpse v2 commit |
| C apps | agents/C-apps.md (M4) then agents/C-boot.md (M5), both done | rice.py ansi/konsole/apply_konsole/alacritty/apply_kwin, apps.py, templates/, konsole/dolphin/darkly/klassy/kwinrc effects+blur, fastfetch, ~/.local/share/kwin/effects | done, integrated | M4 3d187d8, M5 4e26020 |
**2026-10-16 user rule: from now on the orchestrator works ALONE; at most ONE extra agent, and only if truly
needed** (4 concurrent sessions were too heavy for the machine). All agents: rules in agents/COMMON.md. Orchestrator meanwhile: bars (panel/build.py: same layout on every screen,
stray appletsrc group, Panel 2, island padding from tokens, clock px), M0 check-in.

## Log
- 2026-10-15 00:10 all three agents hit the usage limit while still reading (no edits); resumed 02:31 via SendMessage.
- 2026-10-15 ~05:00 all three agents hit the usage limit again mid-work (uncommitted edits in plasma-rice and
  plasmoids repos: A = plasma-style, Rice components, 4 widgets; B = Glimpse split into new files; C = rice.py
  konsole/kwin parts, apps.py, kwin/ effects). Resumed 08:37 via SendMessage (agents keep their context).
- 2026-10-15 agent C hit the WEEKLY limit (reset 2026-10-16 02:00); resumed 02:01. Usage is tight: be economical.
- 2026-10-16 02:02 M1 integrated: neutral popup fill chosen (taste call, NEUTRAL #12131a). Restarted plasmashell
  while all displays were DPMS-off -> panels on screen -1; background watcher (scratchpad/wake-watch.sh) restarts
  plasmashell on wake if they stay at -1. If resuming in a new session: check `panels()` screens first.
- 2026-10-15 M0 check-in acknowledged (Done) with no reply on animation speed: keeping the system 0.5x.

## Decisions
- 2026-10-14 Top band: keep idle strip + function. Opened band: no clock; media module floating right;
  one icon per app, hover shows live thumbnails per window, clicking a thumbnail = normal click action.
- 2026-10-14 Window/popup motion: smooth and subtle (fade + small scale/slide, no overshoot).
- 2026-10-14 Check-ins: "!" over Clawd at each milestone + anything needing reboot/relogin.
- 2026-10-16 User picks: band icons stay LEFT; icons Tela-circle-dracula-dark (settings icon_theme, greeter too);
  cursor stays Simp1e-Tokyo-Night; animation speed stays 0.5x (no objection).
- 2026-10-16 Agents: orchestrator alone from now on; at most 1 extra agent if absolutely needed (4 was too heavy).
- 2026-10-14 Keep Konsole (no new terminal), keep Plasma notifications/OSD/KRunner (style via Plasma Style).

## Rules (every agent)
- Orchestrator: while agents run, commit explicit paths only (never `git add -A`: it would sweep up their work).
- No smooth looping animation in PANEL representations (GPU: plasmashell+KWin redraw at 144-160 Hz).
  Stepped frames (a few repaints every few s) OK. Popups / the opened band may animate while open.
- Motion: enter OutCubic/OutQuart, exit InCubic, 120/200/320 ms; no elastic/OutBack overshoot > ~1.05.
- Colour: per-screen `~/.local/state/rice/palette-<output>.json`; shared chrome (Plasma Style frames) neutral.
- Only the orchestrator restarts plasmashell/KWin, edits rice.py, palette.py, panel/build.py,
  settings.json, the shared QML module, and commits. Agents test offscreen and hand back.
- Memory gotchas in ~/.claude/CLAUDE.md (never unload Krohnkite, Colorizer D-Bus limits, etc.).

## Backups
- git baseline commits ("Baseline before the polish pass") in the three repos.
- `~/.cache/rice/backup-pre-polish-2026-10-14.tar.zst` (~/.config KDE bits, plasma, konsole, kwin, icons, rice state).
- snapper pre/post around system-level changes.

## Tools
- `tools/shots.py <set> [part ...]` screenshot set + perf into ~/.cache/rice/shots/<set>/ (parts: screens popups
  band apps notify osd lock perf; `popups:launcher,clock` for some). Takes over the desktop ~1 min.
- `tools/pointer.py move|click X Y` uinput pointer (moves the user's real cursor).
- Baseline perf (video playing): gpu 15.9 W avg, plasmashell 4.7% CPU, kwin 24.1% CPU.

## Open TODOs / known issues
- New shutdown-only warning since the new style: PlasmoidHeading "Binding loop detected for property leftInset"
  (stock applets, harmless; maybe dialog margins 10 -> 8).
- Notification timeout line stays accent-orange (compiled QML; can't reach from Plasma Style).
- Glimpse: real blur behind the band needs a tiny compiled QML plugin wrapping KWindowEffects::enableBlurBehind
  (not possible from QML); today it's the pre-blurred wallpaper. Candidate for M6.
- M4 taste calls pending with the user: icons Papirus-Rice (now) vs Tela-circle dracula/purple/nord; cursor Simp1e (now) vs
  Bibata Classic/Ice/Amber (shots/agent-c/icons-cursors-comparison.png); fastfetch logo wallpaper (now) vs Clawd; shadow tint
  0.18; diminactive off. Installed but unused: tela-circle-icon-theme-{dracula,purple,nord}, bibata-cursor-theme-bin.
- Live check still owed for M4 (agent C used a headless KWin sandbox): `tools/shots.py m4 apps` when the user is around.
- Glimpse taste calls pending with the user: icons left (current) vs centred (taste-left/center.png in shots/agent-b),
  paused media stays visible (current), stack style = fanned icon copies + count (current).
- Glimpse untested live: "recent" and "screen" order modes.
- Plasma popups aren't visible to KWin scripts (stackingOrder), so shots.py opens/closes popups by timing.
- Clock + tray have no global shortcut; shots.py clicks them (positions from plasmashell scripting).

## M6 progress (2026-10-16, orchestrator)
- Bars normalized (plasmashell stopped): DP-3 bar order clock -> show desktop like the laptop bar, spacers 10 -> 8,
  laptop bar got a trailing 8 px spacer (new widget 170) like the main bar; stray appletsrc group
  [Containments96Appletsts] and plasmashellrc [PlasmaViews][Panel 2] removed. Backups: ~/.cache/rice/appletsrc.pre-bars,
  plasmashellrc.pre-bars. TODO after wake: re-push island styles (`python3 -c "import json,rice;
  rice.apply_screens(rice.screens(), rice.settings(), json.loads((rice.STATE/'palette.json').read_text()))"` in
  ~/.config/plasma-rice) so the per-island gradient follows the new DP-3 order; check all 3 bars in a screenshot.
- Token sweep done 2026-10-16 07:05: Emblem + MediaModule durations now Tokens-scaled; remaining hex literals are
  intentional (white/black alpha chrome, bezel, Emblem defaults overridden by the palette); session power icon keeps a
  0.8 OutBack (within the rule); popup-only skeleton loops are fine. IconButton gained `filled` (FILL axis, native text).

## Rollback notes
- Boot: /boot/limine.conf.pre-m5 is the pre-M5 config (cp back + `sudo limine-mkinitcpio`). Plymouth fallback:
  `sudo plymouth-set-default-theme cachyos && sudo limine-mkinitcpio`. Logout screen: kdeglobals
  LookAndFeelPackage=org.kde.breezedark.desktop.

## Next step
(2026-10-16) After the reboot into Plasma 6.8: `plasmashell --version`/`kwin_wayland --version` = 6.8; journal for KWin effect load errors
(better_blur_dx, kwin4_effect_shapecorners_rice, rice_window/rice_popups JS) and plasmashell QML errors; Colorizer services
c23/c90/c96 present and islands styled; Glimpse band (edge open, glass, per-screen icon states); launcher, logout,
lock, Klassy titlebars + per-screen borders, Darkly apps, Krohnkite started once. If an effect fails: rebuild it
(paru clone dir or pkg/ dir: makepkg -sfci). Rollback: snapper 104/105 (pre-6.8).

## Pass 2: dynamic + harmonized (started 2026-10-16 15:40, orchestrator alone; user away, free hand)
User asked (15:30): UI "not dynamic enough"; launcher hero must follow the wallpaper with a manual choice; better
accents across the UI; the top band's glow line should follow the wallpaper. Answers: accents HARMONIZED; hero gets a
small pencil in its top corner -> "Pick from wallpapers", "Adjust manually" (pan/zoom the current image), "Browse
image"; move the wallpaper picker INSIDE the launcher (minimalism, user's "perhaps", my call: do it); scope = all.
Root cause found first (fixed b18d6e5): widgets never re-read palettes on Plasma 6.8 (RicePalette now watches the file).
TODO (tick as done, commit each):
- [x] A1 colour transitions: RicePalette role colours glide ~400 ms on change (not on first load)
- [x] A2 band glow line sampled from the wallpaper's top edge (rice.py `_rim` stops) + slow light drift while open
- [x] A3 launcher hero: pencil menu (pick from wallpapers / adjust pan+zoom / browse / follow wallpaper), per screen
- [x] B1 harmonized semantics: RicePalette ok/warn/bad = status hues blended toward primary; rings use primary->tertiary
- [x] B2 session popup: neutral tiles, accent on hover, warm glow for restart/shutdown, wallpaper strip header
- [x] B3 popups: faint accent aurora at the top of every popup (PopupIn), from the screen palette
- [x] C1 launcher grid uses all 6 columns (now 3 used, right half empty); C2 category chips scroll with edge fades;
      C3 pinned tiles tinted by app colour with the band's glow
- [x] D1 sysstats: CPU/RAM/GPU history tabs with gradient fills + top 3 processes
- [x] W1 wallpaper picker inside the launcher (a Wallpapers view; Meta+Shift+W opens it; wheel on the Orbit emblem
      steps this screen's wallpaper); remove the wallpicker widget from the bars (keep the plasmoid for rollback)
- [x] E1 presets red/blue/green/pastel/dark: screenshot every surface on each; fix what looks off
Progress (17:20): A1-D1 and W1 done and committed (8ed7e7e, 4383a39, 36beded, f23169a, d398e90). Found on the way:
Plasma 6.8 stopped passing scheme switches to widgets (b18d6e5); `Behavior on onPrimary` and a `palette` property
crash plasmashell; GridView with a width-bound cellWidth + centring leftMargin counted 3 of 6 columns. Next: E1.
Done (17:30): E1 on blue / pale green / near-white / near-black / orange wallpapers (shots/e1-*): bars, band, popups and
launcher all follow each palette and stay readable; restored the user's look (preset "spy"). Idle: 12.1 W, plasmashell
2.4 %, KWin 12.4 % (shots/pass2/perf.txt). Known trade-off: on light wallpapers the band's lower glass reads grey-brown
(it stays a dark bezel by design).

## Pass 3: character-driven colours + Theme page (approved 2026-10-16 ~17:50)
Plan: ~/.claude/plans/stateless-sauteeing-map.md. Decisions: white wallpaper -> LIGHT frosted UI (dark text, silver
accents, terminals stay dark); black -> VOID + starlight; manual colours are temporary unless saved as a theme
(presets become themes); bias modern/neon, pastel only for calm wallpapers (pastel surfaces: my call).
Phases: 1 engine + offline palette sheet (check-in) / 2 dark moods live / 3 light mode / 4 overrides + Themes +
Theme page / 5 sweep + tests.
- [x] P1 engine (palette.py analyse/mood/build_v2) + tools/palette_sheet.py (sheet: ~/.cache/rice/shots/pass3/sheet.png; user: "looks awesome")
- [x] P2 dark moods live (8ce8196): rice.py palette_for = build_v2; RicePalette exposes mood/light/glow/edge, status from
      the palette, harmony 0.10; glows (Aurora, Glimpse haze/tiles, launcher pins) scale with `_glow`. Spy = neon blood red.
- [x] P3 light mode (2b9eaad): Plasma Style variants Rice / Rice-Light (build.py, dark byte-identical), rice.py apply_style
      follows the theme-driving screen; dark_twin palette for terminals/VS Code/Zen/btop/prompt; light KDE scheme inks;
      Colorizer white-frost islands + fg override on stock islands (tray, clock); PopupIn repaints a popup with its
      screen's surface when it differs from the global chrome; Glimpse drawer frosts (bezel strip stays black); rim
      graphite on light; RicePalette deepens status hues on light; Zen pinned dark (ui.systemUsesDarkTheme).
      Tested live: mixed (laptop white, others spy), HDMI white + theme spy, all white (shots p3-mix-pops, p3-light-pops).
- [x] P4 overrides + themes + Theme page (b66b354 + launcher): overrides.json per output, `rice.py theme show|set|reset`,
      theme-screen file = the screen driving the theme; presets save/load overrides + lead (a preset is a theme). Launcher:
      WallpaperPane is the "Theme" page with Wallpapers | Colours tabs (ColoursTab.qml: mood chips, 3 accent cards, wallpaper
      swatches, H/S/L sliders + hex, intensity, preview island, Discard/Automatic + Apply); wording preset -> theme.
- [ ] P5 sweep: user check of the Colours tab; idle 11.5 W GPU / plasmashell 3.1 % / KWin 3.3 % (with audio playing).
Gotchas: Colorizer's fg override sets `color` on every Text/Icon of an island (would flatten our accent text, so only
stock islands get it); `palette.edge` inside a FocusRing resolves to FocusRing's own Item.palette (qualify with the
root id); a light KDE scheme makes the portal report light (Zen/web would follow: pinned dark).
