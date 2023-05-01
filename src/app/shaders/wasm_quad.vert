attribute vec2 a_position;

uniform vec3 u_posPixelsDepth;
uniform vec2 u_sizePixels;
uniform vec2 u_screenSize;

varying highp vec2 v_posPixels;
varying highp vec2 v_sizePixels;
varying highp vec2 v_uv;

vec2 posPixelsToNdc(vec2 pos, vec2 screenSize)
{
    return pos / screenSize * 2.0 - 1.0;
}

void main()
{
    v_posPixels = u_posPixelsDepth.xy;
    v_sizePixels = u_sizePixels;
    v_uv = a_position;

    vec2 posPixels = a_position * u_sizePixels + u_posPixelsDepth.xy;
    gl_Position = vec4(posPixelsToNdc(posPixels, u_screenSize), u_posPixelsDepth.z, 1.0);
}
