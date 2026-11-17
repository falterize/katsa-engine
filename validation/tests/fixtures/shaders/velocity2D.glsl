shader_type canvas_item;

uniform sampler2D motion : hint_velocity_texture;

// Shows the horizontal motion of the 3D render: 0.5 is standing still, brighter is rightwards.
void fragment() {
    COLOR = vec4(texture(motion, UV).r * 20.0 + 0.5, 0.0, 0.0, 1.0);
}
