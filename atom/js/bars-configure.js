var SETTINGS = ARGS.settings;
var out = {};
function add(p, plugin, cfg) {
    var w = p.addWidget(plugin);
    for (var group in (cfg || {})) {
        w.currentConfigGroup = group.split("/");
        for (var k in cfg[group]) w.writeConfig(k, cfg[group][k]);
    }
    return w;
}
function spacer(p) { return add(p, ARGS.spacer, {"General": {"expanding": false, "length": 8}}); }
panels().forEach(function (p) {
    var main = p.screen === 0;
    var have = {};
    p.widgets().forEach(function (w) { (have[w.type] = have[w.type] || []).push(w); });
    var ids = {};
    function one(plugin, cfg) {
        var w = (have[plugin] || [])[0] || add(p, plugin, cfg);
        ids[plugin] = w.id;
        return w;
    }
    // existing pieces
    one(ARGS.launcher); one(ARGS.clock);
    // the clock island replaces the stock clock (its calendar lives on the shell's sheet)
    // ... and the status island replaces Plasma's system tray (its applets go with it: the control center,
    // the notifications and the tray icons are the shell's now)
    ["org.kde.plasma.kickoff", "org.kde.plasma.digitalclock", "org.kde.plasma.systemtray"].forEach(function (t) {
        (have[t] || []).forEach(function (w) { w.remove(); });
    });
    // tasks: Glimpse takes over a stock task manager, pinned apps included
    var LEGACY = ARGS.legacy, old = [];
    LEGACY.forEach(function (t) { old = old.concat(have[t] || []); });
    var legacy = old[0], pins = [];
    if (legacy) {
        legacy.currentConfigGroup = ["General"];
        pins = legacy.readConfig("launchers") || [];
        if (typeof pins === "string") pins = pins ? pins.split(",") : [];
    }
    one(ARGS.tasks, {"General": {"launchers": pins}});
    // the wallpaper picker lives inside the launcher now (Meta+Shift+W, the wheel over the emblem)
    old = old.concat(have["com.zinoxx.wallpicker"] || []);
    old.forEach(function (w) { w.remove(); });
    if (ARGS.with_tiling) one(ARGS.tiling);
    if (main) {
        var st = one(ARGS.status);
        // Meta+V: the clipboard's history (plasmashell's own binding is released first, atom/panel.py)
        if (!st.globalShortcut) st.globalShortcut = "Meta+V";
        if (ARGS.with_claude) one("com.zinoxx.claudeusage");
        one("com.zinoxx.sysstats");
        one("com.zinoxx.session");
    } else {
        one("org.kde.plasma.showdesktop");
    }
    one(ARGS.shell);            // the panels' host (no width on the bar)
    var pc = one(ARGS.colorizer);
    var settings = JSON.parse(JSON.stringify(SETTINGS));
    settings.configurationOverrides.associations = [];      // the clock island pads itself
    pc.currentConfigGroup = ["General"];
    pc.writeConfig("globalSettings", JSON.stringify(settings));
    pc.writeConfig("islandsEnabled", true);
    pc.writeConfig("islandSeparatorWidget", ARGS.spacer);
    pc.writeConfig("hideWidget", true);
    pc.writeConfig("isEnabled", true);
    pc.writeConfig("animatePropertyChanges", true);     // hover and popup states ease in
    pc.writeConfig("animationDuration", 220);
    // spacers: keep one expanding, make sure there are enough small ones
    var spacers = have[ARGS.spacer] || [];
    var expanding = spacers[0] || add(p, ARGS.spacer);
    expanding.currentConfigGroup = ["General"];
    expanding.writeConfig("expanding", true);
    var small = spacers.slice(1).map(function (w) { return w.id; });
    var need = main ? 7 : 3;
    while (small.length < need) small.push(spacer(p).id);
    ids.expanding = expanding.id;
    ids.small = small;
    out[p.id] = ids;
});
print(JSON.stringify(out));
