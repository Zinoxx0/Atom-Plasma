var want = ARGS.want;
panels().forEach(function (p) {
    var pt = want[String(p.id)];
    if (!pt) return;
    p.widgets("org.kde.plasma.digitalclock").forEach(function (w) {
        w.currentConfigGroup = ["Appearance"];
        if (Number(w.readConfig("fontSize")) !== pt) w.writeConfig("fontSize", pt);
    });
});
