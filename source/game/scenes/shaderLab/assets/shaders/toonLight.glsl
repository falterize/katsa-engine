shader_type spatial;

// Replaces the default lighting with a three step toon ramp.
uniform float steps : hint_range(2.0, 8.0) = 3.0;

void light() {
    float wrapped = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
    float banded = floor(wrapped * steps) / (steps - 1.0);
    DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * min(banded, 1.0);
}
