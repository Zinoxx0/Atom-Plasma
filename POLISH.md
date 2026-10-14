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
| 0.1 | "!" attention over Clawd | orchestrator | in progress |
| 0.2 | Safety net (git x3, backup tarball) | orchestrator | done 2026-10-14 |
| 0.3 | Baseline screenshots + perf | orchestrator | todo |
| 0.4 | Design tokens + shared QML module | orchestrator | todo |
| 0.5 | Plasma 6.8 upgrade (own step when it lands) | orchestrator | waiting (not in repos 2026-10-14) |
| 1 | Shell surfaces (Plasma Style, bars, popups) | agent A | todo |
| 2 | Glimpse opened band v2 | agent B | todo |
| 3 | Launcher, logout, lock | agent A | todo |
| 4 | Konsole, Dolphin, decorations, KWin motion | agent C | todo |
| 5 | Boot chain (Limine, Plymouth, login, splash) | agent C + orchestrator | todo |
| 6 | Consistency sweep, perf, memory | orchestrator | todo |

## Agents
| Agent | Brief | Owns | State | Last commit |
|-------|-------|------|-------|-------------|
| (none running) | | | | |

## Decisions
- 2026-10-14 Top band: keep idle strip + function. Opened band: no clock; media module floating right;
  one icon per app, hover shows live thumbnails per window, clicking a thumbnail = normal click action.
- 2026-10-14 Window/popup motion: smooth and subtle (fade + small scale/slide, no overshoot).
- 2026-10-14 Check-ins: "!" over Clawd at each milestone + anything needing reboot/relogin.
- 2026-10-14 Keep Konsole (no new terminal), keep Plasma notifications/OSD/KRunner (style via Plasma Style).

## Rules (every agent)
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

## Open TODOs / known issues
- (none yet)

## Next step
Build 0.1: ask.sh + claudeusage "!" (attention status, banner, Done button), verify on bars 23 and 96.
