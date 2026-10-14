# Agent C, part 2: the startup chain (milestone 5)

Same rules (agents/COMMON.md). Goal: from power-on to desktop, every stage looks like one product in this design
language, and hands off smoothly to the next: Limine menu -> Plymouth (LUKS? check) -> Plasma Login Manager greeter
(only when not auto-logged in; it's NOT autologin here) -> Plasma splash -> desktop.

## You own
- `~/.config/plasma-rice/boot.py` (limine | plymouth | login | preview) and the Plymouth theme it builds
  (/usr/share/plymouth/themes/rice), `/etc/plasmalogin.conf` [Greeter] keys, `/var/lib/plasmalogin/.config/*`.
- Splash: `~/.local/share/plasma/look-and-feel/com.zinoxx.rice/contents/splash/` (Splash.qml + its old Clawd copy:
  switch to the shared Rice Clawd via the `Rice` symlink already there).
Not yours: plasmoids, the logout screen (agent A).

## Hard rules (boot is where mistakes hurt)
- Read the boot lines in ~/.claude/CLAUDE.md: /boot/limine.conf pins blake2b hashes; ONLY rebuild through
  `limine-mkinitcpio` (it self-elevates and updates hashes). Never hand-edit kernel/initramfs entries. Keep a copy of
  /boot/limine.conf before any change. ESP is 4 GB, each initramfs ~258 MB.
- snapper: snap-pac covers pacman; for /etc and /boot edits take `sudo snapper -c root create -t pre ...` /
  `-t post` pairs yourself.
- Never reboot. The orchestrator asks the user to reboot at the end and reviews with them.
- Plymouth can be previewed without rebooting: `sudo plymouthd --debug --tty=/dev/tty63; sudo plymouth show-splash;
  sleep 5; sudo plymouth quit` on a spare VT is risky on Wayland; prefer rendering frames to PNG (the theme's
  script/images) and only do a live test if you're sure it can't grab the active VT. Report what you verified.

## Tasks
1. Limine (boot.py limine): branding with the user's display name or a tasteful mark, `interface_help_hidden`,
   `term_font_scale` for the HiDPI laptop panel, palette colours from the current palette, wallpaper style that
   doesn't stretch (backdrop/centred), timeout unchanged.
2. Plymouth "rice": redesign in the same language as the splash (same backdrop treatment, same spinner/motif so the
   handoff is seamless), eased frames (two-step or script), the password prompt shows its prompt text, messages
   handled. Use a dark neutral backdrop (or a fixed boot palette) so it doesn't go stale against wallpapers.
   Rebuild with limine-mkinitcpio once, at the end.
3. Login greeter: install the Rice Plasma Style and the icon/cursor themes system-wide (copy Rice desktoptheme to
   /usr/share/plasma/desktoptheme/Rice; icons/cursor per the user's pick, ask the orchestrator which), write the
   greeter's plasmarc / kdeglobals / kcminputrc in /var/lib/plasmalogin/.config, wallpaper synced by boot.py login.
4. Splash: per-screen wallpapers (each screen shows its own, from ~/.local/state/rice/palette-<output>.json
   _wallpaper), shared Clawd, display name (first word of GECOS full name, fallback username), same look as
   Plymouth, progress indicator in the design language, subtle motion.

## Done means
boot.py runs clean; renders of the Limine menu (or a mock), Plymouth frames, the greeter config diff, and a splash
render (offscreen, all screens) in ~/.cache/rice/shots/agent-c/boot/; a list of what needs a reboot to verify.
Report per COMMON.md.
