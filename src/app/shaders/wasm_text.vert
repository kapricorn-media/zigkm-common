// per-vertex
attribute vec2 a_pos;

// per-instance
attribute vec2 a_posPixels;
attribute vec2 a_sizePixels;
attribute vec2 a_uvOffset;

uniform float u_atlasSize;
uniform float u_atlasScale;
uniform vec2 u_screenSize;
uniform float u_depth;

varying highp vec2 v_uv;

vec2 posPixelsToNdc(vec2 pos, vec2 screenSize)
{
    return pos / screenSize * 2.0 - 1.0;
}

void main()
{
    v_uv = a_pos * (a_sizePixels / (u_atlasSize * u_atlasScale)) + a_uvOffset;

    vec2 pixelPos = a_pos * a_sizePixels + a_posPixels;
    gl_Position = vec4(posPixelsToNdc(pixelPos, u_screenSize), u_depth, 1.0);
}
