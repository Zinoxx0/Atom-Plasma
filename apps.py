#!/usr/bin/env python3
"""App themes that follow the wallpaper palette (called by rice.py on every change).

    VS Code   ~/.vscode/extensions/zinoxx.rice-theme-*/themes/rice-color-theme.json
              (the theme is contributed with "_watch": true, so VS Code reloads it live)
    btop      ~/.config/btop/themes/rice.theme
    MangoHud  ~/.config/MangoHud/MangoHud.conf (MangoHud reloads it live)
    Zen       userChrome.css / userContent.css / user.js in each Zen profile (applied on Zen's next start)

    fastfetch ~/.config/fastfetch/config.jsonc from templates/fastfetch.jsonc

    apps.py install-vscode    build the VS Code theme extension and install it
    apps.py setup             one-shot, not palette-driven: Dolphin's toolbar and view, Darkly's glass
    apps.py konsole-chrome    Konsole without menu bar or toolbars, tabs as pills (cheap; for login)
"""
import json
import subprocess
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import palette  # noqa: E402

HOME = Path.home()
HERE = Path(__file__).resolve().parent
mix = palette.mix


def alpha(h, a):
    return h + f"{round(a * 255):02x}"


def write_if_changed(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text() == text:
        return False
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text)
    tmp.replace(path)
    return True


ANSI = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
CLAIM = 35      # degrees: how close a wallpaper accent must be to an ANSI hue to take its slot
APART = 15      # ...and how far it must stay from every other slot (blue and cyan sit only ~22 apart)


def _hue_gap(a, b):
    return abs((a - b + 180) % 360 - 180)


def ansi(p):
    """ANSI colours as (normal, bright, faint) per slot, for Konsole, Alacritty and VS Code's terminal.

    After HyDE's kitty mapping (blacks and whites from the surface ladder, the colours from the
    wallpaper's accents, brights lifted), with one difference: HyDE hands red/green/yellow to
    whatever accents the wallpaper has, so an error can come out teal. Here each accent claims
    only the ANSI hue it already resembles (within CLAIM degrees), so the terminal wears the
    wallpaper's exact colours where they fit and red still reads as red everywhere else."""
    lch, oklch = palette.to_oklch, palette.oklch
    slots = {n: lch(p[n]) for n in ANSI[1:7]}
    claimed = {}
    for role in ("primary", "tertiary", "secondary"):
        _, c, h = lch(p[role])
        if c < 0.05:                    # a grey accent has no colour to lend
            continue
        hues = {n: claimed[n][1] if n in claimed else slots[n][2] for n in slots}
        for n in sorted((n for n in slots if n not in claimed), key=lambda s: _hue_gap(h, slots[s][2])):
            if _hue_gap(h, slots[n][2]) > CLAIM:
                break
            if all(_hue_gap(h, hues[m]) >= APART for m in slots if m != n):
                claimed[n] = (c, h)
                break
    t = {}
    for n, (L, C, H) in slots.items():
        if n in claimed:
            C, H = max(claimed[n][0], C * 0.75), claimed[n][1]   # keep the slot's lightness tier
        normal = oklch(L, C, H) if n in claimed else p[n]
        t[n] = (normal, oklch(min(0.93, L + 0.07), C, H), oklch(L - 0.12, C * 0.9, H))
    # bright black is the ghost text (autosuggestions, comments): lifted to sit between outline and muted
    t["black"] = (p["surface_high"], mix(p["outline"], p["muted"], 0.5), p["surface_container"])
    t["white"] = (p["on_surface_variant"], p["on_surface"], p["muted"])
    return t


def term(p):
    """ANSI (normal, bright) pairs for VS Code's terminal."""
    return {n: v[:2] for n, v in ansi(p).items()}


# ---------------------------------------------------------------- KDE config files
def _kesc(v):
    """A value as KConfig writes it (what kwriteconfig6 would leave in the file)."""
    v = str(v).lower() if isinstance(v, bool) else str(v)
    v = v.replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t")
    return "\\s" + v[1:] if v.startswith(" ") else v


def kde_read(path):
    """{(group, ...): {key: raw value}} of a KDE config file (raw = still escaped)."""
    out, cur = {}, None
    try:
        lines = Path(path).read_text().splitlines()
    except OSError:
        return out
    for line in lines:
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            cur = out.setdefault(tuple(s[1:-1].split("][")), {})
        elif cur is not None and "=" in s and not s.startswith("#"):
            k, v = s.split("=", 1)
            cur[k.strip()] = v
    return out


def kde_set(name, groups):
    """Set keys in a KDE config file, running kwriteconfig6 (which locks the file, so it can't race the
    app that owns it) only for the keys that differ. groups: {group or (group, subgroup): {key: value}};
    None deletes a key. name: a file in ~/.config or an absolute path. Returns True if anything changed."""
    path = Path(name) if Path(name).is_absolute() else HOME / ".config" / name
    have = kde_read(path)
    changed = False
    for g, keys in groups.items():
        g = g if isinstance(g, tuple) else (g,)
        cur = have.get(g, {})
        for k, v in keys.items():
            if (v is None and k not in cur) or (v is not None and cur.get(k) == _kesc(v)):
                continue
            cmd = ["kwriteconfig6", "--file", str(path)]
            for part in g:
                cmd += ["--group", part]
            cmd += ["--key", k] + (["--delete"] if v is None else
                                   [str(v).lower() if isinstance(v, bool) else str(v)])
            subprocess.run(cmd, check=False)
            changed = True
    return changed


def konsole_chrome():
    """Konsole's window chrome: no menu bar or toolbars, tabs only when needed, styled by rice-tabs.css
    (written by rice.py). A Konsole started before a change writes its old settings and window state
    back when it closes, so rice.py runs this every time and `apps.py konsole-chrome` fits login.
    Toolbar visibility lives in the saved window state, which every window rewrites on close."""
    kde_set("konsolerc", {
        "MainWindow": {"MenuBar": "Disabled", "ToolBarsMovable": "Disabled"},
        "TabBar": {"TabBarVisibility": "ShowTabBarWhenNeeded", "TabBarUseUserStyleSheet": True,
                   "TabBarUserStyleSheetFile": (HOME / ".local/share/konsole/rice-tabs.css").as_uri(),
                   # no close button inside the pills (middle-click or Ctrl+Shift+W closes a tab),
                   # no Search Tabs bolt in the corner
                   "CloseTabOnMiddleMouseButton": True, "CloseTabButton": "None",
                   "SearchTabsButton": "HideSearchTabsButton", "ExpandTabWidth": False},
    })
    staterc = HOME / ".local/state/konsolestaterc"
    state = kde_read(staterc).get(("MainWindow",), {}).get("State")
    if state:
        kde_set(staterc, {"MainWindow": {"State": qt_toolbars_hidden(state, ("mainToolBar", "sessionToolbar"))}})
    # hide them in open windows too, so what those write back on close is already right
    names = subprocess.run(["qdbus6"], capture_output=True, text=True).stdout.split()
    for svc in (n for n in names if n.startswith("org.kde.konsole-")):
        paths = subprocess.run(["qdbus6", svc], capture_output=True, text=True).stdout.split()
        for path in (p for p in paths if p.count("/") == 2 and p.startswith("/konsole/MainWindow_")):
            for bar in ("mainToolBar", "sessionToolbar"):
                subprocess.run(["qdbus6", svc, path, "org.kde.konsole.KXmlGuiWindow.setToolBarVisible", bar, "false"],
                               capture_output=True)


