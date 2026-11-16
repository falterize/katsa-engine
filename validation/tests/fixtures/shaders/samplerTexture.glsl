shader_type spatial;
render_mode unshaded;

uniform sampler2D tex : filter_nearest;

void fragment() {
    ALBEDO = texture(tex, vec2(0.5)).rgb;
}
