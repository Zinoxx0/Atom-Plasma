#!/usr/bin/env python3
"""Boot -> login look from the current wallpaper palette. Run on demand (uses sudo);
rice.py doesn't call it, since a new Plymouth theme means rebuilding the initramfs.

    boot.py [all|limine|plymouth|login|preview]

    limine    /boot/limine-rice.png (blurred, dimmed wallpaper) + palette in the /boot/limine.conf
              header (everything below the header, i.e. the entries, is left untouched)
    plymouth  theme "rice" in /usr/share/plymouth/themes/rice: the same backdrop, so Limine ->
              Plymouth is seamless, with an accent "comet" spinner; then `limine-mkinitcpio`
              rebuilds the initramfs and re-pins its hashes in limine.conf
    login     Plasma Login Manager greeter: wallpaper + Rice colours, Inter, Papirus-Dark, Simp1e cursor
    preview   mock-ups in ~/.cache/rice/boot/preview-*.png, nothing installed

Backups (first run only): /boot/limine.conf.pre-rice, /etc/plasmalogin.conf.pre-rice,
/var/lib/plasmalogin/.config/kdeglobals.pre-rice. Undo Plymouth with
`sudo plymouth-set-default-theme cachyos && sudo limine-mkinitcpio`.
"""
import json
import math
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import palette  # noqa: E402

HOME = Path.home()
OUT = HOME / ".cache/rice/boot"
INTER = ("/usr/share/fonts/inter/Inter.ttc", 10)          # Inter Medium
LIMINE_CONF = Path("/boot/limine.conf")
PLY_DIR = Path("/usr/share/plymouth/themes/rice")
GREETER = Path("/var/lib/plasmalogin")
FRAMES = 48


def rgb(h):
    return tuple(round(c * 255) for c in palette.hex_rgb(h))


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
    sudo("sh", "-c", f'[ -e "{path}.pre-rice" ] || cp -a "{path}" "{path}.pre-rice"')


# ---------------------------------------------------------------- images
def backdrop(p, w, h):
    """The wallpaper, blurred and pulled toward the darkest surface, with a vignette."""
    im = Image.open(p["_wallpaper"]).convert("RGB")
    s = max(w / im.width, h / im.height)
    im = im.resize((max(w, round(im.width * s)), max(h, round(im.height * s))), Image.LANCZOS)
    left, top = (im.width - w) // 2, (im.height - h) // 2
    im = im.crop((left, top, left + w, top + h)).filter(ImageFilter.GaussianBlur(w / 60))
    im = Image.blend(im, Image.new("RGB", (w, h), rgb(p["surface_lowest"])), 0.5)
    y, x = np.ogrid[:h, :w]
    d = np.hypot((x - w / 2) / (w / 2), (y - h / 2) / (h / 2)) / math.sqrt(2)
    a = (np.clip((d - 0.3) / 0.7, 0, 1) ** 1.5 * 0.8)[..., None]
    dark = np.array(rgb(p["surface_lowest"]), dtype=float) * 0.5
    arr = np.asarray(im, dtype=float) * (1 - a) + dark * a
    arr += np.random.default_rng(7).uniform(-1.5, 1.5, arr.shape)   # dither: no banding in the blur
    return Image.fromarray(np.clip(arr, 0, 255).astype("uint8"))


def spinner(p, size=160, sweep=280):
    """Comet ring: a faint track plus an arc fading from tertiary (tail) to primary (head)."""
    k = 4
    n = size * k
    y, x = np.mgrid[:n, :n] + 0.5
    dx, dy = x - n / 2, y - n / 2
    r = n / 2 - n * 0.07
    w = n * 0.09
    band = np.abs(np.hypot(dx, dy) - r) <= w / 2
    t = ((np.degrees(np.arctan2(dy, dx)) + 90) % 360) / sweep    # 0 at 12 o'clock, clockwise
    arc = band & (t <= 1)
    head = math.radians(sweep - 90)
    cap = np.hypot(x - (n / 2 + r * math.cos(head)), y - (n / 2 + r * math.sin(head))) <= w / 2
    a = np.where(arc, np.clip(t, 0, 1) ** 1.6, 0.0)
    a = np.where(cap, 1.0, a)
    c0, c1 = (np.array(rgb(p[k_]), dtype=float) for k_ in ("tertiary", "primary"))
    col = c0 + (c1 - c0) * np.clip(t, 0, 1)[..., None]
    col = np.where(cap[..., None], c1, col)
    track_a = np.where(band, 0.09, 0.0)
    track_c = np.array(rgb(p["on_surface"]), dtype=float)
    out_a = a + track_a * (1 - a)
    out_c = (col * a[..., None] + track_c * (track_a * (1 - a))[..., None]) / np.maximum(out_a, 1e-6)[..., None]
    img = np.dstack([np.clip(out_c, 0, 255), np.clip(out_a * 255, 0, 255)]).astype("uint8")
    return Image.fromarray(img, "RGBA").resize((size, size), Image.LANCZOS)