def qt_toolbars_hidden(state_b64, names):
    """A QMainWindow saveState() blob (base64) with the named toolbars marked hidden. Each toolbar is
    stored as its objectName (QString: UTF-16BE) followed by a flags byte whose low bit means shown."""
    import base64
    state = bytearray(base64.b64decode(state_b64))
    for name in names:
        enc = name.encode("utf-16-be")
        i = state.find(len(enc).to_bytes(4, "big") + enc)
        if i >= 0:
            state[i + 4 + len(enc)] &= 0xFE
    return base64.b64encode(bytes(state)).decode()


# ---------------------------------------------------------------- VS Code
def vscode(p):
    bg, deep, s, sl, sc = p["background"], p["surface_lowest"], p["surface"], p["surface_low"], p["surface_container"]
    sh, shh, ov, o = p["surface_high"], p["surface_highest"], p["outline_variant"], p["outline"]
    fg, fgv, mut = p["on_surface"], p["on_surface_variant"], p["muted"]
    pr, ter = p["primary"], p["tertiary"]
    red, orange, yellow, green = p["red"], p["orange"], p["yellow"], p["green"]
    teal, cyan, blue, magenta = p["teal"], p["cyan"], p["blue"], p["magenta"]
    none = "#00000000"
    line = alpha(ov, 0.45)
    c = {
        # base
        "foreground": fgv, "descriptionForeground": mut, "errorForeground": red, "icon.foreground": fgv,
        "focusBorder": alpha(pr, 0.55), "contrastBorder": none, "selection.background": alpha(pr, 0.3),
        "widget.shadow": "#00000070", "widget.border": line, "sash.hoverBorder": alpha(pr, 0.6),
        "textLink.foreground": blue, "textLink.activeForeground": p["blue_bright"],
        "textBlockQuote.background": sl, "textBlockQuote.border": alpha(pr, 0.6), "textCodeBlock.background": sl,
        "textPreformat.foreground": orange, "textPreformat.background": sl, "textSeparator.foreground": ov,
        "toolbar.hoverBackground": alpha(ov, 0.4), "toolbar.activeBackground": alpha(ov, 0.6),
        "progressBar.background": pr, "badge.background": pr, "badge.foreground": p["on_primary"],
        # window chrome: everything around the editor sits one step darker
        "titleBar.activeBackground": deep, "titleBar.activeForeground": fgv, "titleBar.inactiveBackground": deep,
        "titleBar.inactiveForeground": mut, "titleBar.border": none,
        "commandCenter.background": sl, "commandCenter.foreground": fgv, "commandCenter.border": line,
        "commandCenter.activeBackground": sc, "commandCenter.activeForeground": fg,
        "commandCenter.activeBorder": alpha(pr, 0.5), "commandCenter.inactiveForeground": mut,
        "menubar.selectionBackground": alpha(ov, 0.4), "menubar.selectionForeground": fg,
        "menu.background": sl, "menu.foreground": fgv, "menu.border": line, "menu.separatorBackground": line,
        "menu.selectionBackground": alpha(pr, 0.18), "menu.selectionForeground": fg,
        "activityBar.background": deep, "activityBar.foreground": fg, "activityBar.inactiveForeground": mut,
        "activityBar.activeBorder": pr, "activityBar.activeBackground": none, "activityBar.border": none,
        "activityBarBadge.background": pr, "activityBarBadge.foreground": p["on_primary"],
        "activityBarTop.foreground": fg, "activityBarTop.activeBorder": pr, "activityBarTop.inactiveForeground": mut,
        "sideBar.background": deep, "sideBar.foreground": fgv, "sideBar.border": none,
        "sideBarTitle.foreground": mut, "sideBarSectionHeader.background": deep,
        "sideBarSectionHeader.foreground": fgv, "sideBarSectionHeader.border": alpha(ov, 0.3),
        "sideBar.dropBackground": alpha(pr, 0.12),
        # lists and trees
        "list.activeSelectionBackground": alpha(pr, 0.18), "list.activeSelectionForeground": fg,
        "list.activeSelectionIconForeground": pr, "list.inactiveSelectionBackground": alpha(ov, 0.4),
        "list.inactiveSelectionForeground": fg, "list.hoverBackground": alpha(ov, 0.28), "list.hoverForeground": fg,
        "list.focusOutline": alpha(pr, 0.45), "list.focusAndSelectionOutline": alpha(pr, 0.6),
        "list.inactiveFocusOutline": none, "list.highlightForeground": pr, "list.focusHighlightForeground": pr,
        "list.dropBackground": alpha(pr, 0.15), "list.errorForeground": red, "list.warningForeground": yellow,
        "list.deemphasizedForeground": mut, "tree.indentGuidesStroke": alpha(ov, 0.7),
        "tree.inactiveIndentGuidesStroke": alpha(ov, 0.35),
        "pickerGroup.foreground": pr, "pickerGroup.border": line,
        "quickInput.background": sl, "quickInput.foreground": fgv, "quickInputTitle.background": sc,
        "quickInputList.focusBackground": alpha(pr, 0.18), "quickInputList.focusForeground": fg,
        # tabs and editor groups
        "editorGroupHeader.tabsBackground": deep, "editorGroupHeader.tabsBorder": none,
        "editorGroupHeader.noTabsBackground": deep, "editorGroupHeader.border": none,
        "editorGroup.border": line, "editorGroup.dropBackground": alpha(pr, 0.12),
        "editorGroup.emptyBackground": bg,
        "tab.activeBackground": bg, "tab.activeForeground": fg, "tab.activeBorderTop": pr, "tab.activeBorder": bg,
        "tab.inactiveBackground": deep, "tab.inactiveForeground": mut, "tab.border": deep,
        "tab.hoverBackground": s, "tab.hoverForeground": fgv, "tab.unfocusedActiveBackground": bg,
        "tab.unfocusedActiveBorderTop": alpha(pr, 0.4), "tab.unfocusedActiveForeground": fgv,
        "tab.unfocusedInactiveForeground": mut, "tab.unfocusedHoverBackground": s,
        "tab.activeModifiedBorder": ter, "tab.inactiveModifiedBorder": alpha(ter, 0.5),
        "tab.lastPinnedBorder": ov, "tab.selectedBackground": bg, "tab.selectedForeground": fg,
        "tab.selectedBorderTop": pr,
        "breadcrumb.background": bg, "breadcrumb.foreground": mut, "breadcrumb.focusForeground": fg,
        "breadcrumb.activeSelectionForeground": pr, "breadcrumbPicker.background": sl,
        # editor
        "editor.background": bg, "editor.foreground": fg,
        "editorLineNumber.foreground": ov, "editorLineNumber.activeForeground": fgv,
        "editorLineNumber.dimmedForeground": alpha(ov, 0.6),
        "editorCursor.foreground": pr, "editorCursor.background": p["on_primary"],
        "editorMultiCursor.primary.foreground": pr, "editorMultiCursor.secondary.foreground": ter,
        "editor.lineHighlightBackground": s, "editor.lineHighlightBorder": none,
        "editor.selectionBackground": alpha(pr, 0.25), "editor.inactiveSelectionBackground": alpha(pr, 0.12),
        "editor.selectionHighlightBackground": alpha(blue, 0.15), "editor.selectionHighlightBorder": none,
        "editor.wordHighlightBackground": alpha(blue, 0.14), "editor.wordHighlightStrongBackground": alpha(magenta, 0.16),
        "editor.wordHighlightTextBackground": alpha(blue, 0.14),
        "editor.findMatchBackground": alpha(ter, 0.35), "editor.findMatchBorder": ter,
        "editor.findMatchHighlightBackground": alpha(ter, 0.16), "editor.findRangeHighlightBackground": alpha(sh, 0.45),
        "editor.rangeHighlightBackground": alpha(pr, 0.08), "editor.hoverHighlightBackground": alpha(pr, 0.12),
        "editor.linkedEditingBackground": alpha(pr, 0.1), "editor.snippetTabstopHighlightBackground": alpha(ter, 0.15),
        "editor.foldBackground": alpha(blue, 0.06), "editor.foldPlaceholderForeground": mut,
        "editorWhitespace.foreground": alpha(ov, 0.5), "editorRuler.foreground": alpha(ov, 0.5),
        "editorIndentGuide.background1": alpha(ov, 0.4), "editorIndentGuide.activeBackground1": alpha(o, 0.8),
        "editorBracketMatch.background": alpha(pr, 0.14), "editorBracketMatch.border": alpha(pr, 0.55),
        "editorBracketHighlight.foreground1": pr, "editorBracketHighlight.foreground2": ter,
        "editorBracketHighlight.foreground3": cyan, "editorBracketHighlight.foreground4": magenta,
        "editorBracketHighlight.foreground5": green, "editorBracketHighlight.foreground6": blue,
        "editorBracketHighlight.unexpectedBracket.foreground": red,
        "editorBracketPairGuide.activeBackground1": alpha(pr, 0.5), "editorBracketPairGuide.activeBackground2": alpha(ter, 0.5),
        "editorBracketPairGuide.activeBackground3": alpha(cyan, 0.5), "editorBracketPairGuide.activeBackground4": alpha(magenta, 0.5),
        "editorCodeLens.foreground": mut, "editorLink.activeForeground": blue,
        "editorInlayHint.background": alpha(sh, 0.55), "editorInlayHint.foreground": mut,
        "editorGhostText.foreground": alpha(mut, 0.85), "editorLightBulb.foreground": yellow,
        "editorLightBulbAutoFix.foreground": teal,
        "editorError.foreground": red, "editorWarning.foreground": yellow, "editorInfo.foreground": blue,
        "editorHint.foreground": teal, "editorUnnecessaryCode.opacity": "#000000a0",
        "editorGutter.background": bg, "editorGutter.addedBackground": green, "editorGutter.modifiedBackground": blue,
        "editorGutter.deletedBackground": red, "editorGutter.foldingControlForeground": mut,
        "editorOverviewRuler.border": none, "editorOverviewRuler.background": bg,
        "editorOverviewRuler.findMatchForeground": alpha(ter, 0.7), "editorOverviewRuler.errorForeground": red,
        "editorOverviewRuler.warningForeground": yellow, "editorOverviewRuler.infoForeground": blue,
        "editorOverviewRuler.addedForeground": alpha(green, 0.7), "editorOverviewRuler.modifiedForeground": alpha(blue, 0.7),
        "editorOverviewRuler.deletedForeground": alpha(red, 0.7),
        "editorOverviewRuler.selectionHighlightForeground": alpha(pr, 0.6),
        "editorWidget.background": sl, "editorWidget.foreground": fgv, "editorWidget.border": line,
        "editorWidget.resizeBorder": alpha(pr, 0.5),
        "editorSuggestWidget.background": sl, "editorSuggestWidget.border": line, "editorSuggestWidget.foreground": fgv,
        "editorSuggestWidget.selectedBackground": alpha(pr, 0.18), "editorSuggestWidget.selectedForeground": fg,
        "editorSuggestWidget.highlightForeground": pr, "editorSuggestWidget.focusHighlightForeground": pr,
        "editorHoverWidget.background": sl, "editorHoverWidget.border": line, "editorHoverWidget.statusBarBackground": sc,
        "editorStickyScroll.background": bg, "editorStickyScrollHover.background": s,
        "editorStickyScroll.shadow": "#00000060", "editorStickyScroll.border": alpha(ov, 0.3),
        "editorMarkerNavigation.background": sl, "editorMarkerNavigationError.background": red,
        "editorMarkerNavigationWarning.background": yellow, "editorMarkerNavigationInfo.background": blue,
        "peekView.border": pr, "peekViewEditor.background": s, "peekViewEditorGutter.background": s,
        "peekViewResult.background": sl, "peekViewTitle.background": sl, "peekViewTitleLabel.foreground": fg,
        "peekViewTitleDescription.foreground": mut, "peekViewResult.selectionBackground": alpha(pr, 0.18),
        "peekViewResult.selectionForeground": fg, "peekViewResult.fileForeground": fgv, "peekViewResult.lineForeground": mut,
        "peekViewEditor.matchHighlightBackground": alpha(ter, 0.3), "peekViewResult.matchHighlightBackground": alpha(ter, 0.3),
        "minimap.background": bg, "minimap.selectionHighlight": alpha(pr, 0.45), "minimap.findMatchHighlight": alpha(ter, 0.55),
        "minimap.errorHighlight": alpha(red, 0.7), "minimap.warningHighlight": alpha(yellow, 0.6),
        "minimapSlider.background": alpha(ov, 0.22), "minimapSlider.hoverBackground": alpha(ov, 0.4),
        "minimapSlider.activeBackground": alpha(pr, 0.3), "minimapGutter.addedBackground": green,
        "minimapGutter.modifiedBackground": blue, "minimapGutter.deletedBackground": red,
        "scrollbar.shadow": none, "scrollbarSlider.background": alpha(ov, 0.32),
        "scrollbarSlider.hoverBackground": alpha(ov, 0.6), "scrollbarSlider.activeBackground": alpha(pr, 0.4),
        "diffEditor.insertedTextBackground": alpha(green, 0.14), "diffEditor.removedTextBackground": alpha(red, 0.14),
        "diffEditor.insertedLineBackground": alpha(green, 0.07), "diffEditor.removedLineBackground": alpha(red, 0.07),
        "diffEditor.diagonalFill": alpha(ov, 0.4), "diffEditor.border": line,
        "diffEditorGutter.insertedLineBackground": alpha(green, 0.12), "diffEditorGutter.removedLineBackground": alpha(red, 0.12),
        "merge.currentHeaderBackground": alpha(teal, 0.35), "merge.currentContentBackground": alpha(teal, 0.1),
        "merge.incomingHeaderBackground": alpha(blue, 0.35), "merge.incomingContentBackground": alpha(blue, 0.1),
        # panel, terminal, status bar
        "panel.background": deep, "panel.border": line, "panel.dropBorder": pr,
        "panelTitle.activeForeground": fg, "panelTitle.activeBorder": pr, "panelTitle.inactiveForeground": mut,
        "panelInput.border": line, "panelSection.border": line, "panelSectionHeader.background": deep,
        "outputView.background": deep, "outputViewStickyScroll.background": deep,
        "terminal.background": deep, "terminal.foreground": fg, "terminal.border": line,
        "terminalCursor.foreground": pr, "terminalCursor.background": p["on_primary"],
        "terminal.selectionBackground": alpha(pr, 0.28), "terminal.inactiveSelectionBackground": alpha(pr, 0.14),
        "terminal.findMatchBackground": alpha(ter, 0.35), "terminal.findMatchHighlightBackground": alpha(ter, 0.16),
        "terminalCommandDecoration.defaultBackground": ov, "terminalCommandDecoration.successBackground": green,
        "terminalCommandDecoration.errorBackground": red, "terminalOverviewRuler.cursorForeground": alpha(pr, 0.6),
        "statusBar.background": deep, "statusBar.foreground": mut, "statusBar.border": none,
        "statusBar.focusBorder": alpha(pr, 0.5),
        "statusBar.noFolderBackground": deep, "statusBar.noFolderForeground": mut,
        "statusBar.debuggingBackground": p["primary_container"], "statusBar.debuggingForeground": p["on_primary_container"],
        "statusBar.debuggingBorder": none,
        "statusBarItem.remoteBackground": pr, "statusBarItem.remoteForeground": p["on_primary"],
        "statusBarItem.remoteHoverBackground": p["primary_dim"],
        "statusBarItem.hoverBackground": alpha(ov, 0.4), "statusBarItem.hoverForeground": fg,
        "statusBarItem.activeBackground": alpha(ov, 0.6), "statusBarItem.compactHoverBackground": alpha(ov, 0.4),
        "statusBarItem.prominentBackground": alpha(pr, 0.2), "statusBarItem.prominentForeground": pr,
        "statusBarItem.prominentHoverBackground": alpha(pr, 0.3),
        "statusBarItem.errorBackground": p["red_dim"], "statusBarItem.errorForeground": deep,
        "statusBarItem.warningBackground": p["yellow_dim"], "statusBarItem.warningForeground": deep,
        "statusBarItem.offlineBackground": p["red_dim"],
        # controls
        "input.background": sl, "input.foreground": fg, "input.border": line, "input.placeholderForeground": mut,
        "inputOption.activeBorder": pr, "inputOption.activeBackground": alpha(pr, 0.2), "inputOption.activeForeground": fg,
        "inputOption.hoverBackground": alpha(ov, 0.4),
        "inputValidation.errorBackground": sl, "inputValidation.errorBorder": red,
        "inputValidation.warningBackground": sl, "inputValidation.warningBorder": yellow,
        "inputValidation.infoBackground": sl, "inputValidation.infoBorder": blue,
        "dropdown.background": sl, "dropdown.listBackground": sl, "dropdown.border": line, "dropdown.foreground": fgv,
        "button.background": pr, "button.foreground": p["on_primary"], "button.hoverBackground": mix(pr, fg, 0.25),
        "button.border": none, "button.separator": alpha(p["on_primary"], 0.4),
        "button.secondaryBackground": sh, "button.secondaryForeground": fg, "button.secondaryHoverBackground": shh,
        "checkbox.background": sl, "checkbox.border": ov, "checkbox.foreground": pr, "checkbox.selectBackground": sl,
        "radio.activeBackground": alpha(pr, 0.2), "radio.activeBorder": pr, "radio.activeForeground": fg,
        "keybindingLabel.background": sh, "keybindingLabel.foreground": fgv, "keybindingLabel.border": ov,
        "keybindingLabel.bottomBorder": ov,
        "settings.headerForeground": fg, "settings.modifiedItemIndicator": pr, "settings.focusedRowBackground": alpha(ov, 0.2),
        "settings.rowHoverBackground": alpha(ov, 0.15), "settings.focusedRowBorder": alpha(pr, 0.4),
        "settings.checkboxBackground": sl, "settings.checkboxBorder": ov, "settings.dropdownBackground": sl,
        "settings.dropdownBorder": line, "settings.textInputBackground": sl, "settings.textInputBorder": line,
        "settings.numberInputBackground": sl, "settings.numberInputBorder": line,
        "notifications.background": sl, "notifications.foreground": fgv, "notifications.border": line,
        "notificationCenterHeader.background": sc, "notificationCenterHeader.foreground": fgv,
        "notificationToast.border": line, "notificationLink.foreground": blue,
        "notificationsErrorIcon.foreground": red, "notificationsWarningIcon.foreground": yellow,
        "notificationsInfoIcon.foreground": blue,
        "banner.background": sc, "banner.foreground": fgv, "banner.iconForeground": pr,
        "debugToolBar.background": sl, "debugToolBar.border": line,
        "editor.stackFrameHighlightBackground": alpha(yellow, 0.12),
        "editor.focusedStackFrameHighlightBackground": alpha(green, 0.12),
        "debugIcon.breakpointForeground": red, "debugIcon.breakpointUnverifiedForeground": p["red_dim"],
        "debugConsole.infoForeground": blue, "debugConsole.warningForeground": yellow,
        "debugConsole.errorForeground": red, "debugConsole.sourceForeground": fgv,
        "debugTokenExpression.name": blue, "debugTokenExpression.value": fgv, "debugTokenExpression.string": green,
        "debugTokenExpression.number": orange, "debugTokenExpression.boolean": orange, "debugTokenExpression.error": red,
        "gitDecoration.modifiedResourceForeground": blue, "gitDecoration.addedResourceForeground": green,
        "gitDecoration.untrackedResourceForeground": green, "gitDecoration.deletedResourceForeground": red,
        "gitDecoration.renamedResourceForeground": teal, "gitDecoration.ignoredResourceForeground": alpha(mut, 0.7),
        "gitDecoration.conflictingResourceForeground": orange, "gitDecoration.stageModifiedResourceForeground": cyan,
        "gitDecoration.stageDeletedResourceForeground": p["red_dim"], "gitDecoration.submoduleResourceForeground": magenta,
        "scmGraph.foreground1": pr, "scmGraph.foreground2": ter, "scmGraph.foreground3": cyan,
        "scmGraph.foreground4": magenta, "scmGraph.foreground5": green,
        "scmGraph.historyItemRefColor": blue, "scmGraph.historyItemRemoteRefColor": magenta,
        "scmGraph.historyItemBaseRefColor": orange, "scmGraph.historyItemHoverDefaultLabelForeground": fg,
        "charts.foreground": fgv, "charts.lines": ov, "charts.red": red, "charts.orange": orange,
        "charts.yellow": yellow, "charts.green": green, "charts.blue": blue, "charts.purple": magenta,
        "welcomePage.tileBackground": sl, "welcomePage.tileHoverBackground": sc, "welcomePage.tileBorder": line,
        "welcomePage.progress.foreground": pr, "walkThrough.embeddedEditorBackground": sl,
        "problemsErrorIcon.foreground": red, "problemsWarningIcon.foreground": yellow,
        "problemsInfoIcon.foreground": blue, "testing.iconPassed": green, "testing.iconFailed": red,
        "testing.iconQueued": yellow, "testing.runAction": green,
        "chat.requestBackground": sl, "chat.requestBorder": line, "chat.slashCommandBackground": alpha(pr, 0.2),
        "chat.slashCommandForeground": pr, "chat.avatarBackground": sc, "chat.avatarForeground": fgv,
        "inlineChat.background": sl, "inlineChat.border": line,
        "extensionButton.prominentBackground": pr, "extensionButton.prominentForeground": p["on_primary"],
        "extensionButton.prominentHoverBackground": mix(pr, fg, 0.25), "extensionBadge.remoteBackground": pr,
        "extensionBadge.remoteForeground": p["on_primary"], "extensionIcon.starForeground": ter,
        "extensionIcon.verifiedForeground": blue, "extensionIcon.preReleaseForeground": orange,
        "symbolIcon.classForeground": teal, "symbolIcon.structForeground": cyan, "symbolIcon.interfaceForeground": cyan,
        "symbolIcon.enumeratorForeground": orange, "symbolIcon.enumeratorMemberForeground": orange,
        "symbolIcon.constantForeground": orange, "symbolIcon.functionForeground": blue,
        "symbolIcon.methodForeground": blue, "symbolIcon.constructorForeground": blue,
        "symbolIcon.variableForeground": fgv, "symbolIcon.fieldForeground": teal, "symbolIcon.propertyForeground": teal,
        "symbolIcon.keywordForeground": magenta, "symbolIcon.moduleForeground": cyan, "symbolIcon.namespaceForeground": cyan,
        "symbolIcon.typeParameterForeground": cyan, "symbolIcon.stringForeground": green,
        "symbolIcon.numberForeground": orange, "symbolIcon.booleanForeground": orange,
        "symbolIcon.eventForeground": ter, "symbolIcon.fileForeground": fgv, "symbolIcon.folderForeground": fgv,
        "symbolIcon.snippetForeground": mut, "symbolIcon.textForeground": fgv, "symbolIcon.colorForeground": pr,
    }

    def tok(scope, color, style=None):
        s = {"foreground": color}
        if style:
            s["fontStyle"] = style
        return {"scope": scope if isinstance(scope, list) else [scope], "settings": s}

    punct = mix(fgv, mut, 0.45)
    tokens = [
        {"settings": {"foreground": fg, "background": bg}},
        tok(["comment", "punctuation.definition.comment", "string.comment"], mut, "italic"),
        tok(["comment.block.documentation", "comment.line.documentation"], mix(mut, fgv, 0.25), "italic"),
        tok(["keyword", "keyword.control", "storage.type", "storage.modifier", "keyword.other.using",
             "keyword.other.typedef", "keyword.type", "storage.type.struct", "storage.type.enum",
             "storage.type.union", "storage.type.class"], magenta),
        tok(["keyword.control.flow", "keyword.control.conditional", "keyword.control.loop",
             "keyword.control.return", "keyword.control.trycatch", "keyword.control.import",
             "keyword.control.from", "keyword.control.export"], magenta, "italic"),
        tok(["keyword.operator", "keyword.operator.assignment", "punctuation.separator.key-value",
             "storage.type.function.arrow", "punctuation.accessor", "punctuation.separator.dot-access",
             "punctuation.separator.pointer-access", "punctuation.separator.period"], cyan),
        tok(["keyword.operator.new", "keyword.operator.expression", "keyword.operator.logical.python",
             "keyword.operator.sizeof", "keyword.operator.wordlike"], magenta),
        tok(["punctuation", "meta.brace", "punctuation.terminator", "punctuation.separator.delimiter",
             "punctuation.separator.comma", "meta.delimiter"], punct),
        tok(["string", "string.quoted", "string.template", "punctuation.definition.string"], green),
        tok(["string.regexp", "constant.other.character-class.regexp"], teal),
        tok(["constant.character.escape", "constant.other.placeholder", "constant.character.format.placeholder",
             "punctuation.definition.template-expression", "punctuation.section.embedded"], p["cyan_bright"]),
        tok(["constant.numeric", "constant.language", "constant.language.boolean", "constant.other.enum",
             "support.constant", "constant.other.caps", "variable.other.constant", "variable.other.enummember",
             "entity.name.constant"], orange),
        tok(["entity.name.function", "support.function", "meta.function-call.generic", "meta.function-call entity.name.function",
             "variable.function", "entity.name.function.member", "support.function.builtin"], blue),
        tok(["entity.name.function.macro", "entity.name.function.preprocessor", "entity.name.macro",
             "support.macro"], orange),
        tok(["meta.preprocessor", "keyword.control.directive", "punctuation.definition.directive",
             "keyword.other.import", "keyword.control.import.include"], cyan),
        tok(["string.quoted.other.lt-gt.include", "meta.preprocessor.include string"], green),
        tok(["entity.name.type", "support.type", "entity.name.class", "entity.other.inherited-class",
             "entity.name.namespace", "entity.name.type.namespace", "support.class", "entity.name.type.struct", "entity.name.type.enum", "entity.name.type.alias",
             "entity.name.scope-resolution", "support.type.posix-reserved"], teal),
        tok(["storage.type.built-in", "storage.type.primitive", "support.type.primitive",
             "support.type.builtin", "keyword.type.builtin"], magenta),
        tok(["variable", "variable.other", "variable.other.readwrite", "meta.definition.variable.name"], fg),
        tok(["variable.parameter", "meta.parameter", "variable.parameter.function"], yellow),
        tok(["variable.other.property", "variable.other.member", "variable.other.object.property",
             "support.variable.property", "entity.name.variable.field", "meta.object-literal.key",
             "variable.other.field"], teal),
        tok(["variable.language", "variable.language.this", "variable.language.self", "variable.parameter.function.language.special.self"], red, "italic"),
        tok(["entity.name.function.decorator", "meta.decorator", "punctuation.decorator",
             "entity.name.function.attribute", "meta.attribute"], ter),
        tok(["entity.name.tag", "punctuation.definition.tag"], red),
        tok(["entity.other.attribute-name", "entity.other.attribute-name.class.css",
             "entity.other.attribute-name.id.css"], yellow, "italic"),
        tok(["support.type.property-name", "support.type.property-name.json", "meta.mapping.key string"], blue),
        tok(["support.type.property-name.css", "support.type.vendored.property-name.css"], teal),
        tok(["meta.property-value.css", "support.constant.property-value.css", "constant.numeric.css",
             "keyword.other.unit"], orange),
        tok(["entity.name.section", "markup.heading", "markup.heading entity.name"], pr, "bold"),
        tok(["markup.bold"], ter, "bold"),
        tok(["markup.italic"], magenta, "italic"),
        tok(["markup.strikethrough"], mut, "strikethrough"),
        tok(["markup.inline.raw", "markup.fenced_code", "markup.raw"], orange),
        tok(["markup.underline.link", "string.other.link", "markup.link"], blue, "underline"),
        tok(["markup.quote"], mut, "italic"),
        tok(["markup.list punctuation.definition.list.begin", "punctuation.definition.list"], ter),
        tok(["markup.inserted", "meta.diff.header.to-file", "punctuation.definition.inserted"], green),
        tok(["markup.deleted", "meta.diff.header.from-file", "punctuation.definition.deleted"], red),
        tok(["markup.changed", "punctuation.definition.changed"], blue),
        tok(["meta.diff.range", "meta.diff.header"], cyan),
        tok(["entity.name.function.target.makefile", "entity.name.function.target"], blue),
        tok(["variable.other.makefile", "variable.other.normal.shell", "punctuation.definition.variable.shell",
             "variable.other.special.shell", "variable.other.positional.shell"], yellow),
        tok(["support.function.builtin.shell", "entity.name.command.shell"], blue),
        tok(["invalid", "invalid.illegal"], red, "underline"),
        tok(["invalid.deprecated"], orange, "strikethrough"),
    ]
    semantic = {
        "parameter": yellow, "property": teal, "property.readonly": teal, "enumMember": orange,
        "macro": orange, "namespace": cyan, "type": teal, "class": teal, "struct": teal, "interface": cyan,
        "typeParameter": cyan, "function": blue, "method": blue, "function.defaultLibrary": blue,
        "variable": fg, "variable.readonly": orange, "variable.readonly.local": fg,
        "variable.defaultLibrary": orange, "keyword": magenta, "label": ter,
        "selfParameter": {"foreground": red, "italic": True}, "decorator": ter,
        "*.deprecated": {"strikethrough": True},
    }
    return {"$schema": "vscode://schemas/color-theme", "name": "Rice", "type": "dark",
            "semanticHighlighting": True, "colors": dict(c, **{f"terminal.ansi{k}": v for k, v in ansi_vscode(p).items()}),
            "tokenColors": tokens, "semanticTokenColors": semantic}


