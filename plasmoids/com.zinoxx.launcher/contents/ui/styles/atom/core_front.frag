// The atom core's foreground highlights (Core.qml): upper-left glass sheen and conical upper-left
// rim light in one pass (replaces 2 Shape CurveRenderers).
// Build (both files are committed; Qt loads the .qsb):
//   /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o core_front.frag.qsb core_front.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float dia;              // core.dia (logical px)
    float dpr;              // device pixel ratio
};

const float PI = 3.14159265;

vec4 over(vec4 top, vec4 under) { return top + (1.0 - top.a) * under; }

void main() {
    float orbR = dia * 0.5;
    vec2 p = (qt_TexCoord0 - 0.5) * dia;
    float dist = length(p);
    float aa = 0.75 / max(dpr, 1.0);
    if (dist > orbR + aa) { fragColor = vec4(0.0); return; }

    // 1. sheen, high on the left (center 0.42, 0.13 of box; radius 0.32 * dia; clipped to orbR - 1)
    float inOrb = 1.0 - smoothstep(orbR - 1.0 - aa, orbR - 1.0 + aa, dist);
    float sT = clamp(length(p - vec2(-0.08 * dia, -0.37 * dia)) / max(1.0, 0.32 * dia), 0.0, 1.0);
    vec4 c = vec4(1.0) * (0.2 * (1.0 - sT) * inOrb);

    // 2. conical rim light along the upper left (annulus orbR - 3 .. orbR - 0.5, angle 128 deg CCW, peak at 0.13)
    float ring = smoothstep(orbR - 3.0 - aa, orbR - 3.0 + aa, dist)
               * (1.0 - smoothstep(orbR - 0.5 - aa, orbR - 0.5 + aa, dist));
    if (ring > 0.002) {
        float angCCW = mod(atan(-p.y, p.x) * 180.0 / PI, 360.0);
        float pos = mod(angCCW - 128.0, 360.0) / 360.0;
        float rimA = 0.0;
        if (pos < 0.13) rimA = (pos / 0.13) * 0.75;
        else if (pos < 0.27) rimA = ((0.27 - pos) / 0.14) * 0.75;
        c = over(vec4(1.0) * (rimA * ring), c);
    }

    if (c.a < 0.002) { fragColor = vec4(0.0); return; }
    fragColor = c * qt_Opacity;
}
