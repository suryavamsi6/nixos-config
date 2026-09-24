#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 glowColor;
    float glowStrength;
};

void main()
{
    vec2 centered = qt_TexCoord0 * 2.0 - 1.0;
    float radius = length(centered);
    float alpha = smoothstep(1.0, 0.12, radius) * glowStrength;
    fragColor = vec4(glowColor.rgb, alpha * glowColor.a * qt_Opacity);
}
