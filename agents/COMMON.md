# Common brief for every polish-pass agent (read fully before starting)

You are one of up to three agents working in parallel on a KDE Plasma 6.7 (Wayland, Qt 6.12, CachyOS) rice,
orchestrated by another Claude instance that reviews and integrates your work. The user is zinoxx (they/them).
Read these first: `~/.claude/CLAUDE.md` (system facts + hard-won gotchas), `~/.config/plasma-rice/POLISH.md`
(live project state), the plan `~/.claude/plans/stateless-sauteeing-map.md` (your milestone section).

## The goal and the look
HyDE-level polish without Hyprland: clean, modern, very detailed and animated, tech-y without being cold or
cyberpunk. The rice already has personality; what it lacks is edge refinement: consistent radii, spacing,
type, motion, states (hover/press/focus/loading/empty), and colours that never clash.

## Design system (use it, don't invent values)
- Tokens: `~/.config/plasma-rice/tokens.py` (single source) -> generated `qml/Rice/Tokens.qml` singleton.
  Radius xs 6 / sm 10 / md 14 (bar islands = windows) / lg 18 (popups) / xl 24; nested corners = outer - padding.
  Space 2/4/8/12/16/24/32. Fonts: Inter (ui), Inter Display (display), JetBrainsMono Nerd Font (mono),
  Material Symbols Rounded (icons). Sizes px: caption 10, small 11, label 12, body 13, title 15, heading 18,
  display 24, hero 32 (bar widgets multiply by the palette's uiScale). Alpha levels in Tokens.alpha.
- Motion: Tokens.fast/base/slow (150/250/400 ms at normal speed, already scaled by the system animation speed,
  currently 0.5x -> 75/125/200), Tokens.enter = OutCubic, Tokens.exit = InCubic, Tokens.move = InOutCubic.
  The user chose "smooth and subtle": fades, small slides/scales, no elastic, no OutBack overshoot > ~1.05.
  Well-damped springs for hover feedback are fine.
- Colour: each screen has its own wallpaper palette. In QML use the shared loader:
  `RicePalette { id: pal; output: Screen.name }` -> pal.primary, pal.fg, pal.surfaceHigh, pal.col("teal"),
  pal.uiScale, pal.topScale, pal.values (raw JSON incl. _wallpaper, _glass...). Helpers:
  `import "Rice/Color.js" as C` -> C.alpha(c, a), C.mix(a, b, t), C.appTint(imageColors, fallback).
  Shared chrome (Plasma Style frames) is NEUTRAL (white-alpha outlines/washes) so it never clashes with a screen.
- Shared module `~/.config/plasma-rice/qml/Rice/` is symlinked into every plasmoid as `contents/ui/Rice`:
  `import "Rice"` gives Tokens, RicePalette, Ring, Clawd, GlassCard, IconButton, SectionHeader, PopupIn.
  Read the files: they're short and documented. A token sheet render is at ~/.cache/rice/shots/baseline/tokens.png
  (renderer: ~/.config/plasma-rice/tools/sheet/TokenSheet.qml).

## Hard rules
- PERFORMANCE: no smooth looping animation in a panel (compact) representation: plasmashell + KWin then redraw
  at 144-160 Hz on the NVIDIA (measured ~27 W vs ~8 W). Stepped frames driven by Timers (a few property changes
  every few seconds) are fine. Popups and the opened Glimpse band may animate while open; stop when closed.
  Never feed a Repeater a JS array that is recomputed on every update (use a fixed model + index lookups).
- Ownership: only edit the files your brief gives you. The orchestrator owns rice.py (except functions your brief
  hands you), palette.py, panel/build.py, settings.json, tokens.py, qml/Rice/{Tokens,RicePalette,qmldir}.qml,
  Color.js. Need a change there? Put the exact diff in your report.
- Don't commit (the orchestrator reviews `git diff` and commits). Don't run `ask.sh` (the orchestrator talks
  to the user). Don't ask the user anything; when a taste call has no clear winner, render the options and
  put them in your report.
- Plasmashell: `systemctl --user restart plasma-plasmashell` is allowed only for agents A and B, only when
  everything you changed lints clean, and not more than needed. KWin is never restarted. NEVER unload/reload
  the Krohnkite KWin script (memory explains why).
- The uinput pointer (`~/.config/plasma-rice/tools/pointer.py`) moves the user's real cursor: only agent B uses
  it, briefly, and parks the cursor mid-screen afterwards.
- Match the surrounding code: comment density, naming, idiom. Comments say why, not what.

## Testing
- Lint: `/usr/lib/qt6/bin/qmllint <file.qml>` (warnings about unqualified access in plasmoids are normal;
  errors are not).
- Offscreen render (great for visuals): a tiny Window QML importing your component, then
  `QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=org.kde.desktop qml6 file.qml`
  with a Timer that does `contentItem.grabToImage(r => { r.saveToFile(path); Qt.quit() })`. Plasma5Support works
  offscreen (RicePalette loads real palettes). console.* output is NOT shown by qml6 here: encode values in the
  render or in `Qt.exit(code)`.
- Live: after a plasmashell restart wait ~8 s, then `journalctl --user -u plasma-plasmashell --since -1min`
  for QML errors. Screenshots: `spectacle -b -n -f -o file.png` = whole desktop at 2x; crop per output with
  geometry from `python3 -c "import sys; sys.path.insert(0,'$HOME/.config/plasma-rice/tools'); import pointer; print(pointer.outputs())"`
  (logical coords; multiply by 2). Screens: HDMI-A-1 (main, panel 23), eDP-1 (laptop, panel 90), DP-3 (4K, panel 96).
  Open an applet popup: `qdbus6 org.kde.kglobalaccel /component/plasmashell org.kde.kglobalaccel.Component.invokeShortcut "activate widget <id>"`
  (ids: launcher "activate application launcher", wallpicker 129, claude 102, sysstats 106, session 107; the same
  call closes it). Save your screenshots under `~/.cache/rice/shots/<your-agent>/`.
- The user is using this computer while you work: keep live tests short, close what you open.

## Report back (your final message)
1. What you changed and why (short), 2. files touched, 3. how you verified it (screenshot paths, lint output),
4. anything unfinished or uncertain, 5. proposed diffs for files you don't own, 6. taste options needing a decision.
