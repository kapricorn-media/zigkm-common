#include <metal_stdlib>
#include <simd/simd.h>

#include "shader_defs.h"

using namespace metal;

constant const float2 QUAD_VERTICES[6] = {
    float2(0.0f, 0.0f),
    float2(1.0f, 0.0f),
    float2(1.0f, 1.0f),
    float2(1.0f, 1.0f),
    float2(0.0f, 1.0f),
    float2(0.0f, 0.0f)
};

float2 pixelSizeToNdc(float2 pixelSize, float2 screenSize)
{
    return pixelSize * 2.0 / screenSize;
}

float2 pixelPosToNdc(float2 pixelPos, float2 screenSize)
{
    const float2 sizeNdc = pixelSizeToNdc(pixelPos, screenSize);
    return sizeNdc - float2(1.0, 1.0);
}

float roundRectSDF(float2 pos, float2 halfSize, float radius)
{
    return length(max(abs(pos) - halfSize + radius, 0.0)) - radius;
}

struct QuadVertOutFragIn
{
    float4 position [[position]];
    float4 color;
    float2 bottomLeft;
    float2 size;
    float2 screenSize;
    float cornerRadius;
};

float getRoundRectSmoothedAlpha(QuadVertOutFragIn in)
{
    const float2 halfSize = in.size / 2.0;
    const float2 pos = float2(in.position.x, in.screenSize.y - in.position.y);
    const float2 posCentered = pos - in.bottomLeft - halfSize;
    const float distance = roundRectSDF(posCentered, halfSize, in.cornerRadius);
    const float edgeSoftness = 1.0;
    return 1.0 - smoothstep(0.0, edgeSoftness * 2.0, distance);
}

// ======== Quads ========

QuadVertOutFragIn quadOutput(
    const _QuadInstanceData data,
    constant QuadUniforms& uniforms,
    uint vid)
{
    const float2 bottomLeftNdc = pixelPosToNdc(data.bottomLeft, uniforms.screenSize);
    const float2 sizeNdc = pixelSizeToNdc(data.size, uniforms.screenSize);

    QuadVertOutFragIn out;
    out.position = float4(QUAD_VERTICES[vid] * sizeNdc + bottomLeftNdc, data.depth, 1.0);
    uint colorIndex = vid;
    if (vid == 5) {
        colorIndex = 0;
    } else if (vid >= 3) {
        colorIndex -= 1;
    }
    out.color = data.colors[colorIndex];
    out.bottomLeft = data.bottomLeft;
    out.size = data.size;
    out.screenSize = uniforms.screenSize;
    out.cornerRadius = data.cornerRadius;
    return out;
}

vertex QuadVertOutFragIn quadVertMain(
    constant QuadInstanceData* instanceData [[buffer(0)]],
    constant QuadUniforms& uniforms [[buffer(1)]],
    uint vid [[vertex_id]],
    uint iid [[instance_id]])
{
    const QuadInstanceData data = instanceData[iid];
    return quadOutput(data.quad, uniforms, vid);
}

fragment float4 quadFragMain(QuadVertOutFragIn in [[stage_in]])
{
    const float smoothedAlpha = getRoundRectSmoothedAlpha(in);
    return mix(float4(0.0, 0.0, 0.0, 0.0), in.color, smoothedAlpha);
}

// ======== Textured Quads ========

struct TexQuadVertOutFragIn
{
    QuadVertOutFragIn quad;
    float2 uv;
};

vertex TexQuadVertOutFragIn texQuadVertMain(
    constant TexQuadInstanceData* instanceData [[buffer(0)]],
    constant QuadUniforms& uniforms [[buffer(1)]],
    uint vid [[vertex_id]],
    uint iid [[instance_id]])
{
    const TexQuadInstanceData data = instanceData[iid];
    TexQuadVertOutFragIn out;
    out.quad = quadOutput(data.quad, uniforms, vid);
    out.uv = QUAD_VERTICES[vid] * data.uvSize + data.uvBottomLeft;
    return out;
}

fragment float4 texQuadFragMain(
    TexQuadVertOutFragIn in [[stage_in]],
    texture2d<half> texture [[texture(0)]])
{
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    const half4 colorSample = texture.sample(textureSampler, in.uv);

    const float smoothedAlpha = getRoundRectSmoothedAlpha(in.quad);
    const float4 colorFlat = mix(float4(0.0, 0.0, 0.0, 0.0), in.quad.color, smoothedAlpha);

    return float4(colorSample * half4(colorFlat));
}

// ======== Text (really a simplified Textured Quad) ========

struct TextVertOutFragIn
{
    float4 position [[position]];
    float4 color;
    float2 uv;
    uint32_t atlasIndex;
};

vertex TextVertOutFragIn textVertMain(
    constant TextInstanceData* instanceData [[buffer(0)]],
    constant TextUniforms& uniforms [[buffer(1)]],
    uint vid [[vertex_id]],
    uint iid [[instance_id]])
{
    const TextInstanceData data = instanceData[iid];

    TextVertOutFragIn out;
    const float2 bottomLeftNdc = pixelPosToNdc(data.bottomLeft, uniforms.screenSize);
    const float2 sizeNdc = pixelSizeToNdc(data.size, uniforms.screenSize);
    out.position = float4(QUAD_VERTICES[vid] * sizeNdc + bottomLeftNdc, data.depth, 1.0);
    out.color = data.color;
    const float atlasSize = ATLAS_SIZE;
    out.uv = QUAD_VERTICES[vid] * (data.size / (atlasSize * data.atlasScale)) + data.uvBottomLeft;
    out.atlasIndex = data.atlasIndex;
    return out;
}

fragment float4 textFragMain(
    TextVertOutFragIn in [[stage_in]],
    array<texture2d<half>, MAX_ATLASES> atlases [[texture(0)]])
{
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    const half4 colorSample = atlases[in.atlasIndex].sample(textureSampler, in.uv);
    return float4(in.color.rgb, in.color.a * colorSample.r);
}
