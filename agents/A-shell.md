# Agent A: shell surfaces (milestone 1)

Read `agents/COMMON.md` first. You own the Plasma Style and the small bar widgets' popups.

## You own
- `~/.config/plasma-rice/plasma-style/build.py` (generates ~/.local/share/plasma/desktoptheme/Rice; run it, then
  delete ~/.cache/plasma_theme_Rice*.kcache and restart plasmashell to see changes).
- Plasmoids `com.zinoxx.{session,sysstats,claudeusage,wallpicker}` (everything under them).
- `qml/Rice/Clawd.qml`, `qml/Rice/Ring.qml`, and NEW files you add to `qml/Rice/` (tell the orchestrator so it adds
  them to qmldir; you may add the qmldir line yourself for new files only).
Not yours: Glimpse, the launcher (milestone 3, later), rice.py, panel/build.py, tokens.py, RicePalette/Tokens/Color.js.

## Tasks
1. Plasma Style "Rice" (`plasma-style/build.py`):
   - Make shared chrome neutral: dialogs/background, widgets/tooltip, widgets/viewitem (and any other frame using
     ColorScheme-Highlight for outlines/washes) must stop using the global accent (it comes from one screen's
     wallpaper and clashes with the other screens' palettes). Use white/black alpha outlines and washes, like
     widgets/tabbar already does. Selection/hover in viewitem: a neutral light wash is fine.
   - Radii from tokens (`import tokens` from the parent dir): dialogs lg 18, tooltips sm 10, viewitems sm 10,
     panel-background md 14. mask-* elements at exactly the frame's radius (blur must not bleed past corners).
   - Add the elements that still fall back to Breeze: widgets/bar_meter_horizontal (+ _vertical), widgets/button
     (normal/hover/pressed/focus + toolbutton variants per the Plasma theme spec), widgets/lineedit (base/focus/hover),
     widgets/slider, widgets/scrollbar, widgets/checkmarks, widgets/radiobutton, widgets/switch if Plasma 6 uses it.
     Use https://develop.kde.org/docs/plasma/theme/theme-details/ and Breeze's SVGs in
     /usr/share/plasma/desktoptheme/default/ as the reference for element ids and hints. Look: rounded, flat,
     hairline outlines, subtle washes; progress/meters can use ColorScheme-Highlight for the FILL only if you judge
     it reads fine on every screen, otherwise neutral-bright.
   - Verify: notification (`notify-send`), OSD (`qdbus6 org.kde.plasmashell /org/kde/osdService
     org.kde.osdService.mediaPlayerVolumeChanged 60 Test audio-volume-medium`), KRunner
     (`qdbus6 org.kde.krunner /App org.kde.krunner.App.display`, close with Escape is not possible for you, so
     use `qdbus6 org.kde.krunner /App org.kde.krunner.App.toggleDisplay`), tooltips. Screenshot each.
2. Migrate session, sysstats, claudeusage, wallpicker to the shared module: `RicePalette` instead of each widget's own
   palette DataSource + col(); `Tokens` for radii/spacing/type/durations; `C.alpha`; delete the local Ring.qml /
   Clawd.qml copies (claudeusage, sysstats) and use the Rice ones. Keep every behaviour (ask.sh "!" check-in banner and
   badge in claudeusage included; the Clawd moods; alerts.py; sysstats sensors; session confirmations; wallpicker
   tags/wallhaven/screens).
3. Popup polish, same structure in all four: PopupIn entrance (replaces each ad-hoc pop animation), one header
   style, consistent paddings (popup content margin Tokens.space.lg, card radius md inside the lg dialog), Rice
   IconButton/tooltips instead of the stock `PlasmaComponents.ToolButton` (sysstats "System Monitor") and
   `QQC2.ToolTip`. Every interactive element gets hover, pressed and keyboard-focus states. Avoid layout-animating
   properties (e.g. animating font.pixelSize: scale instead).
4. Panel (compact) representations: wallpicker's spinner becomes stepped (no smooth infinite rotation);
   claudeusage panel rings `instant: true` (like sysstats). No new loops.
5. Wallpicker: don't rebuild the grid on every open (update the model in place / keep thumbnails), add loading and
   empty states, no "0 wallpapers" flash, fix hard-coded colours (TagField selectedTextColor), radii from tokens.
6. Display name: one name everywhere = the first word of the account's full name (GECOS, `getent passwd $USER`),
   falling back to the username. Apply in session (avatar initial + name). Note in your report how the launcher and
   the splash should read it (they're done later).
7. `qml/Rice/Clawd.qml`: snap `px` to whole device pixels (`Math.max(1, Math.round(px * Screen.devicePixelRatio)) /
   Screen.devicePixelRatio`) so the pixel art stays crisp on the 1.25/1.7 scaled screens; same idea for the popup Clawd.

## Done means
Lint clean; a live restart shows no new QML errors in the journal; before/after screenshots of each popup, the
notification, OSD, KRunner and a tooltip in `~/.cache/rice/shots/agent-a/`; idle bar still static (no panel
loops). Report per COMMON.md.
