"""VS Code's "Rice" colour theme, from the wallpaper palette: a local extension (zinoxx.rice-theme)
whose theme file is contributed with "_watch": true, so VS Code reloads it live when it's rewritten."""
import json
import subprocess
import zipfile

from . import palette, terminals, util
from .util import HOME


def alpha(h, a):
    return h + f"{round(a * 255):02x}"


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
        "button.background": pr, "button.foreground": p["on_primary"], "button.hoverBackground": palette.mix(pr, fg, 0.25),
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
        "extensionButton.prominentHoverBackground": palette.mix(pr, fg, 0.25), "extensionBadge.remoteBackground": pr,
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

    punct = palette.mix(fgv, mut, 0.45)
    tokens = [
        {"settings": {"foreground": fg, "background": bg}},
        tok(["comment", "punctuation.definition.comment", "string.comment"], mut, "italic"),
        tok(["comment.block.documentation", "comment.line.documentation"], palette.mix(mut, fgv, 0.25), "italic"),
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
    for n, (norm, bright) in terminals.term(p).items():
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
        util.write_if_changed(d / "themes/rice-color-theme.json", text)


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
