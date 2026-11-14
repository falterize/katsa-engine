shader_type sky;

// Replaces the background: a warm horizon that fades into the configured sky colour.
uniform vec3 horizon : source_color = vec3(1.0, 0.45, 0.2);
uniform float pulse : hint_range(0.0, 0.5) = 0.15;

void fragment() {
    float height = clamp(EYEDIR.y, 0.0, 1.0);
    vec3 glow = horizon * (0.85 + pulse * sin(TIME));
    COLOR = mix(glow, SKY_COLOR, smoothstep(0.0, 0.45, height));
}
