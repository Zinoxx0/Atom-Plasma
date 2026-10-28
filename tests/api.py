"""The functions the tests check, by name, wherever they live: when code moves, only this file changes,
and the saved outputs in tests/golden/ must still match."""
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import rgb  # noqa: E402
from atom import (apps, boot, kde, layout, palette, panel, screens, style, terminals,  # noqa: E402
                  theme, tokens, util, vscode, walls)


def _script(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


update_check = _script("update_check", "update-check.py")
clawd_intent = _script("clawd_intent", "clawd-intent.py")

# palette
analyse = palette.analyse
mood_of = palette.mood_of
build_v2 = palette.build_v2
MOODS = palette.MOODS
# apps and terminals (the terminal look as designed, not as settings.json has it today)
ansi = terminals.ansi
vscode = vscode.vscode
btop = apps.btop
mangohud = lambda p: apps.mangohud(p, "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-SemiBold.ttf")  # noqa: E731
zen_chrome = apps.zen_chrome
zen_content = apps.zen_content
zen_userjs = apps.zen_userjs
kde_scheme = kde.kde_scheme
konsole = lambda p: terminals.konsole(p, terminals.LOOK)  # noqa: E731
konsole_tabs = lambda p: terminals.konsole_tabs(p, terminals.LOOK)  # noqa: E731
alacritty = lambda p: terminals.alacritty(p, terminals.LOOK)  # noqa: E731
# placement and screens
place = layout.place
rim = screens.rim
media_screen = screens.media_screen
theme_args = theme.theme_args
unusable = walls.unusable
# design tokens, boot, bar islands, keyboards
tokens_qml = tokens.qml
limine_conf = boot.limine_conf
island_style = panel.island_style
launcher_style = panel.launcher_style
vivid = rgb.vivid
led = rgb.led
key_frame = rgb.frame
# the update check
must_check = update_check.must_check
advisories = update_check.advisories
update_prompt = update_check.build_prompt
update_report = update_check.render_report
notice_keys = update_check.notice_keys
notified = update_check.told
# what Claude's answer was about, for Clawd
answer_kind = clawd_intent.classify


def render_templates(p, out_dir):
    """rice.py's templates (starship, the shell colours) for palette `p`, written into out_dir."""
    saved = dict(theme.TEMPLATES)
    try:
        for name in theme.TEMPLATES:
            theme.TEMPLATES[name] = Path(out_dir) / name
        theme.render_templates(p)
    finally:
        theme.TEMPLATES.clear()
        theme.TEMPLATES.update(saved)


def fill(text, p, extra=None):
    """The template filler ({{name}}, {{name.rgb}}; extra values win over the palette)."""
    return util.fill(text, dict(p, **(extra or {})))


def build_style(variant, out_dir):
    """The Plasma Style `variant` (dark | light), generated into out_dir/<its folder>."""
    return style.build(variant, out_dir)
