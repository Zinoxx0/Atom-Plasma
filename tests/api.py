"""The functions the tests check, by name, wherever they live: when code moves, only this file changes,
and the saved outputs in tests/golden/ must still match."""
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(ROOT), str(ROOT / "panel")]

import apps  # noqa: E402
import boot  # noqa: E402
import build as panel  # noqa: E402
import layout  # noqa: E402
import palette  # noqa: E402
import rgb  # noqa: E402
import rice  # noqa: E402
import tokens  # noqa: E402


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


style = _load("plasma_style_build", ROOT / "plasma-style/build.py")

# palette
analyse = palette.analyse
mood_of = palette.mood_of
build_v2 = palette.build_v2
MOODS = palette.MOODS
# apps and terminals
ansi = apps.ansi
vscode = apps.vscode
btop = apps.btop
mangohud = apps.mangohud
zen_chrome = apps.zen_chrome
zen_content = apps.zen_content
zen_userjs = apps.zen_userjs
kde_scheme = rice.kde_scheme
konsole = rice.konsole
konsole_tabs = rice.konsole_tabs
alacritty = rice.alacritty
# placement and screens
place = layout.place
rim = rice.rim
media_screen = rice.media_screen
scale_for = rice.scale_for
theme_args = rice.theme_args
unusable = rice.unusable
# design tokens, boot, bar islands, keyboards
tokens_qml = tokens.qml
limine_conf = boot.limine_conf
island_style = panel.island_style
launcher_style = panel.launcher_style
vivid = rgb.vivid
led = rgb.led
key_frame = rgb.frame


def render_templates(p, out_dir):
    """rice.py's templates (starship, the shell colours) for palette `p`, written into out_dir."""
    saved = dict(rice.TEMPLATES)
    try:
        for name in rice.TEMPLATES:
            rice.TEMPLATES[name] = Path(out_dir) / name
        rice.render_templates(p)
    finally:
        rice.TEMPLATES.clear()
        rice.TEMPLATES.update(saved)


def fill(text, p, extra=None):
    """The fastfetch template filler ({{name}}, {{name:rgb}}, extra values)."""
    return apps.fill(text, p, extra)


def build_style(variant, out_dir):
    """The Plasma Style `variant` (dark | light), generated into out_dir/<its folder>."""
    saved = style.OUT
    try:
        style.OUT = Path(out_dir) / "Rice"
        style.build(variant)
        return style.OUT
    finally:
        style.OUT = saved
