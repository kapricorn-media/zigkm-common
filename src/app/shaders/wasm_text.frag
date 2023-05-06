precision mediump float;

varying highp vec2 v_uv;

uniform sampler2D u_sampler;
uniform vec4 u_color;

void main()
{
    gl_FragColor = u_color;
    gl_FragColor.a *= texture2D(u_sampler, v_uv).r;
}
