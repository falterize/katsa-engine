shader_type canvas_item;

// Pulses the interface toward an accent colour.
uniform vec3 accent : source_color = vec3(0.25, 0.85, 1.0);

void fragment() {
    float pulse = 0.12 + 0.10 * sin(TIME * 2.0);
    COLOR.rgb = mix(COLOR.rgb, accent, pulse);
}
