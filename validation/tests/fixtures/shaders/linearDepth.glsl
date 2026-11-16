shader_type spatial;
render_mode unshaded;

uniform sampler2D depth_tex : hint_depth_texture;

// Writes the view distance of the scene behind the mesh, in units of 100.
void fragment() {
    ALBEDO = vec3(linear_depth(texture(depth_tex, SCREEN_UV).r) / 100.0);
}
