shader_type sky;

// A soft daytime gradient: pale warm haze at the horizon, clear blue overhead, a faint sun glow.
uniform vec3 zenith : source_color = vec3(0.24, 0.5, 0.86);
uniform vec3 haze : source_color = vec3(0.95, 0.86, 0.74);
uniform vec3 sunDirection = vec3(0.5, 0.75, 0.43);

void fragment() {
    float height = clamp(EYEDIR.y, 0.0, 1.0);
    vec3 color = mix(haze, zenith, pow(height, 0.6));
    float sun = max(dot(normalize(EYEDIR), normalize(sunDirection)), 0.0);
    color += vec3(1.0, 0.85, 0.6) * (pow(sun, 64.0) * 0.8 + pow(sun, 6.0) * 0.12);
    COLOR = color;
}
