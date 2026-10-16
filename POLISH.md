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
