// Circular ripple of the backdrop (Backdrop.qml): picture (already aligned & aspect-cropped in picTex)
// + veil + tiled sharp grain, clipped to a circle in one pass.
// Build (both files are committed; Qt loads the .qsb):
//   /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o ripple.frag.qsb ripple.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 boxSize;           // window logical px
    vec2 origin;            // ripple centre, logical px
    float radius;           // ripple radius, logical px
    float dpr;              // device pixel ratio
    float hasPic;           // 1.0 when drawing picture (matte/noise/none), 0.0 for veil-only
    float hasGrain;         // 1.0 when drawing tiled grain on top
    float grainAlpha;       // grain opacity
    vec2 grainSize;         // grain tile size in logical px (matches Image.Tile)
    vec4 veilColor;         // premultiplied veil colour
};
layout(binding = 1) uniform sampler2D picTex;
layout(binding = 2) uniform sampler2D grainTex;

vec4 over(vec4 top, vec4 under) { return top + (1.0 - top.a) * under; }

void main() {
    vec2 p = qt_TexCoord0 * boxSize;
    float aa = 0.75 / max(dpr, 1.0);
    float mask = 1.0 - smoothstep(radius - aa, radius + aa, length(p - origin));
    if (mask < 0.002) { fragColor = vec4(0.0); return; }

    vec4 c = hasPic > 0.5 ? texture(picTex, qt_TexCoord0) : vec4(0.0);
    c = over(veilColor, c);
    if (hasGrain > 0.5) {
        vec2 gs = max(grainSize, vec2(1.0));
        vec2 guv = (floor(p) + 0.5) / gs;
        vec4 g = texture(grainTex, fract(guv)) * grainAlpha;
        c = over(g, c);
    }
    fragColor = c * mask * qt_Opacity;
}
