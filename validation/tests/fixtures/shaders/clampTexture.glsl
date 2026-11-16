shader_type spatial;
render_mode unshaded;

uniform sampler2D tex : repeat_disable;
uniform sampler2D tiled : repeat_enable;

void fragment() {
    ALBEDO = texture(tex, vec2(0.5)).rgb + texture(tiled, vec2(0.5)).rgb * 0.0;
}
