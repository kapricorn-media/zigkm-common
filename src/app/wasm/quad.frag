#version 300 es

precision highp float;

in vec4 vo_color;
in vec2 vo_uv;
// flat in uint vo_textureIndex;

out vec4 fo_color;

uniform sampler2D u_textures[8];

void main()
{
    vec4 c = texture(u_textures[0], vo_uv);
    fo_color = vo_color;
}