def ansi_vscode(p):
    out = {}
    for n, (norm, bright) in term(p).items():
        out[n.capitalize()] = norm
        out["Bright" + n.capitalize()] = bright
    return out


VSCODE_EXT = HOME / ".vscode/extensions"
VSCODE_PKG = {
    "name": "rice-theme", "displayName": "Rice", "publisher": "zinoxx", "version": "1.0.0",
    "description": "Wallpaper-driven theme, regenerated by ~/.config/plasma-rice/rice.py",
    "engines": {"vscode": "^1.80.0"}, "categories": ["Themes"],
    "contributes": {"themes": [{"id": "Rice", "label": "Rice", "uiTheme": "vs-dark",
                                "path": "./themes/rice-color-theme.json", "_watch": True}]},
}


def apply_vscode(p):
    text = json.dumps(vscode(p), indent=1) + "\n"
    for d in VSCODE_EXT.glob("zinoxx.rice-theme-*"):
        write_if_changed(d / "themes/rice-color-theme.json", text)


def install_vscode(p):
    """Package the theme as a .vsix (a zip with a manifest) and install it with the code CLI."""
    out = HOME / ".cache/rice/rice-theme.vsix"
    out.parent.mkdir(parents=True, exist_ok=True)
    v = VSCODE_PKG
    manifest = f"""<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="{v['name']}" Version="{v['version']}" Publisher="{v['publisher']}"/>
    <DisplayName>{v['displayName']}</DisplayName>
    <Description xml:space="preserve">{v['description']}</Description>
    <Categories>Themes</Categories>
    <Properties><Property Id="Microsoft.VisualStudio.Code.Engine" Value="{v['engines']['vscode']}"/></Properties>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
  <Dependencies/>
  <Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets>
</PackageManifest>
"""
    types = ('<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
             '<Default Extension=".json" ContentType="application/json"/>'
             '<Default Extension=".vsixmanifest" ContentType="text/xml"/></Types>')
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", types)
        z.writestr("extension.vsixmanifest", manifest)
        z.writestr("extension/package.json", json.dumps(v, indent=2))
        z.writestr("extension/themes/rice-color-theme.json", json.dumps(vscode(p), indent=1) + "\n")
    subprocess.run(["code", "--install-extension", str(out), "--force"], check=True)


