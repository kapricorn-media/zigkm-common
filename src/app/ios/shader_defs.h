#pragma once

#ifndef __METAL_VERSION__

#include <stddef.h>
#include <stdint.h>

typedef struct {
    float x;
    float y;
} float2;

typedef struct {
    float x;
    float y;
    float z;
} packed_float3;

typedef struct {
    float x;
    float y;
    float z;
    float w;
} float4;

#define MAX_QUADS 16 * 1024
#define MAX_TEX_QUADS 64
#define MAX_TEXT_INSTANCES 64 * 1024

#endif

#define MAX_ATLASES 8
#define ATLAS_SIZE 2048

// TODO rethink this struct? is "float4 colors[4]" necessary?
typedef struct {
    float4 colors[4]; // corner colors: 0,0 | 1,0 | 1,1 | 0,1
    float2 bottomLeft;
    float2 size;
    float depth;
    float cornerRadius;
    float2 _pad;
} _QuadInstanceData;

struct QuadInstanceData
{
    _QuadInstanceData quad;
};

struct QuadUniforms
{
    float2 screenSize;
};

struct TexQuadInstanceData
{
    _QuadInstanceData quad;
    float2 uvBottomLeft;
    float2 uvSize;
};

struct TextInstanceData
{
    float4 color;
    float2 bottomLeft;
    float2 size;
    float2 uvBottomLeft;
    uint32_t atlasIndex;
    float depth;
    float atlasScale;
    packed_float3 _pad;
};

struct TextUniforms
{
    // float4 color;
    float2 screenSize;
    // float depth;
    // float atlasScale;
};
