#!/usr/bin/env python3
"""Screenshot set of the rice, for before/after comparisons, in ~/.cache/rice/shots/<set>/.

    shots.py <set> [part ...]
        parts: screens popups band apps notify osd lock perf   (default: all of them)
        popups:launcher,clock   only those popups

It opens popups and windows and moves the real cursor (uinput), so it takes over the desktop
for about a minute. Popups are captured from the main bar (panel 23, HDMI-A-1).
"""
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from pointer import Pointer, outputs  # noqa: E402

HOME = Path.home()
MAIN = "HDMI-A-1"
# main bar widgets: (name, applet id)
POPUPS = [("launcher", 167), ("wallpicker", 129), ("claude", 102), ("sysstats", 106),
          ("session", 107), ("clock", 85), ("tray", 72)]
OUT = {o["name"]: o for o in outputs()}


def capture(path):
    """Full desktop at 2x (spectacle captures in device pixels of the largest scale)."""
    subprocess.run(["spectacle", "-b", "-n", "-f", "-o", str(path)], check=True)
    for _ in range(40):
        if path.exists() and path.stat().st_size:
            break
        time.sleep(0.1)
    time.sleep(0.3)
    return Image.open(path)


def crop(im, out, top=None, bottom=None, scale=None):
    """Crop one output (logical coordinates) out of a full capture."""
    o = OUT[out]
    k = scale or im.width / max(x["x"] + x["w"] for x in OUT.values())
    y0, y1 = o["y"], o["y"] + o["h"]
    if top is not None:
        y1 = o["y"] + top
    if bottom is not None:
        y0 = o["y"] + o["h"] - bottom
    return im.crop((round(o["x"] * k), round(y0 * k), round((o["x"] + o["w"]) * k), round(y1 * k)))


def activate(applet):
    subprocess.run(["qdbus6", "org.kde.kglobalaccel", "/component/plasmashell",
                    "org.kde.kglobalaccel.Component.invokeShortcut", f"activate widget {applet}"],
                   capture_output=True)


def screens(d):
    im = capture(d / "_full.png")
    for name in OUT:
        crop(im, name).save(d / f"screen-{name}.png")
        crop(im, name, bottom=90).save(d / f"bar-{name}.png")
        crop(im, name, top=60).save(d / f"top-{name}.png")


# how each main-bar popup is opened: a kglobalaccel action, or a click on the widget
POPUP_OPEN = {"launcher": "activate application launcher", "wallpicker": "activate widget 129",
              "claude": "activate widget 102", "session": "activate widget 107"}
FLOAT_GAP = 8       # a floating panel sits this far from the screen edges


