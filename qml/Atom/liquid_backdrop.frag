// Apple Liquid Glass full-screen backdrop (Backdrop.qml, style "liquid"):
// True Snell's-law refraction + spectral chromatic dispersion + curved edge lens bevel +
// organic optical glass depth + Fresnel specular rim, in one single GPU fragment pass
// (samples pre-fitted sharp wallpaper _wallFit and pre-blurred frost _glassFull — zero blur passes).
// Also supports circular opening/closing ripples with a refractive curved glass meniscus edge.
//
// Build (both files are committed; Qt loads the .qsb):
//   /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o liquid_backdrop.frag.qsb liquid_backdrop.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 boxSize;           // window logical px
    vec2 screenSize;        // full screen logical px
    float offsetY;          // window top offset below screen top (logical px)
    float dpr;              // device pixel ratio
    vec2 origin;            // ripple center, window logical px
    float radius;           // ripple radius (< 0: whole window)
    float isLight;          // 1.0 on light theme, 0.0 on dark theme
    vec2 lensCenter;        // optional subtle focal lens center (e.g. Atom core), window px
    float lensRadius;       // focal lens radius (<= 0: none)
    float veilAlpha;        // adaptive veil strength (0..1)
    vec4 veilColor;         // palette surfaceLowest (RGB) + unused A
    vec4 accentColor;       // palette primary (RGB) for delicate rim tint
};

layout(binding = 1) uniform sampler2D sharpTex;
layout(binding = 2) uniform sampler2D blurTex;

const float IOR_R = 0.642;  // 1 / 1.558 (red bends least)
const float IOR_G = 0.658;  // 1 / 1.520 (crown glass green)
const float IOR_B = 0.676;  // 1 / 1.479 (blue bends most)

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

vec2 gradRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    vec2 s = sign(p);
    if (q.x > 0.0 && q.y > 0.0) {
        return s * normalize(q);
    }
    return (q.x > q.y) ? vec2(s.x, 0.0) : vec2(0.0, s.y);
}

// Smooth optical thickness variation across the glass sheet (hand-cast architectural glass)
vec2 liquidBodyGrad(vec2 uv) {
    float wx = 6.28318 * uv.x;
    float wy = 6.28318 * uv.y;
    float gx = cos(wx * 1.1 + wy * 0.45) * 0.55 - sin(wx * 2.1 - wy * 1.3) * 0.25;
    float gy = cos(wy * 1.2 - wx * 0.35) * 0.55 + cos(wx * 1.7 + wy * 1.9) * 0.22;
    return vec2(gx, gy);
}

vec3 liftVibrancy(vec3 c, float sat) {
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    return clamp(mix(vec3(l), c, sat), 0.0, 1.0);
}

// Smooth internal reflection at screen boundaries so edge bevels never smear 1 px clamp streaks
vec2 reflectUv(vec2 u) {
    vec2 m = mod(abs(u), 2.0);
    return clamp(1.0 - abs(1.0 - m), vec2(0.002), vec2(0.998));
}

