// The atom's haze (Haze.qml): every ring's soft band of light in one pass (apps rest right on the arcs).
// Build (both files are committed; Qt loads the .qsb):
//   /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o haze.frag.qsb haze.frag
// Each ring (up to four: radii/lits/shows .x .y .z .w) is three bands, as the Atom lab drew them with CSS blur: a
// quiet one (the fg, when the ring isn't the active one), a wide one in the accent and its hot core (the active ring;
// `lit` hands the light over). A band = an annulus `width` wide blurred by a gaussian of `sigma`, done exactly: the
// difference of two erf across the radius. Its colour comes from the angle to the lens: c0 at the lens, c1 at a1, c2
// at a2, c3 opposite (mirrored round the lens).
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 boxSize;           // the item's size (px)
    vec2 centre;            // the atom's centre, in the item (px)
    vec4 radii;             // each ring's radius (px); 0 = no ring
    vec4 lits;              // each ring's light (0 quiet .. 1 active)
    vec4 shows;             // each ring's opacity (its reveal)
    vec4 widths;            // quiet, wide, hot band widths (px), w unused
    vec4 sigmas;            // and their blur (px)
    vec4 stops;             // quiet/wide a1, a2; hot a1, a2 (radians)
    float lens;             // the lens's angle (radians, clockwise from 3 o'clock)
    vec4 q0; vec4 q1; vec4 q2; vec4 q3;     // quiet colours
    vec4 w0; vec4 w1; vec4 w2; vec4 w3;     // wide colours
    vec4 h0; vec4 h1; vec4 h2; vec4 h3;     // hot colours
};

const float PI = 3.14159265;

float erfA(float x) {       // Abramowitz-Stegun 7.1.26
    float s = sign(x), a = abs(x), t = 1.0 / (1.0 + 0.3275911 * a);
    return s * (1.0 - ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-a * a));
}
// the share of a blurred annulus at distance d from its middle line
float band(float d, float w, float sg) {
    float k = 0.70710678 / max(sg, 0.5);
    return 0.5 * (erfA((d + 0.5 * w) * k) - erfA((d - 0.5 * w) * k));
}
// a colour (premultiplied) at angle t (0 = the lens .. PI = opposite)
vec4 tone(float t, vec4 c0, vec4 c1, vec4 c2, vec4 c3, float a1, float a2) {
    if (t < a1) return mix(c0, c1, t / a1);
    if (t < a2) return mix(c1, c2, (t - a1) / (a2 - a1));
    return mix(c2, c3, (t - a2) / (PI - a2));
}
vec4 over(vec4 top, vec4 under) { return top + (1.0 - top.a) * under; }

vec4 ring(float dist, float t, float r, float lit, float show) {
    if (r < 1.0 || show < 0.004) return vec4(0.0);
    float d = dist - r;
    if (abs(d) > widths.y * 0.5 + 3.0 * sigmas.y + 2.0) return vec4(0.0);
    vec4 q = tone(t, q0, q1, q2, q3, stops.x, stops.y) * band(d, widths.x, sigmas.x) * (1.0 - lit);
    vec4 w = tone(t, w0, w1, w2, w3, stops.x, stops.y) * band(d, widths.y, sigmas.y) * lit;
    vec4 h = tone(t, h0, h1, h2, h3, stops.z, stops.w) * band(d, widths.z, sigmas.z) * lit;
    return over(h, over(w, q)) * show;
}

void main() {
    vec2 p = qt_TexCoord0 * boxSize;
    vec2 v = p - centre;
    float dist = length(v);
    float a = atan(v.y, v.x);
    float t = abs(mod(a - lens + PI, 2.0 * PI) - PI);
    vec4 c = ring(dist, t, radii.x, lits.x, shows.x);
    c = over(ring(dist, t, radii.y, lits.y, shows.y), c);
    c = over(ring(dist, t, radii.z, lits.z, shows.z), c);
    c = over(ring(dist, t, radii.w, lits.w, shows.w), c);
    if (c.a < 0.002) { fragColor = vec4(0.0); return; }
    fragColor = c * qt_Opacity;
}