# ---------------------------------------------------------------- btop
def btop(p):
    t = {
        "main_bg": p["background"], "main_fg": p["on_surface"], "title": p["on_surface"], "hi_fg": p["primary"],
        "selected_bg": p["surface_high"], "selected_fg": p["primary"], "inactive_fg": p["outline"],
        "graph_text": p["on_surface_variant"], "meter_bg": p["surface_high"], "proc_misc": p["tertiary"],
        "cpu_box": p["primary_dim"], "mem_box": p["tertiary_dim"], "net_box": p["magenta_dim"],
        "proc_box": p["blue_dim"], "div_line": p["outline_variant"],
        "temp_start": p["green"], "temp_mid": p["yellow"], "temp_end": p["red"],
        "cpu_start": p["teal"], "cpu_mid": p["blue"], "cpu_end": p["magenta"],
        "free_start": p["green_dim"], "free_mid": p["green"], "free_end": p["green_bright"],
        "cached_start": p["blue_dim"], "cached_mid": p["blue"], "cached_end": p["blue_bright"],
        "available_start": p["yellow_dim"], "available_mid": p["yellow"], "available_end": p["yellow_bright"],
        "used_start": p["red_dim"], "used_mid": p["red"], "used_end": p["red_bright"],
        "download_start": p["cyan_dim"], "download_mid": p["cyan"], "download_end": p["cyan_bright"],
        "upload_start": p["magenta_dim"], "upload_mid": p["magenta"], "upload_end": p["magenta_bright"],
        "process_start": p["primary_dim"], "process_mid": p["primary"], "process_end": p["tertiary"],
    }
    return "# Generated by ~/.config/plasma-rice/apps.py. Do not edit.\n" + \
        "".join(f'theme[{k}]="{v}"\n' for k, v in t.items())


