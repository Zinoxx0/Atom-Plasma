var added = [];
desktops().forEach(function (d) {
    if (d.screen < 0 || d.screen >= screenCount) return;
    if (d.widgets(ARGS.desk).length) return;
    var g = screenGeometry(d.screen);
    // bottom right, under the bar: the applet draws nothing itself (its windows are layer-shell)
    d.addWidget(ARGS.desk, g.width - ARGS.px - 30, g.height - ARGS.px - 30, ARGS.px, ARGS.px);
    added.push(d.id);
});
print(JSON.stringify(added));
