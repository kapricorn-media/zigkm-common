#version 300 es

in vec4 vi_color;
in vec4 vi_bottomLeftSize;
in vec4 vi_uvBottomLeftSize;
in vec2 vi_depthCornerRadius;
in uint vi_textureIndex;
in uint vi_isGrayscale;

out vec4 vo_color;
out vec2 vo_uv;
// flat out uint vo_textureIndex;

uniform vec2 u_screenSize;

vec2 QUAD_VERTICES[6] = vec2[](
    vec2(0, 0),
    vec2(1, 0),
    vec2(1, 1),
    vec2(1, 1),
    vec2(0, 1),
    vec2(0, 0)
);

vec2 pixelSizeToNdc(vec2 pixelSize, vec2 screenSize)
{
    return pixelSize * 2.0 / screenSize;
}

vec2 pixelPosToNdc(vec2 pixelPos, vec2 screenSize)
{
    vec2 sizeNdc = pixelSizeToNdc(pixelPos, screenSize);
    return sizeNdc - vec2(1.0, 1.0);
}

void main()
{
    vo_color = vi_color;
    vo_uv = QUAD_VERTICES[gl_VertexID] * vi_uvBottomLeftSize.zw + vi_uvBottomLeftSize.xy;
    // vo_textureIndex = vi_textureIndex;

    vec2 bottomLeftNdc = pixelPosToNdc(vi_bottomLeftSize.xy, u_screenSize);
    vec2 sizeNdc = pixelSizeToNdc(vi_bottomLeftSize.zw, u_screenSize);
    gl_Position = vec4(QUAD_VERTICES[gl_VertexID] * sizeNdc + bottomLeftNdc, 0, 1);
}
