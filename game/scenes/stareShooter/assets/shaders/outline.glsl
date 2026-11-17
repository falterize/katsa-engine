shader_type canvas_item;

// Outline of the 3D objects in the Shader2D's `viewLayers` (here the group Outlined, the
// character): `layer` is a render of only those layer groups, transparent where none was
// drawn, so the line follows the object and ignores everything else. `layer_depth` is that
// render's depth (unused here, but a shader may compare it with `hint_depth_texture`).
uniform sampler2D screen_tex : hint_screen_texture;
uniform sampler2D layer : hint_layer_texture;
uniform sampler2D layer_depth : hint_layer_depth_texture;
uniform float thickness : hint_range(1.0, 8.0) = 2.0;
uniform vec3 lineColor = vec3(1.0, 0.75, 0.15);

void fragment() {
    vec2 texel = thickness / CANVAS_SIZE;
    float inside = texture(layer, UV).a;
    float around = 0.0;
    for (int i = 0; i < 8; i++) {
        float angle = 6.2831853 * float(i) / 8.0;
        around = max(around, texture(layer, UV + vec2(cos(angle), sin(angle)) * texel).a);
    }
    float edge = clamp(around - inside, 0.0, 1.0);
    vec4 picture = texture(screen_tex, UV);
    COLOR = vec4(mix(picture.rgb, lineColor, edge), picture.a);
}
