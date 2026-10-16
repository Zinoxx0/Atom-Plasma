#!/usr/bin/env python3
"""Render what palette v2 makes of some wallpapers, one row each, to tune the moods offline.

    tools/palette_sheet.py OUT.png IMG [IMG...]

Each row: the wallpaper, its mood and measurements, the extracted swatches, the three accents
(and the ring gradient), the surface ladder, text on the background, ok/warn/bad, and a mock bar
island and ring drawn in the palette.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import palette  # noqa: E402

FONT = "/usr/share/fonts/inter/Inter.ttc"
ROW_H, PAD = 170, 16


def rgb(h):
    return tuple(round(c * 255) for c in palette.hex_rgb(h))


def font(size, bold=False):
    try:
        return ImageFont.truetype(FONT, size, index=0)
    except OSError:
        return ImageFont.load_default()


def cover(img, w, h):
    im = Image.open(img).convert("RGB")
    s = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * s), round(im.height * s)))
    x, y = (im.width - w) // 2, (im.height - h) // 2
    return im.crop((x, y, x + w, y + h))


def gradient(d, box, a, b):
    x0, y0, x1, y1 = box
    ca, cb = rgb(a), rgb(b)
    for x in range(x0, x1):
        t = (x - x0) / max(1, x1 - x0 - 1)
        d.line([(x, y0), (x, y1)], fill=tuple(round(ca[i] + (cb[i] - ca[i]) * t) for i in range(3)))


def row(img, p, a):
    W = 1500
    im = Image.new("RGB", (W, ROW_H), rgb(p["background"]))
    d = ImageDraw.Draw(im)
    im.paste(cover(img, 240, 135), (PAD, (ROW_H - 135) // 2))
    x = PAD + 240 + PAD
    fg, dim = rgb(p["on_surface"]), rgb(p["on_surface_variant"])
    d.text((x, 14), f"{p['_mood'].upper()}  ·  {Path(img).name}", fill=fg, font=font(18))
    d.text((x, 40), f"L {a['L']:.2f}  C {a['C']:.3f}  vivid {a['vivid']:.2f}  hue {a['hue']:.0f}  consistency {a['consistency']:.2f}", fill=dim, font=font(13))
    # swatches from the wallpaper
    for i, s in enumerate(p["_swatches"]):
        d.rounded_rectangle((x + i * 26, 64, x + i * 26 + 22, 86), 5, fill=rgb(s))
    # accents + ring gradient
    ax = x
    for i, role in enumerate(("primary", "secondary", "tertiary")):
        d.rounded_rectangle((ax + i * 70, 98, ax + i * 70 + 62, 130), 8, fill=rgb(p[role]))
        d.text((ax + i * 70 + 8, 106), "Aa", fill=rgb(p[f"on_{role}"]), font=font(15))
    gradient(d, (ax, 138, ax + 202, 146), p["primary"], p["tertiary"])
    # surfaces ladder
    sx = x + 250
    for i, k in enumerate(("surface_lowest", "background", "surface", "surface_container", "surface_high",
                           "surface_highest", "outline_variant", "outline")):
        d.rectangle((sx + i * 28, 64, sx + i * 28 + 28, 100), fill=rgb(p[k]))
    d.text((sx, 108), "Text on surface", fill=fg, font=font(15))
    d.text((sx, 130), "secondary text · muted", fill=dim, font=font(13))
    # ok / warn / bad
    for i, k in enumerate(("ok", "warn", "bad")):
        d.rounded_rectangle((sx + 250 + i * 64, 64, sx + 250 + i * 64 + 58, 86), 11, fill=rgb(p[k]))
    # mock island: surface body, gradient outline, a ring, a label
    ix, iy, iw, ih = sx + 250, 100, 330, 50
    d.rounded_rectangle((ix - 2, iy - 2, ix + iw + 2, iy + ih + 2), 16, fill=rgb(p["primary"]))
    d.rounded_rectangle((ix, iy, ix + iw, iy + ih), 14, fill=rgb(p["surface_container"]))
    d.arc((ix + 12, iy + 9, ix + 44, iy + 41), 0, 360, fill=rgb(p["outline_variant"]), width=4)
    d.arc((ix + 12, iy + 9, ix + 44, iy + 41), -90, 150, fill=rgb(p["primary"]), width=4)
    d.text((ix + 54, iy + 14), "69%   Fri 16 18:02", fill=fg, font=font(16))
    d.rounded_rectangle((ix + 230, iy + 12, ix + 316, iy + 38), 13, fill=rgb(p["primary_container"]))
    d.text((ix + 243, iy + 16), "chip", fill=rgb(p["on_primary_container"]), font=font(14))
    # the band's glow line
    gradient(d, (x, ROW_H - 6, W - PAD, ROW_H - 3), p["primary"], p["tertiary"])
    return im


def main():
    out, imgs = Path(sys.argv[1]), sys.argv[2:]
    rows = []
    for img in imgs:
        a = palette.analyse(img)
        rows.append(row(img, palette.build_v2(a, {"light_ui": True}), a))
    sheet = Image.new("RGB", (1500, len(rows) * (ROW_H + 4)), (255, 255, 255))
    for i, r in enumerate(rows):
        sheet.paste(r, (0, i * (ROW_H + 4)))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(out)


if __name__ == "__main__":
    main()
