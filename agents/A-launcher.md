# Agent A, part 2: launcher, logout, lock (milestone 3)

Same rules as before (agents/COMMON.md). Build on what you did in milestone 1 (shared Rice components, neutral
Plasma Style).

## You own
- Plasmoid `com.zinoxx.launcher` (main.qml 902 lines, Emblem.qml).
- Look-and-Feel `~/.local/share/plasma/look-and-feel/com.zinoxx.rice/` EXCEPT `contents/splash/` (agent C, M5):
  you add `contents/logout/` (and, if the lock-screen route below works, the lock screen bits).
- New files in `qml/Rice/` as before (tell the orchestrator).

## Tasks
1. Launcher polish (keep every feature: hero card with wallpaper/clock/greeting/session buttons, search via KRunner
   grouped by kind, pinned tiles tinted by app colour, category chips, app grid, keyboard nav, right-click pin/unpin +
   jump-list actions, drag to Glimpse to pin, Meta / Alt+F1 via org.kde.plasma.launchermenu):
   - search results cross-fade in (Tokens motion) with a "searching" state while KRunner works; empty state.
   - grid centred (no leftover gap on the right); pinned row scrolls with edge fades when it overflows.
   - nested radii from tokens (cards inside the lg dialog = md; hero = lg minus its inset), consistent headers
     (SectionHeader), Rice tooltips, keyboard focus rings on chips, pins, session buttons.
   - same popup size on every screen (scaled by uiScale); today the saved sizes differ (758x632 vs 880x581).
   - the display name from the account (as in milestone 1), greeting by time of day.
   - Restart/Shut down must go through the same confirmation as the session widget (see 2).
2. Logout screen, wlogout-like but in this design language: Look-and-Feel `contents/logout/Logout.qml`
   (the logout greeter loads `logoutmainscript`; check /usr/lib/ksmserver-logout-greeter and the Breeze lnf
   at /usr/share/plasma/look-and-feel/org.kde.breeze.desktop/contents/logout/ for the API it expects: actions,
   countdown, signals). Blurred wallpaper of each screen behind, big rounded action tiles (lock, sleep, log out,
   restart, shut down) with icons, the name, a countdown, keyboard navigation, subtle entrance. Then make the session
   widget and the launcher call `org.kde.LogoutPrompt` (promptLogout/promptReboot/promptShutDown) so every
   confirmation looks the same. CAREFUL when testing: the logout greeter auto-confirms after its countdown. Test by
   running the QML in a harness offscreen, and if you must run the real greeter, make sure you can cancel it
   immediately (it must never log the user out). Prefer offscreen.
3. Lock screen. Facts so far: the greeter (/usr/lib/kscreenlocker_greet) loads `lockscreen/LockScreen.qml` from the
   Plasma *shell* package (KPackage "Plasma/Shell", with a fallbackPackage), reads a `ShellPackage` setting, and has
   `--testing --shell <pkg>` for previews. plasmashell itself also uses `[Shell] ShellPackage` in plasmashellrc, so
   pointing that at a minimal package could break the desktop. Investigate safely (--testing only) whether a
   minimal shell package with only `contents/lockscreen/` + fallback to org.kde.plasma.desktop can be used by the
   greeter WITHOUT changing what plasmashell loads. Only if it's clean and survives a plasma-desktop update, build a
   lock screen in this design language (clock, date, greeting, password pill, media controls, per-screen wallpaper
   blurred). Otherwise do the supported route (Plasma Style already themes it; kscreenlockerrc: media controls on,
   wallpaper plugin with blur if available) and say so. Never leave the real lock screen broken: verify with
   --testing, and never activate the real locker.

## Done means
Launcher screenshots (browse, search with results, searching state, keyboard focus), logout screen render, lock
screen route decision + render, in ~/.cache/rice/shots/agent-a/. Report per COMMON.md.