def bar_centres(panel=23):
    """Centre of every widget on a bottom panel, in global logical coordinates."""
    js = ("var p = panelById(%d); var g = screenGeometry(p.screen); var out = [g.x, g.y, g.width, g.height, p.height];"
          "p.widgets().forEach(function (w) { var r = w.geometry; out.push(w.id, w.type, r.x, r.y, r.width, r.height) });"
          "print(out.join('|'))" % panel)
    f = subprocess.run(["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js],
                       capture_output=True, text=True).stdout.strip().split("|")
    gx, gy, gw, gh, ph = map(float, f[:5])
    top = gy + gh - FLOAT_GAP - ph
    res = {}
    for i in range(5, len(f), 6):
        wid, typ, x, y, w, h = f[i:i + 6]
        res[typ] = (gx + FLOAT_GAP + float(x) + float(w) / 2, top + float(y) + float(h) / 2,
                    gx + FLOAT_GAP + float(x) + float(w))
    return res


def popups(d, only=None):
    """Each main-bar popup, opened the way a user would (shortcut or click), then closed the same way.
    Plasma popups don't show up in KWin's script API, so this goes by timing."""
    centres = bar_centres()
    clicks = {"sysstats": centres["com.zinoxx.sysstats"][:2],
              "clock": centres["org.kde.plasma.digitalclock"][:2],
              # the tray's expander arrow sits at its right end; the middle would hit an app icon
              "tray": (centres["org.kde.plasma.systemtray"][2] - 12, centres["org.kde.plasma.systemtray"][1])}
    o = OUT[MAIN]
    park = (o["x"] + o["w"] / 2, o["y"] + o["h"] / 2)
    with Pointer() as p:
        p.move(*park)
        for name, _ in POPUPS:
            if only and name not in only:
                continue
            for step in ("open", "close"):
                if name in clicks:
                    p.move(*clicks[name]); time.sleep(0.2); p.click(); time.sleep(0.1); p.move(*park)
                else:
                    subprocess.run(["qdbus6", "org.kde.kglobalaccel", "/component/plasmashell",
                                    "org.kde.kglobalaccel.Component.invokeShortcut", POPUP_OPEN[name]],
                                   capture_output=True)
                if step == "open":
                    time.sleep(2.2 if name == "launcher" else 1.5)
                    crop(capture(d / "_popup.png"), MAIN, bottom=760).save(d / f"popup-{name}.png")
                else:
                    time.sleep(1.0)


def band(d):
    o = OUT[MAIN]
    with Pointer() as p:
        p.move(o["x"] + o["w"] / 2, o["y"] + 300)
        time.sleep(0.4)
        p.glide(o["x"] + o["w"] / 2, o["y"] + 300, o["x"] + 400, o["y"], 250)  # it opens on the very edge
        time.sleep(0.9)
        crop(capture(d / "_band.png"), MAIN, top=180).save(d / "band-open.png")
        p.glide(o["x"] + 400, o["y"], o["x"] + 44, o["y"] + 20, 300)     # over the first icon
        time.sleep(0.9)
        crop(capture(d / "_band.png"), MAIN, top=180).save(d / "band-hover.png")
        p.glide(o["x"] + 44, o["y"] + 20, o["x"] + o["w"] / 2, o["y"] + 400, 200)
        time.sleep(0.6)


def apps(d):
    o = OUT[MAIN]
    with Pointer() as p:        # new windows open on the screen under the cursor
        p.move(o["x"] + o["w"] / 2, o["y"] + o["h"] / 2)
        time.sleep(0.3)
    for name, cmd in (("konsole", ["konsole", "--separate", "--workdir", str(HOME)]),
                      ("dolphin", ["dolphin", "--new-window", str(HOME / "Pictures/Wallpapers")])):
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(2.5)
        crop(capture(d / "_app.png"), MAIN).save(d / f"app-{name}.png")
        proc.terminate()
        time.sleep(0.8)


def notify(d):
    subprocess.run(["notify-send", "-a", "Rice preview", "-i", "preferences-desktop-theme",
                    "Rice preview", "This is how a notification looks right now."])
    time.sleep(1.2)
    crop(capture(d / "_notify.png"), MAIN).save(d / "notification.png")


def osd(d):
    subprocess.run(["qdbus6", "org.kde.plasmashell", "/org/kde/osdService",
                    "org.kde.osdService.mediaPlayerVolumeChanged", "60", "Preview", "audio-volume-medium"],
                   capture_output=True)
    time.sleep(0.6)
    crop(capture(d / "_osd.png"), MAIN).save(d / "osd.png")


def lock(d):
    proc = subprocess.Popen(["/usr/lib/kscreenlocker_greet", "--testing"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(3)
    crop(capture(d / "_lock.png"), MAIN).save(d / "lock.png")
    proc.terminate()
    try:
        proc.wait(3)
    except subprocess.TimeoutExpired:
        proc.kill()


def perf(d):
    """Idle cost: NVIDIA power over 20 s and plasmashell/kwin CPU ticks over the same window."""
    def ticks(name):
        pid = subprocess.run(["pgrep", "-x", name], capture_output=True, text=True).stdout.split()
        if not pid:
            return 0
        f = Path(f"/proc/{pid[0]}/stat").read_text().rsplit(")", 1)[1].split()
        return int(f[11]) + int(f[12])
    t0 = {n: ticks(n) for n in ("plasmashell", "kwin_wayland")}
    watts = []
    for _ in range(10):
        r = subprocess.run(["nvidia-smi", "--query-gpu=power.draw,utilization.gpu", "--format=csv,noheader,nounits"],
                           capture_output=True, text=True).stdout.strip().split(",")
        watts.append(float(r[0]))
        time.sleep(2)
    t1 = {n: ticks(n) for n in ("plasmashell", "kwin_wayland")}
    line = (f"gpu_w_avg={sum(watts) / len(watts):.1f} gpu_w_min={min(watts):.1f} "
            + " ".join(f"{n}_cpu%={(t1[n] - t0[n]) / 20:.1f}" for n in t0))
    (d / "perf.txt").write_text(line + "\n")
    print(line)


PARTS = {"screens": screens, "popups": popups, "band": band, "apps": apps,
         "notify": notify, "osd": osd, "lock": lock, "perf": perf}

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    d = HOME / ".cache/rice/shots" / sys.argv[1]
    d.mkdir(parents=True, exist_ok=True)
    for part in sys.argv[2:] or list(PARTS):     # "popups:launcher,clock" = only those popups
        name, _, only = part.partition(":")
        print("--", part, flush=True)
        PARTS[name](d, only.split(",")) if only else PARTS[name](d)
    for tmp in d.glob("_*.png"):
        tmp.unlink()
    print(d)
