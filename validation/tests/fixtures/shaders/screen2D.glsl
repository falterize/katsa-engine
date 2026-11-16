shader_type canvas_item;

uniform sampler2D behind : hint_screen_texture;

// Swaps red and blue of the snapshot through the screen sampler instead of TEXTURE.
void fragment() {
    vec4 c = texture(behind, UV);
    COLOR = vec4(c.b, c.g, c.r, c.a);
}
