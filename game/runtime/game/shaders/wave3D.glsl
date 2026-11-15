shader_type spatial;

// Ripples the mesh along Y and pulses the surface toward a glow colour.
uniform float waveAmplitude : hint_range(0.0, 1.0) = 0.08;
uniform vec3 glowColor : source_color = vec3(1.0, 0.35, 0.08);

void vertex() {
    VERTEX.y += sin(TIME * 2.0 + VERTEX.x * 4.0) * waveAmplitude;
}

void fragment() {
    ALBEDO = mix(ALBEDO, glowColor, 0.25 + 0.2 * sin(TIME * 2.0));
}
