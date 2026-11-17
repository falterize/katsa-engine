shader_type canvas_item;

// Datamosh: the picture keeps its previous frame and only moves it along the motion of the scene,
// like a video whose key frames were dropped. Whatever moves drags the old image with it; what
// stands still stays frozen. Every `interval` seconds a fresh frame is let through (the "I-frame"),
// and between them a little of the live picture leaks back in. Disabled by default (F7).
//
// `history` is this shader's own result from the previous frame and `motion` the per-pixel motion
// of the 3D render (see postProcessing.md); both are opt-in hints and cost nothing otherwise.
uniform sampler2D screen_tex : hint_screen_texture;
uniform sampler2D history : hint_history_texture;
uniform sampler2D motion : hint_velocity_texture;
uniform float drag : hint_range(0.0, 8.0) = 3.0;       // how strongly motion pushes the old image
uniform float leak : hint_range(0.0, 0.2) = 0.02;      // share of the live picture mixed in per frame
uniform float interval : hint_range(0.5, 20.0) = 6.0;  // seconds between fresh frames
uniform float blockSize : hint_range(4.0, 64.0) = 16.0; // motion is applied per block of pixels

void fragment() {
    // One motion vector per block: blocks move as a unit, the way codec macroblocks do.
    vec2 block = (floor(UV * CANVAS_SIZE / blockSize) + 0.5) * blockSize / CANVAS_SIZE;
    vec2 velocity = texture(motion, block).rg;
    vec4 live = texture(screen_tex, UV);
    vec4 old = texture(history, UV - velocity * drag);
    float fresh = step(fract(TIME / interval), 0.02);
    COLOR = mix(old, live, max(fresh, leak)) * VERTEX_COLOR;
}
