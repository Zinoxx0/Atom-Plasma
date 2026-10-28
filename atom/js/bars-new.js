var want = ARGS.want, made = [];
var have = {};
panels().forEach(function (p) { if (p.screen >= 0 && p.screen < screenCount) have[p.screen] = p; });
want.forEach(function (w) {
    if (w.screen >= screenCount) return;
    var p = have[w.screen];
    if (!p) {
        p = new Panel("org.kde.panel");
        p.screen = w.screen;
        p.location = "bottom";
        p.floating = true;
        p.lengthMode = "fill";
        w.widgets.forEach(function (name) {
            var x = p.addWidget(name === "|" || name === "~" ? ARGS.spacer : name);
            if (name === "|" || name === "~") {
                x.currentConfigGroup = ["General"];
                x.writeConfig("expanding", name === "~");
                if (name === "|") x.writeConfig("length", 8);
            }
        });
        made.push(p.id);
    }
    if (p.height !== w.height) p.height = w.height;
});
print(JSON.stringify(made));
