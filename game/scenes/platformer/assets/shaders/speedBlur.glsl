shader_type canvas_item;

// Spatial radial speed blur. This is not temporal, velocity-buffer motion blur.
uniform float strength : hint_range(0.0, 0.065) = 0.0;

void fragment() {
    vec2 d = (UV - vec2(0.5)) * clamp(strength, 0.0, 0.065);
    vec4 sum = vec4(0.0);
    for (int i = 0; i < 7; i++) {
        sum += Texel(TEXTURE, clamp(UV - d * (float(i) / 6.0), vec2(0.0), vec2(1.0)));
    }
    COLOR = sum / 7.0 * VERTEX_COLOR;
}
