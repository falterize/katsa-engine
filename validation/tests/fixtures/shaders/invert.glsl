shader_type canvas_item;

void fragment() {
    COLOR = vec4(vec3(COLOR.a) - COLOR.rgb, COLOR.a);
}