def label(p, text, px=40, spacing=0.18):
    font = ImageFont.truetype(INTER[0], px, index=INTER[1])
    gap = px * spacing
    widths = [font.getlength(ch) for ch in text]
    w = math.ceil(sum(widths) + gap * (len(text) - 1)) + 8
    img = Image.new("RGBA", (w, round(px * 1.5)), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    x = 4
    col = rgb(p["on_surface_variant"]) + (190,)
    for ch, cw in zip(text, widths):
        d.text((x, px * 0.15), ch, font=font, fill=col)
        x += cw + gap
    return img


def pill(w, h, fill, outline=None, k=4):
    img = Image.new("RGBA", (w * k, h * k), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle((0, 0, w * k - 1, h * k - 1), radius=h * k // 2, fill=fill,
                                          outline=outline, width=2 * k if outline else 0)
    return img.resize((w, h), Image.LANCZOS)


# ---------------------------------------------------------------- Limine
LIMINE_KEYS = ("term_", "interface_", "wallpaper", "backdrop")
LIMINE_COMMENTS = ("# CachyOS Limine theme", "# Author: diegons490", "# Rice Limine theme", "# end Rice Limine theme")


def limine_block(p):
    hx = {k: v.lstrip("#") for k, v in p.items() if isinstance(v, str) and v.startswith("#")}
    norm = [hx["surface_high"], hx["red"], hx["green"], hx["yellow"], hx["blue"], hx["magenta"], hx["cyan"],
            hx["on_surface_variant"]]
    bright = [hx["outline"], hx["red_bright"], hx["green_bright"], hx["yellow_bright"], hx["blue_bright"],
              hx["magenta_bright"], hx["cyan_bright"], hx["on_surface"]]
    host = subprocess.run(["hostnamectl", "hostname"], capture_output=True, text=True).stdout.strip() or "Thorfinn"
    return [
        f"# Rice Limine theme (generated by ~/.config/plasma-rice/boot.py from {Path(p['_wallpaper']).name})",
        "wallpaper: boot():/limine-rice.png",
        "wallpaper_style: stretched",
        f"backdrop: {hx['surface_lowest']}",
        "term_palette: " + ";".join(norm),
        "term_palette_bright: " + ";".join(bright),
        f"term_background: 50{hx['surface_lowest']}",
        f"term_foreground: {hx['on_surface']}",
        f"term_background_bright: {hx['surface_highest']}",
        f"term_foreground_bright: {hx['on_surface']}",
        "term_margin: 192",
        "term_margin_gradient: 40",
        f"interface_branding: {host}",
        f"interface_branding_colour: {hx['primary']}",
        f"interface_help_colour: {hx['muted']}",
        f"interface_help_colour_bright: {hx['primary']}",
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


def apply_limine(p):
    OUT.mkdir(parents=True, exist_ok=True)
    backdrop(p, 1920, 1080).save(OUT / "limine-rice.png", optimize=True)
    conf = sudo_read(LIMINE_CONF)
    new = limine_conf(conf, limine_block(p))
    first = conf.index("\n/")
    assert new.endswith(conf[first:]), "entries changed"
    backup_once(LIMINE_CONF)
    sudo("install", "-m", "755", str(OUT / "limine-rice.png"), "/boot/limine-rice.png")
    if new != conf:
        sudo_write(LIMINE_CONF, new, mode="755")
    print("limine: header themed, wallpaper /boot/limine-rice.png")


# ---------------------------------------------------------------- Plymouth
PLY_THEME = """[Plymouth Theme]
Name=Rice
Description=Wallpaper backdrop + accent spinner (generated by ~/.config/plasma-rice/boot.py)
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/rice
ScriptFile=/usr/share/plymouth/themes/rice/rice.script
"""

PLY_SCRIPT = """# Rice: generated by ~/.config/plasma-rice/boot.py. Do not edit.
Window.SetBackgroundTopColor(%(bg)s);
Window.SetBackgroundBottomColor(%(bg)s);

W = Window.GetWidth();
H = Window.GetHeight();
X = Window.GetX();
Y = Window.GetY();
unit = H / 1080;

background.sprite = Sprite(Image("background.png").Scale(W, H));
background.sprite.SetPosition(X, Y, -100);

size = Math.Int(64 * unit);
for (i = 0; i < %(frames)d; i++)
  {
    frames[i] = Image("spinner-" + i + ".png").Scale(size, size);
  }
spin.sprite = Sprite(frames[0]);
spin.x = Math.Int(X + W / 2 - size / 2);
spin.y = Math.Int(Y + H / 2 - size / 2);
spin.sprite.SetPosition(spin.x, spin.y, 10);

label.image = Image("label.png");
label.w = Math.Int(label.image.GetWidth() * unit / 2);
label.h = Math.Int(label.image.GetHeight() * unit / 2);
label.sprite = Sprite(label.image.Scale(label.w, label.h));
label.sprite.SetPosition(Math.Int(X + W / 2 - label.w / 2), Math.Int(spin.y + size + 26 * unit), 10);

state.tick = 0;
state.frame = 0;
status = "normal";

fun refresh_callback ()
  {
    state.tick++;
    fade = state.tick / 35;
    if (fade > 1)
      fade = 1;
    background.sprite.SetOpacity(fade);
    label.sprite.SetOpacity(fade * 0.9);
    if (status == "normal")
      {
        state.frame++;
        if (state.frame >= %(frames)d)
          state.frame = 0;
        spin.sprite.SetImage(frames[state.frame]);
        spin.sprite.SetOpacity(fade);
      }
    else
      spin.sprite.SetOpacity(0);
  }
Plymouth.SetRefreshFunction(refresh_callback);

#------------------------------------------------ password dialog
fun dialog_setup ()
  {
    local.box;
    box.image = Image("box.png");
    box.w = Math.Int(box.image.GetWidth() * unit / 2);
    box.h = Math.Int(box.image.GetHeight() * unit / 2);
    box.x = Math.Int(X + W / 2 - box.w / 2);
    box.y = Math.Int(Y + H / 2 - box.h / 2);
    box.sprite = Sprite(box.image.Scale(box.w, box.h));
    box.sprite.SetPosition(box.x, box.y, 100);
    global.dialog.box = box;
    global.dialog.bullet_size = Math.Int(box.h * 0.3);
    global.dialog.bullet_image = Image("bullet.png").Scale(dialog.bullet_size, dialog.bullet_size);
  }

fun dialog_opacity (opacity)
  {
    dialog.box.sprite.SetOpacity(opacity);
    for (index = 0; dialog.bullet[index]; index++)
      dialog.bullet[index].sprite.SetOpacity(opacity);
  }

fun display_normal_callback ()
  {
    global.status = "normal";
    if (global.dialog)
      dialog_opacity(0);
  }

fun display_password_callback (prompt, bullets)
  {
    global.status = "password";
    if (!global.dialog)
      dialog_setup();
    else
      dialog_opacity(1);
    gap = dialog.bullet_size * 0.7;
    for (index = 0; dialog.bullet[index] || index < bullets; index++)
      {
        if (!dialog.bullet[index])
          {
            dialog.bullet[index].sprite = Sprite(dialog.bullet_image);
            dialog.bullet[index].sprite.SetPosition(Math.Int(dialog.box.x + dialog.box.h * 0.6 + index * (dialog.bullet_size + gap)),
                                                    Math.Int(dialog.box.y + dialog.box.h / 2 - dialog.bullet_size / 2), 101);
          }
        if (index < bullets)
          dialog.bullet[index].sprite.SetOpacity(1);
        else
          dialog.bullet[index].sprite.SetOpacity(0);
      }
  }

Plymouth.SetDisplayNormalFunction(display_normal_callback);
Plymouth.SetDisplayPasswordFunction(display_password_callback);

fun quit_callback ()
  {
    spin.sprite.SetOpacity(0);
  }
Plymouth.SetQuitFunction(quit_callback);
"""


def build_plymouth(p):
    d = OUT / "plymouth-rice"
    shutil.rmtree(d, ignore_errors=True)
    d.mkdir(parents=True)
    backdrop(p, 1280, 720).save(d / "background.png", optimize=True)   # blurred, so upscaling is invisible
    base = spinner(p)
    for i in range(FRAMES):
        base.rotate(-i * 360 / FRAMES, resample=Image.BICUBIC).save(d / f"spinner-{i}.png", optimize=True)
    host = subprocess.run(["hostnamectl", "hostname"], capture_output=True, text=True).stdout.strip() or "thorfinn"
    label(p, host.lower()).save(d / "label.png", optimize=True)
    sl = rgb(p["surface_low"])
    pill(560, 72, sl + (235,), rgb(p["outline_variant"]) + (255,)).save(d / "box.png", optimize=True)
    pill(32, 32, rgb(p["primary"]) + (255,)).save(d / "bullet.png", optimize=True)
    bg = ", ".join(f"{c / 255:.3f}" for c in rgb(p["surface_lowest"]))
    (d / "rice.script").write_text(PLY_SCRIPT % {"bg": bg, "frames": FRAMES})
    (d / "rice.plymouth").write_text(PLY_THEME)
    return d


def apply_plymouth(p):
    d = build_plymouth(p)
    sudo("rm", "-rf", str(PLY_DIR))
    sudo("cp", "-r", str(d), str(PLY_DIR))
    sudo("chmod", "-R", "u=rwX,go=rX", str(PLY_DIR))
    sudo("plymouth-set-default-theme", "rice")
    print("plymouth: theme installed; rebuilding the initramfs (limine-mkinitcpio) ...")
    sudo("limine-mkinitcpio")
    print("plymouth: done")


# ---------------------------------------------------------------- login screen
def ini_parse(text):
    groups, cur = {}, None
    for line in text.splitlines():
        if line.startswith("[") and line.rstrip().endswith("]"):
            cur = groups.setdefault(line.strip(), {})
        elif cur is not None and "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            cur[k] = v
    return groups


def ini_dump(groups):
    return "\n".join(f"{g}\n" + "".join(f"{k}={v}\n" for k, v in kv.items()) for g, kv in groups.items())


def apply_login(p):
    img = Path(p["_wallpaper"])
    walls = GREETER / "wallpapers"
    dst = walls / ("rice-login" + img.suffix.lower())
    sudo("install", "-d", "-o", "plasmalogin", "-g", "plasmalogin", "-m", "755", str(walls))
    sudo("sh", "-c", f'rm -f "{walls}"/rice-login.*')
    sudo("install", "-o", "plasmalogin", "-g", "plasmalogin", "-m", "644", str(img), str(dst))
    conf = "/etc/plasmalogin.conf"
    backup_once(conf)
    kw = ["kwriteconfig6", "--file", conf, "--group", "Greeter"]
    sudo(*kw, "--key", "WallpaperPluginId", "org.kde.image")
    for key in ("Image", "PreviewImage"):
        sudo(*kw, "--group", "Wallpaper", "--group", "org.kde.image", "--group", "General", "--key", key, f"file://{dst}")

    # colours, fonts, icons and cursor for the greeter user (it can't read ~/.local/share)
    scheme = subprocess.run(["kreadconfig6", "--file", "kdeglobals", "--group", "General", "--key", "ColorScheme"],
                            capture_output=True, text=True).stdout.strip()
    groups = ini_parse((HOME / f".local/share/color-schemes/{scheme}.colors").read_text())
    groups.setdefault("[General]", {}).update({
        "ColorScheme": "Rice", "Name": "Rice",
        "font": "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1", "menuFont": "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1",
        "smallestReadableFont": "Inter,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1",
        "toolBarFont": "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"})
    groups.setdefault("[KDE]", {})["widgetStyle"] = "Darkly"
    groups["[Icons]"] = {"Theme": "Papirus-Dark"}
    kdeglobals = GREETER / ".config/kdeglobals"
    backup_once(kdeglobals)
    sudo_write(kdeglobals, "# Written by ~/.config/plasma-rice/boot.py\n" + ini_dump(groups),
               owner="plasmalogin", mode="600")
    inputrc = GREETER / ".config/kcminputrc"
    sudo_write(inputrc, "[Mouse]\ncursorSize=24\ncursorTheme=Simp1e-Tokyo-Night\n", owner="plasmalogin", mode="600")
    print(f"login: greeter wallpaper {dst.name}, Rice colours, Inter, Papirus-Dark, Simp1e cursor")


# ---------------------------------------------------------------- preview
def preview(p):
    OUT.mkdir(parents=True, exist_ok=True)
    d = build_plymouth(p)
    w, h = 1920, 1080
    bg = Image.open(d / "background.png").convert("RGBA").resize((w, h), Image.BICUBIC)
    sp = Image.open(d / "spinner-0.png").resize((58, 58), Image.LANCZOS)
    bg.alpha_composite(sp, (w // 2 - 29, h // 2 - 29))
    lb = Image.open(d / "label.png")
    lb = lb.resize((lb.width // 2, lb.height // 2), Image.LANCZOS)
    bg.alpha_composite(lb, (w // 2 - lb.width // 2, h // 2 + 29 + 26))
    bg.convert("RGB").save(OUT / "preview-plymouth.png")
    lim = backdrop(p, w, h).convert("RGBA")
    box = Image.new("RGBA", (w - 256, h - 256), rgb(p["surface_lowest"]) + (175,))
    lim.alpha_composite(box, (128, 128))
    lim.convert("RGB").save(OUT / "preview-limine.png")
    print(OUT / "preview-plymouth.png", OUT / "preview-limine.png", sep="\n")


def main():
    p = json.loads((HOME / ".local/state/rice/palette.json").read_text())
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    OUT.mkdir(parents=True, exist_ok=True)
    if what == "preview":
        return preview(p)
    if what in ("all", "limine"):
        apply_limine(p)
    if what in ("all", "login"):
        apply_login(p)
    if what in ("all", "plymouth"):
        apply_plymouth(p)


if __name__ == "__main__":
    main()
