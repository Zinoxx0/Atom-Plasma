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
| 0.5 | Plasma 6.8 upgrade (own step when it lands) | orchestrator | waiting (not in repos 2026-10-14) |
| 1 | Shell surfaces (Plasma Style, bars, popups) | agent A | running |
| 2 | Glimpse opened band v2 | agent B | running |
| 3 | Launcher, logout, lock | agent A | todo |
| 4 | Konsole, Dolphin, decorations, KWin motion | agent C | running |
| 5 | Boot chain (Limine, Plymouth, login, splash) | agent C + orchestrator | todo |
| 6 | Consistency sweep, perf, memory | orchestrator | todo |

## Agents
| Agent | Brief | Owns | State | Last commit |
|-------|-------|------|-------|-------------|
| A shell | agents/A-shell.md (M1) | plasma-style/build.py, plasmoids session/sysstats/claudeusage/wallpicker, qml/Rice/{Clawd,Ring}.qml + new Rice files | running (launched 2026-10-15) | - |
| B glimpse | agents/B-glimpse.md (M2) | plasmoid com.zinoxx.glimpse | running (launched 2026-10-15) | - |
| C apps | agents/C-apps.md (M4) | rice.py ansi/konsole/apply_konsole/alacritty/apply_kwin, apps.py, templates/, konsole/dolphin/darkly/klassy/kwinrc effects+blur, fastfetch, ~/.local/share/kwin/effects | running (launched 2026-10-15) | - |
All agents: rules in agents/COMMON.md. Orchestrator meanwhile: bars (panel/build.py: same layout on every screen,
stray appletsrc group, Panel 2, island padding from tokens, clock px), M0 check-in.

## Log
- 2026-10-15 00:10 all three agents hit the usage limit while still reading (no edits); resumed 02:31 via SendMessage.
- 2026-10-15 M0 check-in acknowledged (Done) with no reply on animation speed: keeping the system 0.5x.

## Decisions
- 2026-10-14 Top band: keep idle strip + function. Opened band: no clock; media module floating right;
  one icon per app, hover shows live thumbnails per window, clicking a thumbnail = normal click action.
- 2026-10-14 Window/popup motion: smooth and subtle (fade + small scale/slide, no overshoot).
- 2026-10-14 Check-ins: "!" over Clawd at each milestone + anything needing reboot/relogin.
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
- Plasma popups aren't visible to KWin scripts (stackingOrder), so shots.py opens/closes popups by timing.
- Clock + tray have no global shortcut; shots.py clicks them (positions from plasmashell scripting).

## Next step
Briefs ready for later: agents/A-launcher.md (M3, send to agent A after M1 is integrated),
agents/C-boot.md (M5, send to agent C after M4 is integrated). Wait for agent reports; review each `git diff` (plasmoids repo for A/B, plasma-rice repo for A/C), integrate live,
screenshot, commit. Meanwhile: bars cleanup (orchestrator). M0 check-in raised (baseline + token sheet).
