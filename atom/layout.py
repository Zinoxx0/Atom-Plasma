"""Composition-aware placement of the desktop widgets: where on a wallpaper, as a screen shows it,
the clock block (and the music card under it) sit, and in which ink.

The wallpaper is covered and cropped to the screen like Plasma does, then scored per 8 px cell:
  detail    edge density after a light blur (sky, stars, fog and flat walls score low)
  presence  colour distance from the frame's own background (its border), so a flat but distinct
            subject (a face, a tower) still counts as "something there"
The block goes where the mean cost under it is lowest, clear of the top band, the bar and the
upper-left quadrant (the user keeps that for shortcuts and work: nothing may sit there), with a
mild pull toward the upper part of the screen. Ink: light text over a dark spot, dark over a
light one.

    layout.place(img, w, h) -> {"clock": {"x", "y", "w", "h"}, "media": {...}, "ink": "light"|"dark",
                                 "align": "left"|"right"}       (logical px of that screen)
    layout.py preview OUT.png IMG:WxH [IMG:WxH ...]             overlay sheet (cost heat + boxes)

numpy and Pillow are imported where they're used: rice.py imports this module for every command.
"""
from . import util

VERSION = 5                 # bump when the placement changes (rice.py caches layouts by it)
CELL = 8                    # logical px per cell
# Sizes are shares of the screen's 16:9 equivalent (as wide as the screen, at most 16:9 of its height): on a
# 16:9 screen that's the screen itself; a portrait or square one gets a landscape-shaped block sized by its
# width, an ultrawide one the block of the 16:9 screen inside it (no stretched clock either way).
CLOCK = (0.25, 0.20)        # the clock block (Clawd's room, time, date, status, hourly strip)
MEDIA = (0.20, 0.085)       # the music card
TOP, BOTTOM, SIDE = 0.07, 0.13, 0.035    # kept clear: the top band, the bar, the edges