BTOP_CONF = """color_theme = "rice"
theme_background = false
truecolor = true
rounded_corners = true
graph_symbol = "braille"
"""


def apply_btop(p):
    d = HOME / ".config/btop"
    write_if_changed(d / "themes/rice.theme", btop(p))
    if not (d / "btop.conf").exists():
        write_if_changed(d / "btop.conf", BTOP_CONF)


# ---------------------------------------------------------------- MangoHud
def mangohud(p):
    h = {k: v.lstrip("#") for k, v in p.items() if isinstance(v, str) and v.startswith("#")}
    return f"""# Generated by ~/.config/plasma-rice/apps.py from the wallpaper palette. Do not edit.
# Show it in a game with MANGOHUD=1 %command% (or mangohud %command%); Shift_R+F12 toggles it.
legacy_layout=false
horizontal
hud_compact
position=top-left
offset_x=14
offset_y=14
round_corners=10
background_alpha=0.6
background_color={h['surface_lowest']}
font_file=/usr/share/fonts/TTF/JetBrainsMonoNerdFont-SemiBold.ttf
font_size=17
text_color={h['on_surface_variant']}
text_outline=0

fps
fps_color_change
fps_value=30,60
fps_color={h['red']},{h['yellow']},{h['green']}
frametime
frame_timing=1
frametime_color={h['primary']}
gpu_stats
gpu_temp
gpu_load_change
gpu_load_value=60,90
gpu_load_color={h['on_surface_variant']},{h['yellow']},{h['red']}
gpu_color={h['teal']}
cpu_stats
cpu_temp
cpu_load_change
cpu_load_value=60,90
cpu_load_color={h['on_surface_variant']},{h['yellow']},{h['red']}
cpu_color={h['blue']}
vram
vram_color={h['magenta']}
ram
ram_color={h['magenta_bright']}
engine_color={h['tertiary']}
wine_color={h['tertiary']}
media_player_color={h['on_surface_variant']}
toggle_hud=Shift_R+F12
"""


