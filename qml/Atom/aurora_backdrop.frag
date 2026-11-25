// Aurora Ambient Silk Mesh backdrop (Backdrop.qml, style "aurora"):
// Velvety organic multi-lobe color mesh woven from the screen's three palette accents
// (primary, secondary, tertiary) over surfaceLowest, with smooth triangular-PDF dithering
// (zero 8-bit banding) and circular ripple support for the Power Page — single GPU pass, 0% idle GPU.
//
// Build (both files are committed; Qt loads the .qsb):
//   /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o aurora_backdrop.frag.qsb aurora_backdrop.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 boxSize;           // window logical px
    float dpr;              // device pixel ratio
    float isLight;          // 1.0 on light theme, 0.0 on dark theme
    vec2 origin;            // ripple center, window logical px
    float radius;           // ripple radius (< 0: whole window)
    float veilAlpha;        // subtle darkening / lightening control
    vec4 baseColor;         // palette surfaceLowest (RGB)
    vec4 colA;              // palette primary (RGB)
    vec4 colB;              // palette secondary (RGB)
    vec4 colC;              // palette tertiary (RGB)
};

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec3 boostSat(vec3 c, float sat) {
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    return clamp(mix(vec3(l), c, sat), 0.0, 1.0);
}

void main() {
    vec2 p = qt_TexCoord0 * boxSize;
    float aa = 0.75 / max(dpr, 1.0);

    float mask = 1.0;
    float rippleGlow = 0.0;
    if (radius >= 0.0) {
        float dist = length(p - origin);
        mask = 1.0 - smoothstep(radius - aa, radius + aa, dist);
        if (mask < 0.002) { fragColor = vec4(0.0); return; }
        float rw = clamp(min(boxSize.x, boxSize.y) * 0.05, 18.0, 44.0);
        float rt = clamp((radius - dist) / rw, 0.0, 1.0);
        rippleGlow = (1.0 - rt) * (1.0 - rt) * 0.22;
    }

    vec2 uv = qt_TexCoord0;
    // Aspect-balanced coordinates so silk lobes stay gracefully proportioned on ultrawide / 16:9 / preview cards
    float aspect = boxSize.x / max(boxSize.y, 1.0);
    vec2 wuv = vec2((uv.x - 0.5) * min(aspect, 2.0), uv.y - 0.5);

    // Organic silk fold warp (static: 0% idle GPU)
    vec2 warp = vec2(
        sin(wuv.y * 3.1 + wuv.x * 1.4) * 0.10,
        cos(wuv.x * 2.6 - wuv.y * 1.7) * 0.09
    );
    vec2 q = wuv + warp;

    // 4 harmonious atmospheric color lobes in golden-ratio balance
    float d1 = length((q - vec2(0.42, -0.26)) * vec2(0.85, 1.25));   // upper-right primary bloom
    float d2 = length((q - vec2(-0.46, 0.30)) * vec2(0.80, 1.20));   // lower-left tertiary sweep
    float d3 = length((q - vec2(-0.22, -0.34)) * vec2(0.95, 1.30));  // upper-left secondary mist
    float d4 = length((q - vec2(0.32, 0.36)) * vec2(0.90, 1.35));    // lower-right cross-tint

    float g1 = exp(-d1 * d1 * 2.35);
    float g2 = exp(-d2 * d2 * 2.15);
    float g3 = exp(-d3 * d3 * 2.50);
    float g4 = exp(-d4 * d4 * 2.80);

    // Subtle sweeping silk ribbon across the diagonal
    float ribbon = exp(-pow((q.y + q.x * 0.44 - sin(q.x * 2.4) * 0.16) * 3.1, 2.0));

    vec3 aViv = boostSat(colA.rgb, 1.38);
    vec3 bViv = boostSat(colB.rgb, 1.38);
    vec3 cViv = boostSat(colC.rgb, 1.38);

    float strength = isLight > 0.5 ? 0.38 : 0.48;
    vec3 col = baseColor.rgb;
    col = mix(col, aViv, clamp(g1 * strength + ribbon * 0.16, 0.0, 0.64));
    col = mix(col, cViv, clamp(g2 * strength * 0.96 + ribbon * 0.12, 0.0, 0.60));
    col = mix(col, bViv, clamp(g3 * strength * 0.84 + g4 * strength * 0.55, 0.0, 0.54));

    // Gentle top-left studio illumination & deep edge anchoring so silk bands glow with contrast
    float topGlow = smoothstep(0.75, 0.0, uv.y) * (isLight > 0.5 ? 0.07 : 0.03);
    float vig = smoothstep(1.30, 0.22, length(wuv));
    col = mix(baseColor.rgb, col, 0.64 + 0.36 * vig);
    col += mix(vec3(1.0), aViv, 0.4) * (ribbon * (isLight > 0.5 ? 0.09 : 0.08));
    col += vec3(1.0) * (topGlow + rippleGlow);

    // Optional extra veil when used on PowerWindow over dense content
    if (veilAlpha > 0.001) {
        col = mix(col, baseColor.rgb, clamp(veilAlpha * 0.42, 0.0, 0.42));
    }

    // Triangular-PDF dither eliminates 8-bit gradient banding completely
    float dither = (hash12(p) + hash12(p + 13.7) - 1.0) / 255.0;
    col = clamp(col + dither, 0.0, 1.0);
    fragColor = vec4(col, 1.0) * mask * qt_Opacity;
}
