shader_type fog;

uniform float strength : hint_range(0.0, 4.0) = 1.5;
uniform vec3 glowColor : source_color = vec3(0.2, 0.5, 1.0);

void fragment() {
    float wave = 0.5 + 0.5 * sin(WORLD_POSITION.x * 0.3 + TIME);
    DENSITY *= strength * wave;
    ALBEDO = mix(ALBEDO, glowColor, wave);
    EMISSION = glowColor * 0.02 * DISTANCE / (1.0 + DISTANCE);
}