def apply_mangohud(p):
    write_if_changed(HOME / ".config/MangoHud/MangoHud.conf", mangohud(p))


# ---------------------------------------------------------------- Zen Browser
def rgba(h, a):
    return f"rgba({palette.rgb_csv(h)}, {a})"


def zen_chrome(p):
    """userChrome.css: Zen's own colour variables from the palette, over a translucent gradient
    (zen.widget.linux.transparency + KWin's blur make the sidebar frosted glass)."""
    pr, ov = p["primary"], p["outline_variant"]
    glass = (f"linear-gradient(135deg, {rgba(p['primary_container'], 0.72)} 0%, "
             f"{rgba(p['surface_lowest'], 0.84)} 52%, {rgba(p['tertiary_container'], 0.68)} 100%)")
    return f"""/* Rice for Zen: generated by ~/.config/plasma-rice/apps.py from the wallpaper palette. Do not edit. */
:root, :host(:is(.anonymous-content-host, notification-message)) {{
  --zen-primary-color: {pr} !important;
  --zen-branding-dark: {p['background']} !important;
  --zen-colors-primary: color-mix(in srgb, {pr} 22%, {p['surface']}) !important;
  --zen-colors-secondary: color-mix(in srgb, {pr} 32%, {p['surface']}) !important;
  --zen-colors-tertiary: {p['surface_lowest']} !important;
  --zen-colors-hover-bg: color-mix(in srgb, {pr} 14%, {p['surface_low']}) !important;
  --zen-colors-primary-foreground: {p['on_surface']} !important;
  --zen-colors-border: {rgba(ov, 0.55)} !important;
  --zen-colors-border-contrast: {rgba(ov, 0.3)} !important;
  --zen-colors-input-bg: {p['surface_low']} !important;
  --zen-input-border-color: {ov} !important;
  --zen-dialog-background: {p['surface']} !important;
  --zen-urlbar-background: {p['surface_low']} !important;
  --zen-main-browser-background: {glass} !important;
  --zen-main-browser-background-toolbar: {glass} !important;
  --toolbox-textcolor: {p['on_surface']} !important;
  --toolbar-field-color: {p['on_surface']} !important;
  --arrowpanel-background: {p['surface_low']} !important;
  --arrowpanel-color: {p['on_surface']} !important;
  --arrowpanel-border-color: {rgba(ov, 0.6)} !important;
  --panel-separator-color: {rgba(ov, 0.6)} !important;
  --focus-outline-color: {pr} !important;
  --zen-sidebar-themed-icon-fill: {p['on_surface_variant']} !important;
}}

/* Zen paints the workspace gradient on these layers and sets its variables inline on them,
   so override the layers themselves (::before is the cross-fade target while switching spaces) */
.zen-browser-generic-background::after,
.zen-browser-generic-background::before {{
  background: {glass} !important;
}}

/* selected tab: a soft accent wash with a hairline, instead of plain white */
.tabbrowser-tab:is([selected], [multiselected]) .tab-background {{
  background-color: {rgba(pr, 0.16)} !important;
  box-shadow: inset 0 0 0 1px {rgba(pr, 0.32)} !important;
}}
.tabbrowser-tab:not([selected]):hover .tab-background {{
  background-color: {rgba(p['on_surface'], 0.07)} !important;
}}

/* command bar / url bar popup */
#urlbar[breakout-extend] > .urlbar-background,
#urlbar[breakout-extend] #urlbar-background {{
  background-color: {p['surface_low']} !important;
  border: 1px solid {rgba(ov, 0.7)} !important;
  box-shadow: 0 12px 40px rgba(0, 0, 0, 0.45) !important;
}}
.urlbarView-row[selected] {{
  background-color: {rgba(pr, 0.18)} !important;
}}

/* menus and popups */
menupopup, panel {{
  --panel-background: {p['surface_low']} !important;
  --panel-color: {p['on_surface']} !important;
  --panel-border-color: {rgba(ov, 0.6)} !important;
}}
"""


