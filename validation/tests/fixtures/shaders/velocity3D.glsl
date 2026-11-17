shader_type spatial;
render_mode unshaded;

uniform sampler2D motion : hint_velocity_texture;

// Shows the horizontal motion of what is behind the mesh: 0.5 is standing still.
void fragment() {
    ALBEDO = vec3(texture(motion, SCREEN_UV).r * 20.0 + 0.5, 0.0, 0.0);
}
