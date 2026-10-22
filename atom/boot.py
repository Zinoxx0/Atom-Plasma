"""Power-on -> desktop in one look. Run on demand (uses sudo); rice.py doesn't call it, since a new
Plymouth theme means rebuilding the initramfs.

    boot.py limine [--dry-run]   Limine menu: the boot surface as wallpaper (centred, never stretched),
                                 menu colours from the current palette, branding, no help line, 2x font
                                 for the HiDPI panel. Only the header of /boot/limine.conf changes; the
                                 entries (and their blake2b hashes) stay byte-identical. --dry-run writes
                                 the candidate and a diff to ~/.cache/rice/boot/ and touches nothing.
    boot.py plymouth [--rebuild] installs theme "rice" in /usr/share/plymouth/themes/rice; --rebuild also
                                 selects it and runs limine-mkinitcpio (rebuilds the initramfs, re-pins
                                 its hashes in limine.conf)
    boot.py login                Plasma Login greeter: follows the theme from then on (installs a small
                                 system unit that copies what rice.py stages: wallpaper, colours, Plasma
                                 Style), Inter, the icon theme (settings icon_theme) and the session's
                                 cursor (system-wide if needed)
    boot.py greeter-sync         reinstalls only that copier and its (sandboxed) units
    boot.py preview              renders in ~/.cache/rice/shots/boot/, nothing installed

One fixed boot surface (BOOT: the neutral dark of the Plasma Style's popups) carries Limine and
Plymouth, so they never go stale against a new wallpaper and Limine -> Plymouth is seamless. Plymouth
and the Plasma splash share one layout (LAYOUT: the white Orbit mark, a neutral comet ring, a label below), so the
splash picks up where the boot screen left off and then lets each screen's wallpaper in.

Backups (first run only): /boot/limine.conf.pre-rice, /etc/plasmalogin.conf.pre-rice,
/var/lib/plasmalogin/.config/kdeglobals.pre-rice. Undo Plymouth with
`sudo plymouth-set-default-theme cachyos && sudo limine-mkinitcpio`.
"""
import difflib
import json
import math
import os
import pwd
import shutil
import socket
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from . import kde, palette, tokens, util
from .util import CACHE, HOME, ROOT

OUT = CACHE / "boot"
SHOTS = CACHE / "shots/boot"
LIMINE_CONF = Path("/boot/limine.conf")
PLY_DIR = Path("/usr/share/plymouth/themes/rice")
GREETER = Path("/var/lib/plasmalogin")
SPLASH_IMAGES = HOME / ".local/share/plasma/look-and-feel/com.zinoxx.rice/contents/splash/images"
FRAMES = 60


def inter(style="Medium"):
    """Inter's (file, face index): Inter.ttc holds every weight."""
    return util.font(f"Inter:style={style}")


def greeter_icons():
    """The greeter's icon theme: the desktop's (settings.json icon_theme)."""
    return util.settings().get("icon_theme", "breeze-dark")


def greeter_cursor():
    """The greeter's cursor theme: the session's (kcminputrc)."""
    return util.run("kreadconfig6", "--file", "kcminputrc", "--group", "Mouse", "--key", "cursorTheme",
                    "--default", "breeze_cursors").stdout.strip()


# the fixed boot surface (the Plasma Style's popup fill, a breath of light in the middle) and the layout
# Plymouth shares with the splash: design tokens, so Splash.qml reads the same ones (Tokens.boot, Tokens.bootLayout)
BOOT = tokens.TOKENS["boot"]
LAYOUT = tokens.TOKENS["bootLayout"]


def rgb(h):
    return tuple(round(c * 255) for c in palette.hex_rgb(h))


def display_name():
    """First word of the account's full name (GECOS), else the login name, as the shell's Account.qml."""
    pw = pwd.getpwuid(os.getuid())
    return (pw.pw_gecos.split(",")[0].split() or [pw.pw_name])[0]


def hostname():
    return util.run("hostnamectl", "hostname", quiet=True).stdout.strip() or socket.gethostname()


def sudo(*cmd, data=None):
    subprocess.run(["sudo", *cmd], input=data, check=True,
                   stdout=subprocess.DEVNULL if data is not None else None)


def sudo_read(path):
    return subprocess.run(["sudo", "cat", str(path)], check=True, capture_output=True, text=True).stdout


def sudo_write(path, text, owner=None, mode="644"):
    tmp = OUT / "tmp-write"
    tmp.write_text(text)
    args = ["install", "-m", mode] + (["-o", owner, "-g", owner] if owner else []) + [str(tmp), str(path)]
    sudo(*args)
    tmp.unlink()


def backup_once(path):
    sudo("sh", "-c", f'[ -e "{path}" ] && [ ! -e "{path}.pre-rice" ] && cp -a "{path}" "{path}.pre-rice" || true')