def zen_content(p):
    """userContent.css: dark, palette-tinted backgrounds for blank/new-tab pages and scrollbars everywhere."""
    return f"""/* Rice for Zen: generated by ~/.config/plasma-rice/apps.py. Do not edit. */
:root {{
  scrollbar-color: {rgba(p['outline'], 0.7)} transparent;
}}
@-moz-document url("about:blank"), url("about:newtab"), url("about:home"), url("about:privatebrowsing") {{
  html, body {{ background-color: {p['background']} !important; }}
}}
"""


ZEN_BEGIN, ZEN_END = "// rice: begin (managed by ~/.config/plasma-rice/apps.py)", "// rice: end"


def zen_userjs(p, current):
    prefs = {
        "toolkit.legacyUserProfileCustomizations.stylesheets": True,
        "zen.widget.linux.transparency": True,
        "zen.theme.accent-color": p["primary"],
        "browser.display.background_color.dark": p["background"],
        "layout.css.prefers-color-scheme.content-override": 0,
        "ui.systemUsesDarkTheme": 1,       # Zen stays dark when a light wallpaper turns the desktop light
        "svg.context-properties.content.enabled": True,
    }
    block = [ZEN_BEGIN] + [f"user_pref({json.dumps(k)}, {json.dumps(v)});" for k, v in prefs.items()] + [ZEN_END]
    lines = current.splitlines()
    if ZEN_BEGIN in lines and ZEN_END in lines:
        i, j = lines.index(ZEN_BEGIN), lines.index(ZEN_END)
        lines[i:j + 1] = block
    else:
        lines += block
    return "\n".join(lines) + "\n"


