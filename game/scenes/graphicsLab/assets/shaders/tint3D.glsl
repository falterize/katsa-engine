shader_type spatial;

// Multiplies the surface colour before lighting.
uniform vec3 tintEffect : source_color = vec3(1.0, 1.0, 1.0);

void fragment() {
    ALBEDO *= tintEffect;
}