void main() {
    vec2 p = qt_TexCoord0 * boxSize;
    float aa = 0.75 / max(dpr, 1.0);

    // 1. Optional circular ripple mask & curved liquid meniscus ring at wavefront
    float mask = 1.0;
    vec2 rippleGrad = vec2(0.0);
    float rippleBand = 0.0;
    if (radius >= 0.0) {
        vec2 dp = p - origin;
        float dist = length(dp);
        mask = 1.0 - smoothstep(radius - aa, radius + aa, dist);
        if (mask < 0.002) { fragColor = vec4(0.0); return; }
        float ringW = clamp(min(boxSize.x, boxSize.y) * 0.065, 22.0, 56.0);
        float rt = clamp((radius - dist) / ringW, 0.0, 1.0);
        if (rt < 1.0 && dist > 0.5) {
            float slope = (1.0 - rt) / sqrt(max(1.0 - (1.0 - rt) * (1.0 - rt), 0.08));
            rippleGrad = (dp / dist) * min(slope, 2.2);
            rippleBand = 1.0 - rt;
        }
    }

    // 2. Subtle optical glass edge refraction around the full viewport (monotonic: never folds 1px stars)
    vec2 halfBox = boxSize * 0.5;
    float cornerR = clamp(min(boxSize.x, boxSize.y) * 0.02, 12.0, 26.0);
    float bevelW = clamp(min(boxSize.x, boxSize.y) * 0.048, 30.0, 58.0);
    float dEdge = sdRoundBox(p - halfBox, halfBox, cornerR);
    float tEdge = clamp(-dEdge / bevelW, 0.0, 1.0);
    vec2 edgeN2 = gradRoundBox(p - halfBox, halfBox, cornerR);
    float edgeSlope = 0.0;
    if (tEdge < 1.0) {
        float u = 1.0 - tEdge;
        // Smooth monotonic optical edge curve (zero caustic fold on point light sources)
        edgeSlope = u * u * (3.0 - 2.0 * u) * 0.62;
    }

    // 3. Optional subtle focal optical lens ring (e.g. behind Atom launcher's glass core: refraction only)
    vec2 domeGrad = vec2(0.0);
    float domeBand = 0.0;
    if (lensRadius > 4.0) {
        vec2 dl = p - lensCenter;
        float lr = length(dl);
        float outerR = lensRadius * 1.45;
        if (lr < outerR && lr > 0.5) {
            float u = lr / outerR;
            float ring = exp(-pow((u - 0.80) / 0.22, 2.0));
            domeGrad = (dl / lr) * ring * 0.30;
            domeBand = ring;
        }
    }

    // 4. Combine 3D optical surface normal (curved edge + cast-glass wave body + ripple + core lens)
    vec2 bodyN = liquidBodyGrad(qt_TexCoord0) * 0.095;
    vec2 specGrad = edgeN2 * edgeSlope + bodyN + rippleGrad * 0.95;
    vec3 N = normalize(vec3(specGrad + domeGrad, 1.0));
    vec3 Ns = normalize(vec3(specGrad, 1.0));
    vec3 I = vec3(0.0, 0.0, -1.0);

    // 5. True Snell's Law refraction + RGB spectral chromatic dispersion
    vec3 refR = refract(I, N, IOR_R);
    vec3 refG = refract(I, N, IOR_G);
    vec3 refB = refract(I, N, IOR_B);

    vec2 baseUv = vec2(p.x / max(screenSize.x, 1.0), (p.y + offsetY) / max(screenSize.y, 1.0));
    float dispScale = 30.0 / max(min(screenSize.x, screenSize.y), 1.0);
    // Subtle prismatic dispersion along curved rim, ripple meniscus, and optical glass undulations
    float chromaBoost = 1.0 + 1.35 * max((1.0 - tEdge) * 0.75, max(rippleBand, domeBand * 0.65));
    vec2 uvG = reflectUv(baseUv + refG.xy * dispScale);
    vec2 uvR = reflectUv(baseUv + mix(refG.xy, refR.xy, chromaBoost) * dispScale);
    vec2 uvB = reflectUv(baseUv + mix(refG.xy, refB.xy, chromaBoost) * dispScale);

    // Sample refracted sharp wallpaper & refracted pre-blurred frost
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

    // Optical glass clarity: refracted silky frost across the sheet, crisp crystal meniscus on ripples & bevels
    float rimClarity = smoothstep(0.0, 0.9, 1.0 - tEdge) * 0.28
                     + rippleBand * 0.55
                     + domeBand * 0.24;
    float frostMix = clamp(0.68 - rimClarity * 0.45, 0.36, 0.72);
    vec3 glassCol = mix(sharpCol, blurCol, frostMix);
    glassCol = liftVibrancy(glassCol, 1.20);

    // 6. Schlick Fresnel + dual diagonal studio specular highlights (on perimeter bevel & ripple, not core dome)
    float NdotV = clamp(Ns.z, 0.0, 1.0);
    float fresnel = 0.04 + 0.96 * pow(1.0 - NdotV, 4.0);

    vec3 L1 = normalize(vec3(-0.55, -0.78, 0.45));   // upper-left key light
    vec3 L2 = normalize(vec3(0.58, 0.74, 0.38));    // bottom-right internal bounce caustic
    vec3 H1 = normalize(L1 + vec3(0.0, 0.0, 1.0));
    vec3 H2 = normalize(L2 + vec3(0.0, 0.0, 1.0));
    float spec1 = pow(max(dot(Ns, H1), 0.0), 40.0);
    float spec2 = pow(max(dot(Ns, H2), 0.0), 26.0);

    // Delicate luminous bezel rim line
    float rimLine = smoothstep(-2.4, -0.4, dEdge) * (1.0 - smoothstep(-0.4, 0.8, dEdge));
    float topLeftBias = clamp(0.55 - 0.45 * (qt_TexCoord0.x * 0.8 + qt_TexCoord0.y * 0.9), 0.15, 1.0);

    // Adaptive glass body tint (keeps dark themes smoked crystal, light themes sunlit crystal)
    vec3 tintTarget = isLight > 0.5 ? mix(vec3(0.96, 0.97, 1.0), veilColor.rgb, 0.35)
                                    : veilColor.rgb;
    float tintAmt = clamp(veilAlpha * (isLight > 0.5 ? 0.52 : 0.78), 0.0, 0.72);
    vec3 col = mix(glassCol, tintTarget, tintAmt);

    // Add optical Fresnel sheen, specular caustics, and subtle edge luminance
    vec3 rimTint = mix(vec3(1.0), accentColor.rgb, 0.22);
    col += vec3(1.0) * (spec1 * (isLight > 0.5 ? 0.42 : 0.34));
    col += rimTint * (spec2 * (isLight > 0.5 ? 0.20 : 0.18));
    col += rimTint * (fresnel * (isLight > 0.5 ? 0.30 : 0.26));
    col += vec3(1.0) * (rimLine * topLeftBias * (isLight > 0.5 ? 0.48 : 0.32));
    // Ripple wavefront bright liquid caustic
    col += vec3(1.0) * (rippleBand * rippleBand * 0.36);

    col = clamp(col, 0.0, 1.0);
    fragColor = vec4(col, 1.0) * mask * qt_Opacity;
}