def zen_profiles():
    import configparser
    root = HOME / ".config/zen"
    ini = configparser.ConfigParser()
    ini.read(root / "profiles.ini")
    for s in ini.sections():
        path = ini.get(s, "Path", fallback=None)
        if path and s.startswith("Profile"):
            d = root / path if ini.getboolean(s, "IsRelative", fallback=True) else Path(path)
            if d.is_dir():
                yield d


def apply_zen(p):
    """Zen reads these at startup, so a wallpaper change shows up the next time it starts."""
    for d in zen_profiles():
        write_if_changed(d / "chrome/userChrome.css", zen_chrome(p))
        write_if_changed(d / "chrome/userContent.css", zen_content(p))
        uj = d / "user.js"
        write_if_changed(uj, zen_userjs(p, uj.read_text() if uj.exists() else ""))


# ---------------------------------------------------------------- fastfetch
FASTFETCH_LOGO = "wallpaper"    # "wallpaper": a rounded square of it, "clawd": the text art in ~/.config/fastfetch


def fastfetch_logo(p):
    """The current wallpaper as a rounded square (radius lg at the size it's shown), named after the image
    so fastfetch's own image cache never shows a stale one."""
    import hashlib
    img = Path(p.get("_wallpaper", ""))
    if FASTFETCH_LOGO != "wallpaper" or not img.is_file():
        return None
    d = HOME / ".cache/rice/fastfetch"
    out = d / f"logo-{hashlib.sha1(f'{img}:{img.stat().st_mtime}'.encode()).hexdigest()[:10]}.png"
    if not out.exists():
        d.mkdir(parents=True, exist_ok=True)
        subprocess.run(["magick", f"{img}[0]", "-resize", "400x400^", "-gravity", "center", "-extent", "400x400",
                        "(", "-size", "400x400", "xc:none", "-fill", "white", "-draw", "roundrectangle 0,0,399,399,40,40", ")",
                        "-compose", "DstIn", "-composite", str(out)], check=False, timeout=30)
        for old in d.glob("logo-*.png"):
            if old != out:
                old.unlink(missing_ok=True)
    return out if out.exists() else None


def accent3(p):
    """The palette colour furthest in hue from both primary and tertiary (red is kept for errors)."""
    hue = lambda n: palette.to_oklch(p[n])[2]   # noqa: E731
    return max(("teal", "cyan", "blue", "magenta", "green", "yellow", "orange"),
               key=lambda n: min(_hue_gap(hue(n), hue("primary")), _hue_gap(hue(n), hue("tertiary"))))


def fill(text, p, extra=None):
    """{{name}} -> #hex, {{name:rgb}} -> r;g;b (for {#38;2;...} codes); extra values win over the palette."""
    import re
    vals = dict(p, **(extra or {}))

    def sub(m):
        v = vals.get(m.group(1))
        if v is None:
            return m.group(0)
        return palette.rgb_csv(v).replace(",", ";") if m.group(2) == "rgb" else str(v)
    return re.sub(r"\{\{(\w+)(?::(rgb))?\}\}", sub, text)


def apply_fastfetch(p):
    src = (HERE / "templates/fastfetch.jsonc").read_text()
    body = "\n".join(line for line in src.splitlines() if not line.startswith("//"))
    logo = fastfetch_logo(p)
    text = fill(body, p, {"logo": logo or HOME / ".config/fastfetch/clawd.txt", "logo_type": "kitty" if logo else "file-raw",
                          "logo_width": 20 if logo else 44, "accent3": p[accent3(p)]})
    write_if_changed(HOME / ".config/fastfetch/config.jsonc",
                     "// Generated by ~/.config/plasma-rice/apps.py from templates/fastfetch.jsonc. Do not edit.\n" + text)


# ---------------------------------------------------------------- one-shot app settings
# Not palette-driven, so rice.py doesn't rewrite them on every wallpaper (a setting the user changes
# in the app stays changed); `apps.py setup` applies them again, e.g. after a reset.
DOLPHIN_TOOLBAR = """    <ToolBar noMerge="1" name="mainToolBar" ToolButtonStyle="icononly" >
        <text context="@title:menu">Main Toolbar</text>
        <Action name="go_back" />
        <Action name="go_forward" />
        <Action name="url_navigators" />
        <Action name="toggle_search" />
        <Action name="view_settings" />
        <Action name="hamburger_menu" />
    </ToolBar>"""


def dolphin_ui():
    """Dolphin's own dolphinui.rc with the rice toolbar: back/forward, the path, then search, view mode
    and the menu (split view stays on F3 and in the menu). The built-in file is a zstd-compressed Qt
    resource inside the binary; the copy keeps its version, so a Dolphin update that bumps it wins."""
    import re
    blob, best = Path("/usr/bin/dolphin").read_bytes(), (-1, "")
    i = blob.find(b"\x28\xb5\x2f\xfd")
    while i >= 0:
        xml = subprocess.run(["zstd", "-dcq"], input=blob[i:i + 400000], capture_output=True).stdout.decode(errors="replace")
        m = re.search(r'<gui name="dolphin" version="(\d+)"', xml)
        if m and 'ToolBar noMerge="1" name="mainToolBar" >' in xml and int(m.group(1)) > best[0]:
            best = (int(m.group(1)), xml)   # the desktop file (a phone layout with a bottom toolbar ships too)
        i = blob.find(b"\x28\xb5\x2f\xfd", i + 1)
    if best[0] < 0:
        return None
    return re.sub(r'    <ToolBar noMerge="1" name="mainToolBar" >.*?</ToolBar>', DOLPHIN_TOOLBAR, best[1], count=1, flags=re.S)


def setup():
    ui = dolphin_ui()
    if ui:
        write_if_changed(HOME / ".local/share/kxmlgui5/dolphin/dolphinui.rc", ui)
    kde_set("dolphinrc", {
        "General": {"ShowStatusBar": "Small", "ShowZoomSlider": False,
                    "ShowSelectionToggle": False},
        "IconsMode": {"PreviewSize": 96, "IconSize": 64},
    })
    kde_set("darklyrc", {"Style": {
        # the file view stays readable over a bright wallpaper; the sidebar shows more of the glass
        "DolphinViewOpacity": 72, "DolphinSidebarOpacity": 55,
        # the current tab gets a neutral lift, not a solid accent fill (accents are for state)
        "TabUseHighlightColor": False,
    }})


# ---------------------------------------------------------------- entry points
def apply(p):
    for fn in (apply_vscode, apply_btop, apply_mangohud, apply_zen, apply_fastfetch):
        try:
            fn(p)
        except Exception as e:  # one broken app must not stop the rest of the re-theme
            print(f"apps.py: {fn.__name__}: {e}", file=sys.stderr)


if __name__ == "__main__":
    pal = json.loads((HOME / ".local/state/rice/palette.json").read_text())
    if sys.argv[1:] == ["install-vscode"]:
        install_vscode(pal)
    elif sys.argv[1:] == ["setup"]:
        setup()
    elif sys.argv[1:] == ["konsole-chrome"]:
        konsole_chrome()
    else:
        apply(pal)
