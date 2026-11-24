// The atom core's background (Core.qml): outer focus glow, three rotating rounded-cap arcs,
// tinted glass orb, inner border, accent rim and bottom light — all in one pass (replaces 3 Shape
// CurveRenderers and 2 Rectangles).
// Build (both files are committed; Qt loads the .qsb):
//   /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o core_back.frag.qsb core_back.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 boxSize;           // 2 * reach (logical px)
    float orbR;             // core.dia / 2 (logical px)
    float arcR;             // core.dia / 2 + d(9) * k (logical px)
    float reach;            // core.dia / 2 + d(40) * k (logical px)
    float arcRot;           // radians (40 * turns * PI / 180)
    float dpr;              // device pixel ratio (for crisp 1-dev-px AA)
    vec4 tint;              // focus tint (opaque, premultiplied alpha=1)
    vec4 arcMid;            // C.mix(tint, fg, 0.5) (opaque)
    vec4 glassColor;        // C.alpha(C.mix(surfaceLowest, tint, 0.12), 0.84) (premultiplied)
    vec4 innerBorder;       // C.alpha(light ? #000 : #fff, 0.13) (premultiplied)
    vec4 rimColor;          // C.alpha(tint, 0.45) (premultiplied)
};

const float PI = 3.14159265;

vec4 over(vec4 top, vec4 under) { return top + (1.0 - top.a) * under; }

// exact SDF of a circular arc with RoundCap at radius r, centred at angle cAng with half-sweep hSw
float arcMask(vec2 p, float r, float cAng, float hSw, float halfW, float aa) {
    float a = atan(p.y, p.x);
    float da = mod(a - cAng + PI, 2.0 * PI) - PI;
    float clamped = clamp(da, -hSw, hSw) + cAng;
    vec2 closest = vec2(cos(clamped), sin(clamped)) * r;
    float d = length(p - closest) - halfW;
    return 1.0 - smoothstep(-aa, aa, d);
}

void main() {
    vec2 p = qt_TexCoord0 * boxSize - vec2(reach);
    float dist = length(p);
    float aa = 0.75 / max(dpr, 1.0);
    if (dist > reach + aa) { fragColor = vec4(0.0); return; }

    vec3 tintRgb = tint.rgb / max(tint.a, 0.0001);
    vec3 midRgb = arcMid.rgb / max(arcMid.a, 0.0001);

    // 1. soft radial glow round the orb (0.26 at orbR -> 0 at reach)
    float gT = clamp((dist - orbR) / max(1.0, reach - orbR), 0.0, 1.0);
    float gOut = 1.0 - smoothstep(reach - aa, reach + aa, dist);
    vec4 c = vec4(tintRgb, 1.0) * (0.26 * (1.0 - gT) * gOut);

    // 2. three rotating rounded-cap arcs (startAngle -90/+26, 30/+12, 150/+12 deg)
    if (abs(dist - arcR) < 4.0) {
        float cr = cos(-arcRot), sr = sin(-arcRot);
        vec2 pr = vec2(cr * p.x - sr * p.y, sr * p.x + cr * p.y);
        float a1 = arcMask(pr, arcR, -77.0 * PI / 180.0, 13.0 * PI / 180.0, 1.1, aa);
        float a2 = arcMask(pr, arcR,  36.0 * PI / 180.0,  6.0 * PI / 180.0, 1.1, aa);
        float a3 = arcMask(pr, arcR, 156.0 * PI / 180.0,  6.0 * PI / 180.0, 1.1, aa);
        c = over(vec4(tintRgb, 1.0) * max(a1, a3), c);
        c = over(vec4(midRgb, 1.0) * a2, c);
    }

    // 3. the orb glass, inner 1px border, outer 1px accent rim, and bottom light
    if (dist < orbR + 2.0) {
        float orbIn = 1.0 - smoothstep(orbR - aa, orbR + aa, dist);
        c = over(glassColor * orbIn, c);

        float ib = smoothstep(orbR - 1.0 - aa, orbR - 1.0 + aa, dist) * orbIn;
        c = over(innerBorder * ib, c);

        float rm = smoothstep(orbR - aa, orbR + aa, dist) * (1.0 - smoothstep(orbR + 1.0 - aa, orbR + 1.0 + aa, dist));
        c = over(rimColor * rm, c);

        float underMask = 1.0 - smoothstep(orbR - 1.0 - aa, orbR - 1.0 + aa, dist);
        float uT = clamp(length(p - vec2(0.0, orbR * 1.2)) / max(1.0, orbR * 1.24), 0.0, 1.0);
        c = over(vec4(tintRgb, 1.0) * (0.7 * (1.0 - uT) * underMask), c);
    }

    if (c.a < 0.002) { fragColor = vec4(0.0); return; }
    fragColor = c * qt_Opacity;
}
