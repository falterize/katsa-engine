shader_type canvas_item;

// Datamosh: the picture keeps its previous frame and only moves it along the motion of the scene,
// like a video whose key frames were dropped. Whatever moves drags the old image with it; what
// stands still stays frozen. The live picture only leaks back in slowly (`leak`), with a soft swell
// every `interval` seconds (`heal`) so the damage fades and builds instead of snapping. There is no
// hard reset: `heal = 0` lets the damage stay until the scene moves it. Disabled by default (F7).
//
// `history` is this shader's own result from the previous frame and `motion` the per-pixel motion
// of the 3D render (see postProcessing.md); both are opt-in hints and cost nothing otherwise.
uniform sampler2D screen_tex : hint_screen_texture;
uniform sampler2D history : hint_history_texture;
uniform sampler2D motion : hint_velocity_texture;
uniform float drag : hint_range(0.0, 8.0) = 3.0;       // how strongly motion pushes the old image
uniform float leak : hint_range(0.0, 0.2) = 0.02;      // share of the live picture mixed in per frame
uniform float heal : hint_range(0.0, 0.3) = 0.05;      // extra leak at the top of each swell
uniform float interval : hint_range(1.0, 30.0) = 8.0;  // seconds between swells
uniform float blockSize : hint_range(4.0, 64.0) = 16.0; // motion is applied per block of pixels

void fragment() {
    // One motion vector per block: blocks move as a unit, the way codec macroblocks do.
    vec2 block = (floor(UV * CANVAS_SIZE / blockSize) + 0.5) * blockSize / CANVAS_SIZE;
    vec2 velocity = texture(motion, block).rg;
    vec4 live = texture(screen_tex, UV);
    vec4 old = texture(history, UV - velocity * drag);
    float swell = pow(0.5 - 0.5 * cos(TIME * 6.2831853 / interval), 6.0);
    COLOR = mix(old, live, leak + heal * swell) * VERTEX_COLOR;
}
