shader_type canvas_item;

uniform sampler2D depth_tex : hint_depth_texture;

// Paints the view distance of the 3D render under the interface, in units of 100.
void fragment() {
    COLOR = vec4(vec3(linear_depth(texture(depth_tex, UV).r) / 100.0), 1.0);
}
