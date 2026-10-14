# Agent B: Glimpse opened band v2 (milestone 2)

Read `agents/COMMON.md` first. You own the Glimpse plasmoid: `~/.local/share/plasma/plasmoids/com.zinoxx.glimpse/`
(main.qml 1226 lines, Notch.qml, ScreenTasks.qml, ConfigGeneral.qml, config/main.xml, code/glimpse-kwin.sh).
Split main.qml into focused files as you go (e.g. IconTile.qml, ThumbStrip.qml, MediaModule.qml, BarLaunchers.qml).
You may use the uinput pointer (tools/pointer.py) and restart plasmashell for live tests.

## What Glimpse is (keep all of it)
A task manager in two places: pinned launchers on every bottom bar, and a full-width "notch/bezel" band at the
top of every screen (one plasmoid instance per screen owns that screen's layer-shell windows). Read the
`Glimpse` and `Plasma/Wayland gotchas from Glimpse` lines in ~/.claude/CLAUDE.md. Key behaviour that must survive:
- The thin idle strip (7 px with tinted pills, the focused pill's glow leaking under the lip, faint accent rim):
  the user LOVES it ("very sci-fi, modern, dark and tech-y"). Keep its look; only fix pixel crispness at scale 1.0.
- Hover the strip (hoverDelay 120 ms) -> the band opens; leaving it closes it at once; fullscreen edge with dwell.
- Click rules: minimized -> restore here; on another screen -> slide here (code/glimpse-kwin.sh); here + focused ->
  minimize; here -> focus. Middle-click = new instance. Right-click menu. Meta+1..9 = activateTaskAtIndex.
- Order "alpha" by default: ONE list by app name, identical on every screen, stable for muscle memory.
- Magic lamp minimizes into the pills (requestPublishDelegateGeometry). Exclusive zone of the strip.

## What the user wants changed (their words, 2026-10-14)
"Something I don't love is the look of it when the cursor hovers it: the app icons look small and the bar is
overly simple." Keep the idle version. Changes must keep the same design language as the rest of the system.
- NO clock in the band (the bottom bars already have one).
- Media with controls, floating on the RIGHT side of the opened band.
- Hovering an app icon shows live thumbnails. Multiple windows of the same app are STACKED on ONE icon
  ("3 VS Codes -> hover -> 3 thumbnails appear underneath, clicking one of those thumbnails has the normal
  functionality" = the click rules above, applied to that window).
- The opened band itself stays about 44 px tall (an earlier request: bigger icons, NOT a taller band).
  Thumbnails drop below the band; they don't make the band taller.
- Window/popup motion everywhere: smooth and subtle (OutQuart/OutCubic fades and small rises/scales, no
  elastic). Today the band uses OutBack 2.4 + elastic pops: tone that down.

## Tasks
1. One icon per app: group windows by app (TasksModel groupMode GroupApplications, or group the existing flat
   model by app id yourself; keep alphabetical order). An app with several windows shows a stack (offset card
   edges / layered silhouettes behind the icon) and a small count. Keep the indicators (focused bar, here dot,
   minimized ring) and make the other-screen tag readable (>= 10 px, short label). Clicking the icon acts on the
   app's most recent window with the normal rules. Meta+N semantics: per app now; document it.
2. Thumbnails: hovering an icon opens a strip of live window thumbnails under the band, aligned to the icon
   (one per window of that app). Use `TaskManager.ScreencastingRequest` + `PipeWire.PipeWireSourceItem`
   (`import org.kde.pipewire as PipeWire`, `import org.kde.taskmanager as TaskManager`) like the stock task
   manager's tooltip (see /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/ui/ToolTipWindowMouseArea.qml
   / ToolTipInstance.qml, or the compiled plugin if the QML isn't on disk). Each thumbnail: title, screen tag,
   minimized state, close button. Click = normal click rules for that window; middle-click = close. Stream only
   while visible. The strip lives in the opened band's layer-shell window (grow it downward while thumbnails show;
   keep input regions tight; close when the pointer leaves band + strip).
3. Media module on the right: MPRIS (`org.kde.plasma.private.mpris` Mpris2Model, as used by
   /usr/share/plasma/plasmoids/org.kde.plasma.mediacontroller if present): album art, title/artist, prev/play/next,
   a thin progress line. Hidden when nothing plays. Optional tiny level meter ONLY while the band is open and
   playing (needs `cava`; install with `sudo pacman -S --needed cava` if you use it; otherwise skip).
4. Look, same design language: everything scales with topScale (pal.topScale; currently 1.2) except the band height;
   bigger icon slots and a proper hover lens; the label tab merges into the lower edge (the glowing edge line
   follows the tab instead of cutting across it, Notch.qml); tab text = app name only; fallbacks from Tokens
   (RicePalette); idle band hidden only once the opened band is actually on screen (no flicker).
5. Real blur behind the opened band if feasible (KWindowEffects / Better Blur DX treats layer-shell docks;
   investigate), otherwise keep the pre-blurred wallpaper backdrop with a lighter tint.
6. Bottom-bar launchers part: the "launching" pulse loops in the PANEL: make it stepped. Radii from tokens.
7. Use the shared module (RicePalette, Tokens, Color.js appTint) instead of Glimpse's own palette loader/appTint.

## Done means
Lint clean; live: open band on each screen, hover icons with 1 and 3 windows of an app (open 3 konsole windows to
test, close them after), thumbnails show and clicks do the right thing, media module with something playing
(the user often has YouTube in Zen) and without, fullscreen edge still works, magic lamp still lands in the pills,
idle strip unchanged. Screenshots in `~/.cache/rice/shots/agent-b/`. Park the cursor mid-screen after pointer tests.
Report per COMMON.md.
