// Replace top-level sections of one bar's Colorizer settings (ARGS.patch) in one write; the widget picks it
// up live. Prints "ok" for each Colorizer it wrote.
panels().forEach(function (p) {
    if (p.id !== ARGS.panel) return;
    p.widgets(ARGS.colorizer).forEach(function (w) {
        w.currentConfigGroup = ["General"];
        var g = {};
        try { g = JSON.parse(w.readConfig("globalSettings") || "{}"); } catch (e) {}
        for (var k in ARGS.patch) g[k] = ARGS.patch[k];
        w.writeConfig("globalSettings", JSON.stringify(g));
        w.reloadConfig();
        print("ok");
    });
});
