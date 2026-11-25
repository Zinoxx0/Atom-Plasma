// Optical Glass for taskbar islands and morphing popup sheets (LiquidBar.qml & Glass.qml):
// Supports two single-pass GPU surface materials via `mode` (0% idle cost):
//   mode == 0  Liquid glass : plano-convex bevel SDF, Snell's-law refraction, Cauchy RGB dispersion, Fresnel rim
//   mode == 1  Aurora glass : silky translucent palette mesh (primary/secondary/tertiary) + soft glass rim
//
// Build (both files are committed; Qt loads the .qsb):
//   /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o liquid_glass.frag.qsb liquid_glass.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 boxSize;           // element logical px
    vec2 rectPos;           // element top-left in screen logical px (for wallpaper alignment)
    vec2 screenSize;        // screen logical px
    float bevel;            // curved optical bezel width (logical px, e.g. 11 for islands, 16 for popups)
    float dpr;              // device pixel ratio
    vec4 radii;             // corner radii (topLeft, topRight, bottomRight, bottomLeft) logical px
    vec4 tintColor;         // glass body tint (RGB) + tint strength (A)
    vec4 rimA;              // primary rim accent (RGB) + unused A
    vec4 rimB;              // tertiary rim accent (RGB) + unused A
    vec4 rimC;              // secondary accent (RGB) for Aurora silk mesh
    float glassAlpha;       // overall opacity of the refracted glass body (allows KWin live blur behind)
    float frostMix;         // interior frost blend (0 = pure crystal, 1 = frosted)
    float isLight;          // 1.0 light theme, 0.0 dark theme
    float isJewel;          // 1.0 for launcher accent jewel island, 0.0 for regular islands/popups
    float flatBottom;       // 1.0 for screen-bottom notch islands (flush bottom & screen-corner edges)
    float mode;             // 0.0 = Liquid glass, 1.0 = Aurora silk glass
};

layout(binding = 1) uniform sampler2D sharpTex;
layout(binding = 2) uniform sampler2D blurTex;

const float IOR_R = 0.635;  // 1 / 1.575
const float IOR_G = 0.658;  // 1 / 1.520
const float IOR_B = 0.682;  // 1 / 1.466

float sdRoundBox4(vec2 p, vec2 b, vec4 r) {
    float cr = (p.y < 0.0) ? ((p.x < 0.0) ? r.x : r.y)
                           : ((p.x < 0.0) ? r.w : r.z);
    cr = min(cr, min(b.x, b.y));
    vec2 q = abs(p) - b + vec2(cr);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - cr;
}

vec2 gradRoundBox4(vec2 p, vec2 b, vec4 r) {
    float eps = 0.5;
    float dx = sdRoundBox4(p + vec2(eps, 0.0), b, r) - sdRoundBox4(p - vec2(eps, 0.0), b, r);
    float dy = sdRoundBox4(p + vec2(0.0, eps), b, r) - sdRoundBox4(p - vec2(0.0, eps), b, r);
    vec2 g = vec2(dx, dy);
    float len = length(g);
    return len > 1e-4 ? g / len : vec2(0.0, -1.0);
}

vec3 liftVibrancy(vec3 c, float sat) {
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    return clamp(mix(vec3(l), c, sat), 0.0, 1.0);
}

vec2 reflectUv(vec2 u) {
    vec2 m = mod(abs(u), 2.0);
    return clamp(1.0 - abs(1.0 - m), vec2(0.002), vec2(0.998));
}

