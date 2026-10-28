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
    one(ARGS.launcher); one("org.kde.plasma.digitalclock");
    (have["org.kde.plasma.kickoff"] || []).forEach(function (w) { w.remove(); });
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
    var clock = (have["org.kde.plasma.digitalclock"] || [])[0];
    if (clock) {
        clock.currentConfigGroup = ["Appearance"];
        clock.writeConfig("showDate", true);
        clock.writeConfig("dateDisplayFormat", "BesideTime");
        clock.writeConfig("dateFormat", "custom");
        clock.writeConfig("customDateFormat", "ddd d");
        clock.writeConfig("use24hFormat", 2);
        // the size is per bar (bigger on scaled bars), so only a fresh clock gets the default
        var fresh = String(clock.readConfig("autoFontAndSize")) !== "false";
        clock.writeConfig("autoFontAndSize", false);
        clock.writeConfig("fontFamily", "Inter Display");
        clock.writeConfig("fontWeight", 700);
        if (fresh) clock.writeConfig("fontSize", 11);
    }
    if (ARGS.with_tiling) one(ARGS.tiling);
    if (main) {
        one("org.kde.plasma.systemtray");
        if (ARGS.with_claude) one("com.zinoxx.claudeusage");
        one("com.zinoxx.sysstats");
        one("com.zinoxx.session");
    } else {
        one("org.kde.plasma.showdesktop");
    }
    var pc = one(ARGS.colorizer);
    var settings = JSON.parse(JSON.stringify(SETTINGS));
    settings.configurationOverrides.associations = [{"id": ids["org.kde.plasma.digitalclock"],
        "name": "org.kde.plasma.digitalclock", "presets": [ARGS.clockpad]}];
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