# ---------------------------------------------------------------- images
def backdrop(w, h):
    """The boot surface: neutral near-black, a soft lift in the middle, darker corners, dithered."""
    y, x = np.ogrid[:h, :w]
    d = np.hypot((x - w / 2) / (w / 2), (y - h / 2) / (h / 2)) / math.sqrt(2)      # 0 centre .. 1 corner
    base, glow = (np.array(rgb(BOOT[k]), dtype=float) for k in ("base", "glow"))
    t = np.clip(1 - d / 0.75, 0, 1) ** 2                                        # the lift fades out by 3/4
    arr = base + (glow - base) * t[..., None]
    arr *= (1 - 0.35 * np.clip((d - 0.6) / 0.4, 0, 1) ** 2)[..., None]          # corners sink a little
    # the outer band melts into the edge colour, so a centred copy on a larger screen has no seam
    edge = np.minimum(np.minimum(x, w - 1 - x) / w, np.minimum(y, h - 1 - y) / h)
    e = np.clip(1 - edge / 0.06, 0, 1) ** 2
    arr = arr * (1 - e[..., None]) + np.array(rgb(edge_colour()), dtype=float) * e[..., None]
    arr = arr + np.random.default_rng(7).uniform(-1.2, 1.2, (h, w, 1))          # dither: no banding
    return Image.fromarray(np.clip(arr, 0, 255).astype("uint8"))


def edge_colour():
    """What the backdrop's border settles to: Limine's backdrop around a centred image."""
    return "#%02x%02x%02x" % tuple(round(c * 0.65) for c in rgb(BOOT["base"]))


def spinner(size, sweep=270, k=4):
    """Comet ring, neutral: a faint full track plus an arc whose tail fades in towards a bright head."""
    n = size * k
    y, x = np.mgrid[:n, :n] + 0.5
    dx, dy = x - n / 2, y - n / 2
    w = n * LAYOUT["ring_w"] / LAYOUT["ring"]
    r = n / 2 - w
    band = np.abs(np.hypot(dx, dy) - r) <= w / 2
    t = ((np.degrees(np.arctan2(dy, dx)) + 90) % 360) / sweep        # 0 at 12 o'clock, clockwise
    head = math.radians(sweep - 90)
    cap = np.hypot(x - (n / 2 + r * math.cos(head)), y - (n / 2 + r * math.sin(head))) <= w / 2
    a = np.where(band & (t <= 1), np.clip(t, 0, 1) ** 1.8 * 0.92, 0.0)
    a = np.where(cap, 0.92, a)
    a = a + np.where(band, 0.10, 0.0) * (1 - a)                     # the track under it
    col = np.array(rgb(BOOT["fg"]), dtype=float)
    img = np.dstack([np.broadcast_to(col, (n, n, 3)), np.clip(a * 255, 0, 255)]).astype("uint8")
    return Image.fromarray(img, "RGBA").resize((size, size), Image.LANCZOS)


