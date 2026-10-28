var out = [];
desktops().forEach(function (d) {
    // a desktop keeps its screen index while that screen is unplugged, and screenGeometry() answers
    // an index past the last screen with screen 0's place
    if (d.screen < 0 || d.screen >= screenCount) return;
    var g = screenGeometry(d.screen);
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    out.push({id: d.id, screen: d.screen, x: g.x, y: g.y,
              image: d.wallpaperPlugin === "org.kde.image" ? d.readConfig("Image") : ""});
});
print(JSON.stringify(out));
