shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

void fragment() {
    ALBEDO = vec3(1.0, 0.0, 0.0);
    ALPHA = 0.5;
}
