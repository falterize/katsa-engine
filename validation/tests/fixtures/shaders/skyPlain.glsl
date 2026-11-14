shader_type sky;

// Never reads SKY_COLOR: the driver drops the sky image uniforms.
void fragment() {
    COLOR = vec3(0.0, 1.0, 0.0);
}