def label(text, px, colour, alpha=200, spacing=0.18):
    face, index = inter("Medium")
    font = ImageFont.truetype(face, px, index=index)
    gap = px * spacing
    widths = [font.getlength(ch) for ch in text]
    w = math.ceil(sum(widths) + gap * (len(text) - 1)) + 8
    img = Image.new("RGBA", (w, round(px * 1.5)), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    x = 4
    for ch, cw in zip(text, widths):
        d.text((x, px * 0.15), ch, font=font, fill=rgb(colour) + (alpha,))
        x += cw + gap
    return img


def pill(w, h, fill, outline=None, k=4):
    img = Image.new("RGBA", (w * k, h * k), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle((0, 0, w * k - 1, h * k - 1), radius=h * k // 2, fill=fill,
                                          outline=outline, width=k if outline else 0)
    return img.resize((w, h), Image.LANCZOS)


def mark(scale):
    """Atom Plasma's mark (qml/Rice/Emblem.qml, the launcher's Orbit), all white, rendered offscreen at
    `scale`. The software grab has no alpha, so it's drawn over black and over white and the alpha
    solved from the difference (its glow is translucent)."""
    d = OUT / "render"
    d.mkdir(parents=True, exist_ok=True)
    (d / "Rice").unlink(missing_ok=True)
    (d / "Rice").symlink_to(ROOT / "qml/Rice")
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl")
    shots = []
    for bg in ("black", "white"):
        out = d / f"mark-{scale}-{bg}.png"
        (d / "mark.qml").write_text("""import QtQuick
import QtQuick.Window
import "Rice"
Window {
    id: w
    width: Math.ceil(52 * %(s)s); height: width
    visible: true
    Rectangle { anchors.fill: parent; color: "%(bg)s" }
    Emblem { anchors.centerIn: parent; scale: %(s)s
             c1: "#ffffff"; c2: "#ffffff"; c3: "#ffffff"; c4: "#ffffff"; glow: "#ffffff" }
    Timer { interval: 600; running: true
            onTriggered: w.contentItem.grabToImage(r => { r.saveToFile("%(out)s"); Qt.quit() }) }
}
""" % {"s": scale, "bg": bg, "out": out})
        subprocess.run(["qml6", str(d / "mark.qml")], env=env, cwd=d, check=False, timeout=30,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        shots.append(np.asarray(Image.open(out).convert("RGB"), dtype=float))
    b, w = shots
    a = np.clip(255 - (w - b).mean(axis=2), 0, 255)
    c = np.clip(b * 255 / np.maximum(a, 1)[..., None], 0, 255)
    im = Image.fromarray(np.dstack([c, a]).astype("uint8"), "RGBA")
    return im.crop(im.getbbox())


# ---------------------------------------------------------------- Limine
LIMINE_KEYS = ("term_", "interface_", "wallpaper", "backdrop")
LIMINE_COMMENTS = ("# CachyOS Limine theme", "# Author: diegons490", "# Rice Limine theme", "# end Rice Limine theme")


def limine_block(p):
    hx = {k: v.lstrip("#") for k, v in p.items() if isinstance(v, str) and v.startswith("#")}
    norm = [hx["surface_high"], hx["red"], hx["green"], hx["yellow"], hx["blue"], hx["magenta"], hx["cyan"],
            hx["on_surface_variant"]]
    bright = [hx["outline"], hx["red_bright"], hx["green_bright"], hx["yellow_bright"], hx["blue_bright"],
              hx["magenta_bright"], hx["cyan_bright"], hx["on_surface"]]
    return [
        "# Rice Limine theme (generated by ~/.config/plasma-rice/boot.py; colours from "
        f"{Path(p['_wallpaper']).name})",
        "wallpaper: boot():/limine-rice.png",
        "wallpaper_style: centered",                     # the image is the screen's size or smaller: no stretch
        f"backdrop: {edge_colour().lstrip('#')}",        # ...and what shows around it matches its edge
        "term_palette: " + ";".join(norm),
        "term_palette_bright: " + ";".join(bright),
        "term_background: ff000000",                     # the backdrop shows through the menu
        f"term_foreground: {hx['on_surface']}",
        f"term_background_bright: {hx['surface_highest']}",
        f"term_foreground_bright: {hx['on_surface']}",
        "term_font_scale: 2x2",                          # 8x16 is tiny on the laptop's 15.6\" 1080p panel
        "term_margin: 160",
        "term_margin_gradient: 0",
        f"interface_branding: {display_name().lower()} @ {hostname().lower()}",
        f"interface_branding_colour: {hx['primary']}",
        "interface_help_hidden: yes",
        "# end Rice Limine theme",
    ]


def limine_conf(conf, block):
    """Swap the theme options in the global header; entries (from the first `/` line) stay byte-identical."""
    lines = conf.split("\n")
    first = next((i for i, l in enumerate(lines) if l.startswith("/")), len(lines))
    head, rest = lines[:first], lines[first:]
    keep = [l for l in head if not l.startswith(LIMINE_KEYS) and not l.startswith(LIMINE_COMMENTS)]
    at = next((i for i, l in enumerate(keep) if l.startswith("comment:")), len(keep))
    keep[at:at] = block + [""]
    out = []
    for l in keep:                      # no runs of blank lines
        if l == "" and out and out[-1] == "":
            continue
        out.append(l)
    return "\n".join(out + rest)


def apply_limine(p, dry=False):
    OUT.mkdir(parents=True, exist_ok=True)
    backdrop(1920, 1080).save(OUT / "limine-rice.png", optimize=True)
    conf = sudo_read(LIMINE_CONF)
    new = limine_conf(conf, limine_block(p))
    first = conf.index("\n/")
    assert new.endswith(conf[first:]), "entries changed"
    if dry:
        (OUT / "limine.conf.candidate").write_text(new)
        diff = "".join(difflib.unified_diff(conf.splitlines(True), new.splitlines(True),
                                            "/boot/limine.conf", "/boot/limine.conf (rice)"))
        (OUT / "limine.conf.diff").write_text(diff)
        print(diff or "limine: no change")
        print(f"limine (dry run): {OUT / 'limine.conf.candidate'}, {OUT / 'limine-rice.png'}")
        return
    backup_once(LIMINE_CONF)
    sudo("install", "-m", "755", str(OUT / "limine-rice.png"), "/boot/limine-rice.png")
    if new != conf:
        sudo_write(LIMINE_CONF, new, mode="755")
    print("limine: header themed, wallpaper /boot/limine-rice.png")


# ---------------------------------------------------------------- Plymouth
PLY_THEME = """[Plymouth Theme]
Name=Atom Plasma
Description=The Orbit mark and a comet ring on Atom Plasma's boot surface (generated by ~/.config/plasma-rice/boot.py)
ModuleName=script
# bundled into the initramfs as Plymouth.ttf, for prompt and message text
Font=Inter

[script]
ImageDir=/usr/share/plymouth/themes/rice
ScriptFile=/usr/share/plymouth/themes/rice/rice.script
"""

PLY_SCRIPT = """# Atom Plasma: generated by ~/.config/plasma-rice/boot.py. Do not edit.
# Layout matches the Plasma splash (Splash.qml): the Orbit mark, a comet ring, a label, all from the centre.
Window.SetBackgroundTopColor(%(bg)s);
Window.SetBackgroundBottomColor(%(bg)s);

W = Window.GetWidth();
H = Window.GetHeight();
X = Window.GetX();
Y = Window.GetY();
unit = H / 1080;
cx = X + W / 2;
cy = Y + H / 2;

background.sprite = Sprite(Image("background.png").Scale(W, H));
background.sprite.SetPosition(X, Y, -100);

# images come at 2x
mark.image = Image("mark.png");
mark.w = Math.Int(mark.image.GetWidth() * unit / 2);
mark.h = Math.Int(mark.image.GetHeight() * unit / 2);
mark.sprite = Sprite(mark.image.Scale(mark.w, mark.h));
mark.y = Math.Int(cy - %(mark_up)d * unit - mark.h / 2);
mark.sprite.SetPosition(Math.Int(cx - mark.w / 2), mark.y, 10);

size = Math.Int(%(ring)d * unit);
for (i = 0; i < %(frames)d; i++)
  frames[i] = Image("spinner-" + i + ".png").Scale(size, size);
spin.sprite = Sprite(frames[0]);
spin.sprite.SetPosition(Math.Int(cx - size / 2), Math.Int(cy + %(ring_y)d * unit - size / 2), 10);

label.image = Image("label.png");
label.w = Math.Int(label.image.GetWidth() * unit / 2);
label.h = Math.Int(label.image.GetHeight() * unit / 2);
label.sprite = Sprite(label.image.Scale(label.w, label.h));
label.sprite.SetPosition(Math.Int(cx - label.w / 2), Math.Int(cy + %(label_y)d * unit), 10);

fun ease (t)        # OutCubic, 0..1
  {
    if (t > 1) t = 1;
    u = 1 - t;
    return 1 - u * u * u;
  }

tick = 0;
status = "normal";
fun refresh_callback ()
  {
    global.tick++;
    k = ease(tick / 40);                      # ~0.8 s fade-in; the content rises 8 px into place
    background.sprite.SetOpacity(k);
    rise = Math.Int((1 - k) * 8 * unit);
    mark.sprite.SetY(mark.y + rise);
    mark.sprite.SetOpacity(k);
    label.sprite.SetOpacity(k * 0.85);
    if (status == "normal")
      {
        spin.sprite.SetImage(frames[Math.Int(tick * %(frames)d / 80) %% %(frames)d]);   # 1.6 s a turn
        spin.sprite.SetOpacity(k);
      }
    else
      spin.sprite.SetOpacity(0);
  }
Plymouth.SetRefreshFunction(refresh_callback);

#------------------------------------------------ text (prompts, messages)
fun text_image (str, alpha)
  {
    return Image.Text(str, %(fg)s, alpha, "Inter " + Math.Int(13 * unit));
  }

fun place_text (sprite, img, y)
  {
    sprite.SetImage(img);
    sprite.SetPosition(Math.Int(cx - img.GetWidth() / 2), Math.Int(y), 110);
  }

message.sprite = Sprite();
fun message_callback (text)
  {
    if (!text) return;
    place_text(message.sprite, text_image(text, 0.6), cy + %(label_y)d * unit + label.h + 18 * unit);
    message.sprite.SetOpacity(1);
  }
fun hide_message_callback (text)
  {
    message.sprite.SetOpacity(0);
  }
Plymouth.SetDisplayMessageFunction(message_callback);
Plymouth.SetHideMessageFunction(hide_message_callback);

#------------------------------------------------ password / question dialog
fun dialog_setup ()
  {
    local.box;
    box.image = Image("box.png");
    box.w = Math.Int(box.image.GetWidth() * unit / 2);
    box.h = Math.Int(box.image.GetHeight() * unit / 2);
    box.x = Math.Int(cx - box.w / 2);
    box.y = Math.Int(cy + %(box_y)d * unit - box.h / 2);     # below where the ring was
    box.sprite = Sprite(box.image.Scale(box.w, box.h));
    box.sprite.SetPosition(box.x, box.y, 100);
    global.dialog.box = box;
    global.dialog.prompt = Sprite();
    global.dialog.entry = Sprite();
    global.dialog.bullet_size = Math.Int(box.h * 0.22);
    global.dialog.bullet_image = Image("bullet.png").Scale(dialog.bullet_size, dialog.bullet_size);
  }

fun dialog_opacity (opacity)
  {
    dialog.box.sprite.SetOpacity(opacity);
    dialog.prompt.SetOpacity(opacity);
    dialog.entry.SetOpacity(opacity);
    for (index = 0; dialog.bullet[index]; index++)
      dialog.bullet[index].sprite.SetOpacity(0);
  }

fun dialog_show (prompt)
  {
    global.status = "dialog";
    if (!global.dialog)
      dialog_setup();
    dialog_opacity(1);
    label.sprite.SetOpacity(0);
    if (!prompt) prompt = "Password";
    place_text(dialog.prompt, text_image(prompt, 0.75), dialog.box.y - 30 * unit);
  }

fun display_normal_callback ()
  {
    global.status = "normal";
    if (global.dialog)
      {
        dialog_opacity(0);
        label.sprite.SetOpacity(0.85);
      }
  }

fun display_password_callback (prompt, bullets)
  {
    dialog_show(prompt);
    dialog.entry.SetOpacity(0);
    gap = dialog.bullet_size * 0.8;
    total = bullets * dialog.bullet_size + (bullets - 1) * gap;
    if (total > dialog.box.w - dialog.box.h) total = dialog.box.w - dialog.box.h;
    for (index = 0; dialog.bullet[index] || index < bullets; index++)
      {
        if (!dialog.bullet[index])
          dialog.bullet[index].sprite = Sprite(dialog.bullet_image);
        x = cx - total / 2 + index * (dialog.bullet_size + gap);
        dialog.bullet[index].sprite.SetPosition(Math.Int(x), Math.Int(dialog.box.y + dialog.box.h / 2 - dialog.bullet_size / 2), 101);
        if (index < bullets && x + dialog.bullet_size < dialog.box.x + dialog.box.w - dialog.box.h / 2)
          dialog.bullet[index].sprite.SetOpacity(1);
        else
          dialog.bullet[index].sprite.SetOpacity(0);
      }
  }

fun display_question_callback (prompt, entry)
  {
    dialog_show(prompt);
    for (index = 0; dialog.bullet[index]; index++)
      dialog.bullet[index].sprite.SetOpacity(0);
    if (!entry) return;
    img = text_image(entry, 0.95);
    dialog.entry.SetImage(img);
    dialog.entry.SetPosition(Math.Int(cx - img.GetWidth() / 2), Math.Int(dialog.box.y + dialog.box.h / 2 - img.GetHeight() / 2), 101);
    dialog.entry.SetOpacity(1);
  }

Plymouth.SetDisplayNormalFunction(display_normal_callback);
Plymouth.SetDisplayPasswordFunction(display_password_callback);
Plymouth.SetDisplayQuestionFunction(display_question_callback);

fun quit_callback ()
  {
    spin.sprite.SetOpacity(0);
  }
Plymouth.SetQuitFunction(quit_callback);
"""


def build_plymouth():
    d = OUT / "plymouth-rice"
    shutil.rmtree(d, ignore_errors=True)
    d.mkdir(parents=True)
    backdrop(1280, 720).save(d / "background.png", optimize=True)     # a smooth gradient: scales up cleanly, keeps the initramfs lean
    base = spinner(LAYOUT["ring"] * 2)
    for i in range(FRAMES):
        base.rotate(-i * 360 / FRAMES, resample=Image.BICUBIC).save(d / f"spinner-{i}.png", optimize=True)
    mark(LAYOUT["mark_scale"] * 2).save(d / "mark.png", optimize=True)
    label(hostname().lower(), 26, BOOT["muted"]).save(d / "label.png", optimize=True)
    pill(2 * 300, 2 * 44, rgb(BOOT["fill"]) + (240,), (255, 255, 255, 40)).save(d / "box.png", optimize=True)
    pill(32, 32, rgb(BOOT["fg"]) + (235,)).save(d / "bullet.png", optimize=True)
    bg = ", ".join(f"{c / 255:.3f}" for c in rgb(BOOT["base"]))
    fg = ", ".join(f"{c / 255:.3f}" for c in rgb(BOOT["fg"]))
    (d / "rice.script").write_text(PLY_SCRIPT % dict(LAYOUT, bg=bg, fg=fg, frames=FRAMES, mark_up=-LAYOUT["mark_y"]))
    (d / "rice.plymouth").write_text(PLY_THEME)
    # the splash draws the same backdrop and comet, so the boot screen hands over to it seamlessly
    SPLASH_IMAGES.mkdir(parents=True, exist_ok=True)
    shutil.copy(d / "background.png", SPLASH_IMAGES / "backdrop.png")
    shutil.copy(d / "spinner-0.png", SPLASH_IMAGES / "comet.png")
    return d


def apply_plymouth(rebuild=False):
    d = build_plymouth()
    sudo("rm", "-rf", str(PLY_DIR))
    sudo("cp", "-r", str(d), str(PLY_DIR))
    sudo("chmod", "-R", "u=rwX,go=rX", str(PLY_DIR))
    print(f"plymouth: theme files in {PLY_DIR}")
    if rebuild:
        sudo("plymouth-set-default-theme", "rice")
        print("plymouth: rebuilding the initramfs (limine-mkinitcpio) ...")
        sudo("limine-mkinitcpio")
        print("plymouth: done")
    else:
        print("plymouth: takes effect after `sudo plymouth-set-default-theme rice && sudo limine-mkinitcpio`")


# ---------------------------------------------------------------- login screen
def install_system(src, dst):
    """Copy a theme the greeter user can't read from ~ into /usr/share (replacing an older copy)."""
    if src.is_dir():
        sudo("rm", "-rf", str(dst))
        sudo("cp", "-rL", str(src), str(dst))
        sudo("chmod", "-R", "u=rwX,go=rX", str(dst))


# The login screen follows the theme. The greeter runs as its own user and can't read ~, so rice.py stages
# this theme's wallpaper (a light JPEG scaled to the biggest screen), colours and Plasma Style in
# ~/.local/state/rice/greeter/ on every change (stage_greeter), and a root-owned system unit that
# `boot.py login` installs copies them for the greeter whenever the stage's `stamp` changes. Nothing
# runs as root when the wallpaper changes, and the copier only takes plain files from that one folder.
STAGE = HOME / ".local/state/rice/greeter"
SYNC = Path("/usr/local/lib/atom-plasma/greeter-sync")
SYNC_SH = """#!/bin/sh
# Atom Plasma: copy the login screen's wallpaper, colours and Plasma Style, staged by rice.py in %(stage)s,
# to the Plasma Login greeter. Run by atom-plasma-greeter.service, which atom-plasma-greeter.path starts
# whenever the stage's stamp changes. Installed by %(home)s/.config/plasma-rice/boot.py login.
set -eu
SRC=%(stage)s
G=%(greeter)s
[ "$(realpath -e "$SRC")" = "$SRC" ] || exit 0            # the folder itself, not a link somewhere else
OWNER=$(stat -c %%u "$SRC"); GROUP=$(stat -c %%g "$SRC")   # the user who stages it
take() {    # plain files only, READ AS THAT USER: root never opens a path the user controls, so swapping a
            # file for a link between the check and the copy gets nothing the user couldn't read anyway
    [ -f "$SRC/$1" ] && [ ! -L "$SRC/$1" ] || return 0
    tmp=$(mktemp "$2.XXXXXX")
    if setpriv --reuid="$OWNER" --regid="$GROUP" --clear-groups cat -- "$SRC/$1" > "$tmp"; then
        chown plasmalogin:plasmalogin "$tmp" && chmod "$3" "$tmp" && mv -f "$tmp" "$2"
    else
        rm -f "$tmp"
    fi
}
install -d -o plasmalogin -g plasmalogin -m 755 "$G/wallpapers"
install -d -o plasmalogin -g plasmalogin -m 700 "$G/.config"
take wallpaper.jpg "$G/wallpapers/rice-login.jpg" 644
take kdeglobals "$G/.config/kdeglobals" 600
take plasmarc "$G/.config/plasmarc" 600
"""
UNIT_SERVICE = """[Unit]
Description=Atom Plasma: give the login screen the theme's wallpaper and colours

[Service]
Type=oneshot
ExecStart=%(sync)s
# root only to write into the greeter's home (the stage is read as its owner, see the script)
CapabilityBoundingSet=CAP_CHOWN CAP_FOWNER CAP_DAC_OVERRIDE CAP_SETUID CAP_SETGID
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/var/lib/plasmalogin
ProtectHome=read-only
PrivateTmp=yes
PrivateNetwork=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
RestrictAddressFamilies=AF_UNIX
RestrictNamespaces=yes
RestrictRealtime=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
SystemCallArchitectures=native
"""
UNIT_PATH = """[Unit]
Description=Atom Plasma: follow the theme on the login screen

[Path]
PathChanged=%(stage)s/stamp
Unit=atom-plasma-greeter.service

[Install]
WantedBy=multi-user.target
"""


def greeter_kdeglobals():
    """The greeter user's kdeglobals: the active KDE colour scheme, Inter, Darkly and the icon theme."""
    scheme = util.run("kreadconfig6", "--file", "kdeglobals", "--group", "General", "--key", "ColorScheme").stdout.strip()
    groups = kde.kde_read(HOME / f".local/share/color-schemes/{scheme}.colors")
    ui = tokens.TOKENS["font"]["ui"]
    groups.setdefault(("General",), {}).update({
        "ColorScheme": "Rice", "Name": "Atom Plasma",
        "font": f"{ui},10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1", "menuFont": f"{ui},10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1",
        "smallestReadableFont": f"{ui},8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1",
        "toolBarFont": f"{ui},10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"})
    groups.setdefault(("KDE",), {})["widgetStyle"] = "Darkly"
    groups[("Icons",)] = {"Theme": greeter_icons()}
    return "# Written by ~/.config/plasma-rice/boot.py\n" + kde.kde_dump(groups)


def stage_greeter(img, style="Rice"):
    """Stage the login screen's look for the copier (see STAGE): this wallpaper scaled down to cover the
    biggest screen (a JPEG instead of decoding a 15 MB PNG at every login), the colours, the Plasma Style.
    The stamp changes only when something did. Called by rice.py after every re-theme."""
    STAGE.mkdir(parents=True, exist_ok=True)
    changed = False
    src = f"{img}:{img.stat().st_mtime}"
    tag = STAGE / "wallpaper.src"
    if not (STAGE / "wallpaper.jpg").exists() or not tag.exists() or tag.read_text() != src:
        tmp = STAGE / "wallpaper.tmp.jpg"
        subprocess.run(["magick", f"{img}[0]", "-resize", "3840x2160^>", "-strip", "-quality", "92", str(tmp)],
                       check=True, timeout=60)
        tmp.replace(STAGE / "wallpaper.jpg")
        tag.write_text(src)
        changed = True
    for name, text in (("kdeglobals", greeter_kdeglobals()),
                       ("plasmarc", f"# Written by ~/.config/plasma-rice/boot.py\n[Theme]\nname={style}\n")):
        f = STAGE / name
        if not f.exists() or f.read_text() != text:
            f.write_text(text)
            changed = True
    if changed or not (STAGE / "stamp").exists():
        (STAGE / "stamp").write_text(f"{img}\n")
        (STAGE / "stamp").touch()
    return changed


def install_greeter_sync():
    """The root copier and its units: the part of `login` that keeps the greeter on the theme (`boot.py
    greeter-sync` reinstalls just this, e.g. after a change to SYNC_SH or the unit)."""
    sudo("install", "-d", "-m", "755", str(SYNC.parent))
    sudo_write(SYNC, SYNC_SH % {"stage": STAGE, "greeter": GREETER, "home": HOME}, mode="755")
    sudo_write("/etc/systemd/system/atom-plasma-greeter.service", UNIT_SERVICE % {"sync": SYNC})
    sudo_write("/etc/systemd/system/atom-plasma-greeter.path", UNIT_PATH % {"stage": STAGE})
    sudo("systemctl", "daemon-reload")
    sudo("systemctl", "enable", "--now", "atom-plasma-greeter.path")


def apply_login(p):
    """Plasma Login greeter: installs the copier that keeps it on the theme's wallpaper and colours (see
    STAGE), points the greeter at the copied wallpaper, installs the Plasma Styles, icons and cursor it
    needs system-wide, and copies the current look once."""
    stage_greeter(Path(p["_wallpaper"]), "Rice-Light" if p.get("_scheme") == "light" else "Rice")
    install_greeter_sync()

    walls = GREETER / "wallpapers"
    sudo("sh", "-c", f'rm -f "{walls}"/rice-login.png "{walls}"/rice-login.jpeg')     # older copies
    conf = "/etc/plasmalogin.conf"
    backup_once(conf)
    kw = ["kwriteconfig6", "--file", conf, "--group", "Greeter"]
    sudo(*kw, "--key", "WallpaperPluginId", "org.kde.image")
    for key in ("Image", "PreviewImage"):
        sudo(*kw, "--group", "Wallpaper", "--group", "org.kde.image", "--group", "General", "--key", key,
             f"file://{walls}/rice-login.jpg")

    # the Plasma Styles and themes the greeter needs, where the greeter user can read them
    for style in ("Rice", "Rice-Light"):
        install_system(HOME / ".local/share/plasma/desktoptheme" / style, Path("/usr/share/plasma/desktoptheme") / style)
    icons_theme, cursor = greeter_icons(), greeter_cursor()
    for name in (icons_theme, cursor):
        if not (Path("/usr/share/icons") / name).is_dir():
            install_system(HOME / ".local/share/icons" / name, Path("/usr/share/icons") / name)
    if icons_theme == "Papirus-Rice":     # icons.py regenerates the local copy; keep the system one in step
        install_system(HOME / ".local/share/icons/Papirus-Rice", Path("/usr/share/icons/Papirus-Rice"))
    cfg = GREETER / ".config"
    backup_once(cfg / "kdeglobals")
    sudo_write(cfg / "kcminputrc", f"[Mouse]\ncursorSize=24\ncursorTheme={cursor}\n",
               owner="plasmalogin", mode="600")
    sudo(str(SYNC))
    print(f"login: follows the theme (atom-plasma-greeter.path), now {Path(p['_wallpaper']).name}; "
          f"{icons_theme}, {cursor}")


# ---------------------------------------------------------------- preview
def plymouth_frame(d, w, h, tick, dialog=None, message=None):
    """What rice.script draws at `tick` (50 per s), composited the same way, for checking without a reboot."""
    unit = h / 1080
    cx, cy = w / 2, h / 2
    k = 1 - (1 - min(1, tick / 40)) ** 3
    base = Image.new("RGBA", (w, h), rgb(BOOT["base"]) + (255,))
    bg = Image.open(d / "background.png").convert("RGBA").resize((w, h), Image.BICUBIC)
    bg.putalpha(round(255 * k))
    base.alpha_composite(bg)

    def put(img, x, y, alpha):
        if alpha <= 0:
            return
        img = img.copy()
        img.putalpha(img.getchannel("A").point(lambda v: round(v * alpha)))
        base.alpha_composite(img, (round(x), round(y)))

    def scaled(name, f=0.5):
        im = Image.open(d / name).convert("RGBA")
        return im.resize((round(im.width * unit * f), round(im.height * unit * f)), Image.LANCZOS)
    mk = scaled("mark.png")
    put(mk, cx - mk.width / 2, cy + LAYOUT["mark_y"] * unit - mk.height / 2 + (1 - k) * 8 * unit, k)
    lb = scaled("label.png")
    face, index = inter("Regular")
    font = ImageFont.truetype(face, round(13 * unit), index=index)          # Inter Regular, as Plymouth.ttf

    def text(s, alpha):
        im = Image.new("RGBA", (round(font.getlength(s)) + 4, round(13 * unit * 1.4)), (0, 0, 0, 0))
        ImageDraw.Draw(im).text((2, 0), s, font=font, fill=rgb(BOOT["fg"]) + (round(255 * alpha),))
        return im
    if dialog is None:
        size = round(LAYOUT["ring"] * unit)
        sp = Image.open(d / f"spinner-{int(tick * FRAMES / 80) % FRAMES}.png").convert("RGBA").resize((size, size), Image.LANCZOS)
        put(sp, cx - size / 2, cy + LAYOUT["ring_y"] * unit - size / 2, k)
        put(lb, cx - lb.width / 2, cy + LAYOUT["label_y"] * unit, k * 0.85)
    else:
        prompt, bullets = dialog
        bx = scaled("box.png")
        by = cy + LAYOUT["box_y"] * unit - bx.height / 2
        put(bx, cx - bx.width / 2, by, 1)
        pt = text(prompt, 0.75)
        put(pt, cx - pt.width / 2, by - 30 * unit, 1)
        bs = round(bx.height * 0.22)
        bu = Image.open(d / "bullet.png").convert("RGBA").resize((bs, bs), Image.LANCZOS)
        gap = bs * 0.8
        total = bullets * bs + (bullets - 1) * gap
        for i in range(bullets):
            put(bu, cx - total / 2 + i * (bs + gap), by + bx.height / 2 - bs / 2, 1)
    if message:
        mt = text(message, 0.6)
        put(mt, cx - mt.width / 2, cy + LAYOUT["label_y"] * unit + lb.height + 18 * unit, 1)
    return base.convert("RGB")


def preview(p):
    SHOTS.mkdir(parents=True, exist_ok=True)
    d = build_plymouth()
    w, h = 1920, 1080
    frames = [plymouth_frame(d, w, h, t) for t in (6, 14, 24, 60)]
    strip = Image.new("RGB", (w * 2 + 16, h * 2 + 16), "black")
    for i, f in enumerate(frames):
        strip.paste(f, ((i % 2) * (w + 16), (i // 2) * (h + 16)))
    strip.resize((strip.width // 2, strip.height // 2), Image.LANCZOS).save(SHOTS / "plymouth-fade-in.png")
    frames[-1].save(SHOTS / "plymouth-1080p.png")
    plymouth_frame(d, 3840, 2160, 60).resize((1920, 1080), Image.LANCZOS).save(SHOTS / "plymouth-4k-downscaled.png")
    plymouth_frame(d, w, h, 60, dialog=("Please enter passphrase for disk root", 9)).save(SHOTS / "plymouth-password.png")
    plymouth_frame(d, w, h, 60, message="Checking file system on /dev/nvme0n1p2").save(SHOTS / "plymouth-message.png")
    # Limine mock: the boot surface, centred, the menu in the terminal area (2x font = 16x32 cells)
    lim = Image.open(OUT / "limine-rice.png").convert("RGB") if (OUT / "limine-rice.png").exists() else backdrop(w, h)
    dr = ImageDraw.Draw(lim)
    mono = ImageFont.truetype(util.font("JetBrainsMono Nerd Font:style=Regular")[0], 26)
    blk = {l.split(": ", 1)[0]: l.split(": ", 1)[1] for l in limine_block(p) if ": " in l and not l.startswith("#")}
    brand = "#" + blk["interface_branding_colour"]
    pal = blk["term_palette"].split(";")
    tw = dr.textlength(blk["interface_branding"], font=mono)
    dr.text(((w - tw) / 2, 40), blk["interface_branding"], font=mono, fill=brand)
    y = 160
    entries = ["CachyOS", "  linux-cachyos", "  linux-cachyos-lts", "  Snapshots"]
    for i, e in enumerate(entries):
        if i == 1:
            dr.rectangle((160, y - 2, w - 160, y + 32), fill="#" + blk["term_background_bright"])
        dr.text((176, y), e, font=mono, fill="#" + blk["term_foreground"] if i != 1 else "#" + pal[7])
        y += 34
    lim.save(SHOTS / "limine-mock.png")
    print(SHOTS)


def main(args):
    p = json.loads((util.STATE / "palette.json").read_text())
    what = args[0] if args else "preview"
    OUT.mkdir(parents=True, exist_ok=True)
    if what == "preview":
        return preview(p)
    if what == "limine":
        return apply_limine(p, dry="--dry-run" in args)
    if what == "login":
        return apply_login(p)
    if what == "greeter-sync":
        return install_greeter_sync()
    if what == "plymouth":
        return apply_plymouth(rebuild="--rebuild" in args)
    sys.exit(__doc__)