def cover(img, w, h):
    """The wallpaper as the screen shows it (scaled to cover, centred), at one pixel per cell."""
    from PIL import Image
    im = Image.open(img).convert("RGB")
    cw, ch = max(1, w // CELL), max(1, h // CELL)
    s = max(cw / im.width, ch / im.height)
    im = im.resize((max(cw, round(im.width * s)), max(ch, round(im.height * s))), Image.LANCZOS)
    x, y = (im.width - cw) // 2, (im.height - ch) // 2
    return im.crop((x, y, x + cw, y + ch))


def cost_map(small):
    import numpy as np
    from PIL import Image, ImageFilter
    g = small.convert("L").filter(ImageFilter.GaussianBlur(0.8))
    e = np.asarray(g.filter(ImageFilter.FIND_EDGES), float)
    detail = np.asarray(Image.fromarray(np.clip(e * 3, 0, 255).astype("uint8")).filter(ImageFilter.GaussianBlur(2.5)), float)
    detail /= max(detail.max(), 1e-6)
    a = np.asarray(small.filter(ImageFilter.GaussianBlur(1.5)), float)
    border = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    bg = np.median(border, axis=0)
    presence = np.sqrt(((a - bg) ** 2).sum(axis=2))
    presence /= max(presence.max(), 1e-6)
    return 0.7 * detail + 0.3 * presence


def equivalent(W, H):
    """The 16:9 equivalent of a W x H screen (any unit): (width, height)."""
    eq = min(W, H * 16 / 9)
    return eq, eq * 9 / 16


def clear(W, H):
    """Cells kept clear at the sides, top and bottom of a W x H cell grid."""
    ew, eh = equivalent(W, H)
    return round(ew * SIDE), round(eh * TOP), round(eh * BOTTOM)


def best_box(cost, bw, bh, taken=()):
    """Top-left cell of the bw x bh box with the lowest mean cost (plus a pull upward), inside the
    clear area and off `taken` boxes."""
    import numpy as np
    H, W = cost.shape
    ii = np.pad(cost.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    side, top, bottom = clear(W, H)
    x0, x1 = side, W - side - bw
    y0, y1 = top, H - bottom - bh
    best, where = None, (x0, y0)
    for y in range(y0, max(y0, y1) + 1):
        for x in range(x0, max(x0, x1) + 1):
            if any(x < tx + tw and tx < x + bw and y < ty + th and ty < y + bh for tx, ty, tw, th in taken):
                continue
            if x < W / 2 and y < H / 2:     # the upper-left quadrant stays clear
                continue
            s = (ii[y + bh, x + bw] - ii[y, x + bw] - ii[y + bh, x] + ii[y, x]) / (bw * bh)
            s += 0.08 * (y + bh / 2) / H        # a little higher reads better
            if best is None or s < best:
                best, where = s, (x, y)
    return where


def place(img, w, h):
    import numpy as np
    small = cover(img, w, h)
    cost = cost_map(small)
    H, W = cost.shape
    ew, eh = equivalent(W, H)
    cw, ch = min(W, round(ew * CLOCK[0])), min(H, round(eh * CLOCK[1]))
    mw, mh = min(W, round(ew * MEDIA[0])), min(H, max(8, round(eh * MEDIA[1])))
    cx, cy = best_box(cost, cw, ch)
    # the music card stacks under the clock when that spot is quiet, else finds its own
    under = (cx, cy + ch + 1)
    ux = cx if cx + cw / 2 < W * 0.62 else cx + cw - mw    # flush with the clock's own side
    under = (ux, under[1])
    if under[1] + mh <= H - clear(W, H)[2] and cost[under[1]:under[1] + mh, ux:ux + mw].mean() < 0.35:
        mx, my = under
    else:
        mx, my = best_box(cost, mw, mh, taken=[(cx, cy, cw, ch)])
    lum = np.asarray(small.convert("L"), float)[cy:cy + ch, cx:cx + cw].mean() / 255
    box = lambda x, y, bw, bh: {"x": x * CELL, "y": y * CELL, "w": bw * CELL, "h": bh * CELL}
    return {"clock": box(cx, cy, cw, ch), "media": box(mx, my, mw, mh),
            "ink": "dark" if lum > 0.62 else "light", "align": "right" if cx + cw / 2 > W * 0.62 else "left",
            "_cost": cost}


def preview(out, specs):
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont
    face, index = util.font("Inter:style=Regular")
    rows = []
    for spec in specs:
        img, size = spec.rsplit(":", 1)
        w, h = map(int, size.split("x"))
        L = place(img, w, h)
        k = 900 / w
        im = Image.open(img).convert("RGB")
        s = max(w / im.width, h / im.height)
        im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
        im = im.crop(((im.width - w) // 2, (im.height - h) // 2, (im.width - w) // 2 + w, (im.height - h) // 2 + h))
        im = im.resize((900, round(h * k)), Image.LANCZOS)
        heat = Image.fromarray((np.clip(L["_cost"], 0, 1) * 255).astype("uint8")).resize(im.size, Image.BILINEAR)
        red = Image.new("RGB", im.size, (255, 40, 60))
        im = Image.composite(red, im, heat.point(lambda v: int(v * 0.45)))
        d = ImageDraw.Draw(im)
        H, W = im.size[1], im.size[0]
        d.rectangle((0, 0, W, int(H * TOP)), outline=(255, 255, 255))
        d.rectangle((0, H - int(H * BOTTOM), W, H), outline=(255, 255, 255))
        ink = (245, 245, 250) if L["ink"] == "light" else (20, 22, 28)
        c, m = L["clock"], L["media"]
        bx = lambda b: tuple(round(v * k) for v in (b["x"], b["y"], b["x"] + b["w"], b["y"] + b["h"]))
        d.rectangle(bx(c), outline=(80, 255, 160), width=2)
        d.rectangle(bx(m), outline=(80, 200, 255), width=2)
        x0, y0, x1, y1 = bx(c)
        f = ImageFont.truetype(face, max(10, round((y1 - y0) * 0.5)), index=index)
        tx = x0 + 6 if L["align"] == "left" else x1 - 6 - d.textlength("19:36", font=f)
        d.text((tx, y0 + 2), "19:36", fill=ink, font=f)
        d.text((x0 + 6, y0 + (y1 - y0) * 0.62), "FRIDAY · 16 OCT", fill=ink, font=ImageFont.truetype(face, max(8, round((y1 - y0) * 0.12)), index=index))
        d.text((6, H - int(H * BOTTOM) - 16), f"{img.rsplit('/', 1)[-1]}  ink={L['ink']}  align={L['align']}", fill=(255, 255, 255),
               font=ImageFont.truetype(face, 12, index=index))
        rows.append(im)
    sheet = Image.new("RGB", (900, sum(r.height + 8 for r in rows)), (0, 0, 0))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y)); y += r.height + 8
    sheet.save(out)
    print(out)

