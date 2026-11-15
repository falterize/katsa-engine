shader_type spatial;
render_mode unshaded;

// Reads the opaque scene behind the surface (hint_screen_texture) and swaps red with blue.
uniform sampler2D screen_tex : hint_screen_texture;
uniform float amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
    vec3 behind = texture(screen_tex, SCREEN_UV).rgb;
    ALBEDO = mix(behind, behind.bgr, amount);
}
