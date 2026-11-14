shader_type sky;

uniform vec3 horizon : source_color = vec3(1.0, 0.5, 0.25);
uniform float pulse : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    float height = clamp(EYEDIR.y, 0.0, 1.0);
    COLOR = mix(horizon * (0.75 + pulse * sin(TIME)), SKY_COLOR, smoothstep(0.0, 0.4, height));
}
