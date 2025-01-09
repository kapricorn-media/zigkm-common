#version 300 es

#define NUM_TEXTURES 8

precision highp float;

in vec4 vo_color;
in vec4 vo_bottomLeftSize;
in float vo_cornerRadius;
in vec2 vo_uv;
flat in uvec2 vo_textureIndexMode;

out vec4 fo_color;

uniform sampler2D u_textures[NUM_TEXTURES];

// TODO: this effectively samples ALL textures and masks the result, which is not great. Options:
// - split into multiple draw calls
// - use array textures, potentially blowing up individual texture sizes
// - use a combination of array textures + atlases, to combine smaller textures into 1
vec4 sampleTextureIndex(uint index, vec2 uv)
{
    vec4 samples[NUM_TEXTURES] = vec4[](
        texture(u_textures[0], uv),
        texture(u_textures[1], uv),
        texture(u_textures[2], uv),
        texture(u_textures[3], uv),
        texture(u_textures[4], uv),
        texture(u_textures[5], uv),
        texture(u_textures[6], uv),
        texture(u_textures[7], uv)
    );
    return samples[index];
}

float roundRectSDF(vec2 pos, vec2 halfSize, float radius)
{
    return length(max(abs(pos) - halfSize + radius, 0.0)) - radius;
}

float getRoundRectSmoothedAlpha(vec4 fragCoord, vec2 bottomLeft, vec2 size, float cornerRadius)
{
    float edgeSoftness = 1.0;

    float distance = roundRectSDF(
        fragCoord.xy - bottomLeft - size / 2.0,
        size / 2.0,
        cornerRadius
    );
    return 1.0 - smoothstep(0.0, edgeSoftness * 2.0, distance);
}

void main()
{
    vec4 colorSample = sampleTextureIndex(vo_textureIndexMode.x, vo_uv);

    float smoothedAlpha = getRoundRectSmoothedAlpha(gl_FragCoord, vo_bottomLeftSize.xy, vo_bottomLeftSize.zw, vo_cornerRadius);
    vec4 colorFlat = vec4(vo_color.rgb, vo_color.a * smoothedAlpha);

    if (vo_textureIndexMode.y == uint(1)) {
        fo_color = colorSample * colorFlat;
    } else if (vo_textureIndexMode.y == uint(2)) {
        fo_color = vec4(colorFlat.rgb, colorFlat.a * colorSample.r);
    } else {
        fo_color = colorFlat;
    }
}
