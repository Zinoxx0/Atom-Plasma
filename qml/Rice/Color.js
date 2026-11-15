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

// A colour's relative luminance (WCAG: linear light, 0..1).
function luminance(c) {
    c = rgb(c);
    const f = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

// How strong a scrim of colour `under` must be over a backdrop of luminance Yb (the theme engine's measures:
// palette _backdrop / _backdropSharp, a banner's light) for text of colour `ink` to reach `ratio` (4.5 for small
// text). Blending happens on gamma-encoded values, so it's solved there. 0..0.94.
function scrim(Yb, ink, under, ratio) {
    const g = v => Math.pow(Math.max(0, v), 1 / 2.2);
    const Yt = luminance(ink), Ys = luminance(under);
    if (Yt >= Ys) {             // light text: the backdrop must stay under Ymax
        const Ymax = (Yt + 0.05) / ratio - 0.05;
        return Yb <= Ymax ? 0 : Math.min(0.94, (g(Yb) - g(Ymax)) / Math.max(1e-4, g(Yb) - g(Ys)));
    }
    const Ymin = ratio * (Yt + 0.05) - 0.05;     // dark text (a light mood): it must stay over Ymin
    return Yb >= Ymin ? 0 : Math.min(0.94, (g(Ymin) - g(Yb)) / Math.max(1e-4, g(Ys) - g(Yb)));
}
