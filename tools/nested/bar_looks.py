"""The bar tests' driver (run inside the nested session): every nested bar gets the rice's settings and both of
its looks (atom/panel.py bar_looks, dock_presets) in the main screen's palette, as rice.py gives them, with the
morph lasting argv[2] ms. Prints the islands and whether each bar took them."""
import hashlib
import json
import sys

sys.path.insert(0, sys.argv[1])
from atom import panel, util  # noqa: E402

p = json.load(open(util.STATE / "palette-HDMI-A-1.json"))
print("configured", json.dumps(panel.configure()))
for bar in panel.panels():
    looks = panel.bar_looks(p, bar)
    key = hashlib.sha1(json.dumps(looks, sort_keys=True).encode()).hexdigest()
    cfg = {"presetAutoloading": panel.dock_presets(bar, looks, key), "animatePropertyChanges": True,
           "animationDuration": int(sys.argv[2])}
    print("islands", [[w.split(".")[-1] for _, w in g] for g in panel.islands(bar)])
    print("applied", panel.colorizer_apply(bar, looks[0], cfg))
