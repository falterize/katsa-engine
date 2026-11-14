shader_type spatial;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture;
uniform sampler2D depth_tex : hint_depth_texture;
uniform float amount : hint_range(0.0, 1.0) = 1.0;

// Shows the scene behind the mesh with red and blue swapped; depth tints the green channel.
void fragment() {
    vec3 behind = texture(screen_tex, SCREEN_UV).rgb;
    float depth = texture(depth_tex, SCREEN_UV).r;
    ALBEDO = mix(behind, vec3(behind.b, depth * 0.0 + behind.g, behind.r), amount);
}
