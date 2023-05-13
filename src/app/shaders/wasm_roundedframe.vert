attribute vec2 a_position;

uniform vec3 u_posPixelsDepth;
uniform vec2 u_sizePixels;
uniform vec2 u_screenSize;

vec2 posPixelsToNdc(vec2 pos, vec2 screenSize)
{
    return pos / screenSize * 2.0 - 1.0;
}

void main()
{
    vec2 posPixels = a_position * u_sizePixels + u_posPixelsDepth.xy;
    gl_Position = vec4(posPixelsToNdc(posPixels, u_screenSize), u_posPixelsDepth.z, 1.0);
}
