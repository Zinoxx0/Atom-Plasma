var out = [];
panels().forEach(function (p) {
    if (p.screen < 0 || p.screen >= screenCount) return;     // its screen is unplugged
    var g = screenGeometry(p.screen), pc = null, clock = null, widgets = [];
    p.currentConfigGroup = ["General"];
    var order = String(p.readConfig("AppletOrder") || "");
    p.widgets().forEach(function (w) {
        if (w.type === ARGS.colorizer) pc = w.id;
        if (w.type === "org.kde.plasma.digitalclock") clock = w.id;
        widgets.push({id: w.id, type: w.type});
    });
    if (pc !== null) out.push({panel: p.id, screen: p.screen, x: g.x, y: g.y, colorizer: pc, clock: clock,
                               widgets: widgets, order: order});
});
print(JSON.stringify(out));
