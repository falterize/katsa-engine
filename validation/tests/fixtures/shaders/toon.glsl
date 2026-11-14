shader_type spatial;

void light() {
    float wrapped = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
    DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * floor(wrapped * 3.0) / 3.0;
}
