// Vertical bottom fade for sharp game art (Scene.qml): solid down to 55% of its height, smoothstep
// out to 0 at its bottom — lightweight single-pass layer effect (replaces MultiEffect + fadeMask).
// Build (both files are committed; Qt loads the .qsb):
//   /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o artfade.frag.qsb artfade.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    float fade = 1.0 - smoothstep(0.55, 1.0, qt_TexCoord0.y);
    fragColor = texture(source, qt_TexCoord0) * fade * qt_Opacity;
}
