shader_type fog;

// Runs for every sample of the volumetric fog: pulsing bands of coloured haze.
uniform float strength : hint_range(0.0, 4.0) = 2.0;
uniform vec3 glowColor : source_color = vec3(0.3, 0.55, 1.0);

void fragment() {
    float band = 0.5 + 0.5 * sin(WORLD_POSITION.x * 0.15 + TIME);
    DENSITY *= strength * band;
    ALBEDO = mix(ALBEDO, glowColor, band);
    EMISSION = glowColor * 0.02 * DISTANCE / (1.0 + DISTANCE);
}
