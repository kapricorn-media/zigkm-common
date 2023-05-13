precision mediump float;

uniform vec2 u_framePos;
uniform vec2 u_frameSize;
uniform float u_cornerRadius;
uniform vec4 u_color;

float roundedBoxSDF(vec2 center, vec2 size, float radius) {
    return length(max(abs(center) - size + radius, 0.0)) - radius;
}

void main()
{
    float edgeSoftness = 1.0;
    float distance = roundedBoxSDF(
        gl_FragCoord.xy - u_framePos - u_frameSize / 2.0,
        u_frameSize / 2.0,
        u_cornerRadius
    );
    float smoothedAlpha = smoothstep(0.0, edgeSoftness * 2.0, distance);

    gl_FragColor = vec4(u_color.rgb, u_color.a * smoothedAlpha);
}
