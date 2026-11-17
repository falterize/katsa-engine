shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture;
uniform sampler2D previous : hint_history_texture;

// Half of the new picture, half of what this shader showed on the previous frame.
void fragment() {
    COLOR = mix(texture(previous, UV), texture(screen_tex, UV), 0.5);
}
