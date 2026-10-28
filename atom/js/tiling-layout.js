var target = null;
workspace.screens.forEach(function (o) { if (o.name === ARGS.conn) target = o; });
if (!target) { answer("no-screen"); }
else {
    var before = workspace.activeWindow, desk = null;
    workspace.stackingOrder.forEach(function (w) { if (w.desktopWindow && w.output === target) desk = w; });
    if (desk) workspace.activeWindow = desk;
    callDBus("org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component", "invokeShortcut",
             ARGS.shortcut, function () {
        if (before && before !== desk) workspace.activeWindow = before;
        answer(desk ? "ok" : "no-desktop");
    });
}