void main() {
    vec2 p = qt_TexCoord0 * boxSize;
    vec2 halfB = boxSize * 0.5;
    vec2 lp = p - halfB;
    float aa = 0.75 / max(dpr, 1.0);

    float d = sdRoundBox4(lp, halfB, radii);
    float mask = 1.0 - smoothstep(-aa, aa, d);
    if (mask < 0.002) { fragColor = vec4(0.0); return; }

    // Flush bevel edges for screen-bottom notch islands & screen-corner notches
    float extB = flatBottom > 0.5 ? bevel * 2.0 : 0.0;
    float extL = (flatBottom > 0.5 && radii.x < 0.5) ? bevel * 2.0 : 0.0;
    float extR = (flatBottom > 0.5 && radii.y < 0.5) ? bevel * 2.0 : 0.0;
    vec2 bevelB = vec2(halfB.x + (extL + extR) * 0.5, halfB.y + extB);
    vec2 bevelP = vec2(lp.x - (extR - extL) * 0.5, lp.y - extB);
    vec4 bevelR = flatBottom > 0.5 ? vec4(radii.x, radii.y, 0.0, 0.0) : radii;
    float dBevel = sdRoundBox4(bevelP, bevelB, bevelR);
    vec2 n2 = gradRoundBox4(bevelP, bevelB, bevelR);

    float bw = max(bevel, 4.0);
    float t = clamp(-dBevel / bw, 0.0, 1.0);
    float u = 1.0 - t;
    vec2 screenPos = rectPos + p;
    vec2 baseUv = screenPos / max(screenSize, vec2(1.0));
    vec3 accentGrad = mix(rimA.rgb, rimB.rgb, qt_TexCoord0.x);

    // Rim & crease geometry shared across all three glass modes
    float rimStroke = smoothstep(-2.0, -0.4, dBevel) * (1.0 - smoothstep(-0.4, 0.7, dBevel));
    float topWeight = clamp(0.85 - qt_TexCoord0.y * 0.55, 0.2, 1.0);
    float innerShadow = smoothstep(-bw * 0.55, -bw * 0.18, dBevel) * (1.0 - smoothstep(-bw * 0.18, -0.8, dBevel));

    // =========================================================================
    // MODE 1: AURORA SILK GLASS (velvety translucent palette mesh + crisp rim)
    // =========================================================================
    if (mode > 0.5) {
        vec2 uv = qt_TexCoord0;
        vec2 wuv = vec2(uv.x - 0.5, uv.y - 0.5);
        float g1 = exp(-dot(wuv - vec2(-0.34, -0.18), wuv - vec2(-0.34, -0.18)) * 5.2);
        float g2 = exp(-dot(wuv - vec2(0.04, 0.22), wuv - vec2(0.04, 0.22)) * 5.8);
        float g3 = exp(-dot(wuv - vec2(0.36, -0.12), wuv - vec2(0.36, -0.12)) * 5.2);
        vec3 baseFrost = liftVibrancy(texture(blurTex, reflectUv(baseUv)).rgb, 1.15);
        vec3 silk = mix(tintColor.rgb, baseFrost, isLight > 0.5 ? 0.22 : 0.16);
        float sK = isLight > 0.5 ? 0.38 : 0.48;
        silk = mix(silk, liftVibrancy(rimA.rgb, 1.35), clamp(g1 * sK, 0.0, 0.62));
        silk = mix(silk, liftVibrancy(rimC.rgb, 1.35), clamp(g2 * sK * 0.88, 0.0, 0.56));
        silk = mix(silk, liftVibrancy(rimB.rgb, 1.35), clamp(g3 * sK, 0.0, 0.62));
        if (isJewel > 0.5) {
            silk = mix(silk, accentGrad * 0.80, 0.68);
        }
        float sheen = smoothstep(0.55, 0.0, uv.y) * (isLight > 0.5 ? 0.18 : 0.09);
        vec3 col = silk + vec3(1.0) * sheen;
        col += mix(vec3(1.0), accentGrad, 0.45) * (rimStroke * topWeight * (isLight > 0.5 ? 0.65 : 0.52));
        float outA = clamp(glassAlpha + rimStroke * 0.35, 0.0, 1.0) * mask * qt_Opacity;
        fragColor = vec4(clamp(col, 0.0, 1.0) * outA, outA);
        return;
    }

    // =========================================================================
    // MODE 0: APPLE LIQUID GLASS (convex optical bevel + Snell + Fresnel)
    // =========================================================================
    float slope = clamp((u * u * 2.15) / sqrt(max(1.0 - u * u * 0.86, 0.09)), 0.0, 2.8);
    vec2 dome = (lp / max(halfB, vec2(1.0))) * 0.06;
    vec3 N = normalize(vec3(n2 * slope + dome, 1.0));
    vec3 I = vec3(0.0, 0.0, -1.0);

    vec3 refR = refract(I, N, IOR_R);
    vec3 refG = refract(I, N, IOR_G);
    vec3 refB = refract(I, N, IOR_B);

    vec2 pxOffset = vec2(bw * 1.45) / max(screenSize, vec2(1.0));
    float chromaK = 1.0 + 1.65 * u;
    vec2 uvG = reflectUv(baseUv + refG.xy * pxOffset);
    vec2 uvR = reflectUv(baseUv + mix(refG.xy, refR.xy, chromaK) * pxOffset);
    vec2 uvB = reflectUv(baseUv + mix(refG.xy, refB.xy, chromaK) * pxOffset);

    vec3 sharpCol = vec3(
        texture(sharpTex, uvR).r,
        texture(sharpTex, uvG).g,
        texture(sharpTex, uvB).b
    );
    vec3 blurCol = vec3(
        texture(blurTex, uvR).r,
        texture(blurTex, uvG).g,
        texture(blurTex, uvB).b
    );

    float localFrost = clamp(frostMix * (0.26 + 0.74 * smoothstep(0.0, 0.85, t)), 0.0, 1.0);
    vec3 glassCol = liftVibrancy(mix(sharpCol, blurCol, localFrost), 1.24);

    vec3 bodyCol = glassCol;
    if (isJewel > 0.5) {
        vec3 deepJewel = accentGrad * 0.72;
        bodyCol = mix(glassCol, deepJewel, 0.70);
    } else {
        bodyCol = mix(glassCol, tintColor.rgb, tintColor.a);
    }

    float NdotV = clamp(N.z, 0.0, 1.0);
    float fresnel = 0.04 + 0.96 * pow(1.0 - NdotV, 3.8);

    vec3 L1 = normalize(vec3(-0.48, -0.82, 0.42));
    vec3 L2 = normalize(vec3(0.55, 0.76, 0.35));
    vec3 H1 = normalize(L1 + vec3(0.0, 0.0, 1.0));
    vec3 H2 = normalize(L2 + vec3(0.0, 0.0, 1.0));
    float spec1 = pow(max(dot(N, H1), 0.0), 34.0);
    float spec2 = pow(max(dot(N, H2), 0.0), 22.0);
    float sheen = smoothstep(0.55, 0.0, qt_TexCoord0.y) * (isLight > 0.5 ? 0.14 : 0.075);

    vec3 col = bodyCol;
    col *= (1.0 - innerShadow * (isLight > 0.5 ? 0.07 : 0.14));
    col += vec3(1.0) * (sheen + spec1 * (isLight > 0.5 ? 0.55 : 0.48));
    col += mix(vec3(1.0), accentGrad, 0.45) * (spec2 * (isLight > 0.5 ? 0.22 : 0.24));
    col += mix(vec3(1.0), accentGrad, 0.28) * (fresnel * (isLight > 0.5 ? 0.40 : 0.38));
    col += mix(vec3(1.0), accentGrad, isJewel > 0.5 ? 0.2 : 0.35) * (rimStroke * topWeight * (isLight > 0.5 ? 0.68 : 0.52));

    float outAlpha = clamp(glassAlpha + fresnel * 0.32 + rimStroke * 0.42 + spec1 * 0.35, 0.0, 1.0) * mask * qt_Opacity;
    col = clamp(col, 0.0, 1.0);
    fragColor = vec4(col * outAlpha, outAlpha);
}
