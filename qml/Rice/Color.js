.pragma library
// Colour helpers shared by the rice widgets. They accept colours or "#rrggbb" strings.

function rgb(c) { return Qt.lighter(c, 1) }

function alpha(c, a) {
    c = rgb(c);
    return Qt.rgba(c.r, c.g, c.b, a);
}

function mix(a, b, t) {
    a = rgb(a); b = rgb(b);
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
}

// An app's own colour, from its icon (Kirigami.ImageColors): the most vivid sizeable swatch,
// lifted to a candy pastel that reads on the dark surfaces. Monochrome icons get `fallback`.
function appTint(ic, fallback) {
    const pal = ic ? ic.palette : null;
    let best = null, score = 0;
    for (let i = 0; pal && i < pal.length; i++) {
        const c = pal[i].color, r = pal[i].ratio;
        if (r < 0.04 || c.hslSaturation < 0.28 || c.hslLightness < 0.12 || c.hslLightness > 0.92) continue;
        const sc = c.hslSaturation * Math.sqrt(r);
        if (sc > score) { best = c; score = sc; }
    }
    if (!best) return fallback;
    return Qt.hsla(best.hslHue, Math.min(1, best.hslSaturation * 1.1), Math.max(0.62, Math.min(0.76, best.hslLightness)), 1);
}
