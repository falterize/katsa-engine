shader_type canvas_item;

// Datamosh: the picture keeps its previous frame and only moves it along the motion of the scene,
// like a video whose key frames were dropped. Where something moves, the old pixels are pushed
// along its motion vector, whole pixels at a time and one vector per block (like a codec's
// macroblocks), so edges tear and colours smear instead of blurring. Where nothing moves, the old
// picture stays. Move the camera, the character or an object to tear it. Disabled by default (F7).
//
// `history` is this shader's own result from the previous frame and `motion` the per-pixel motion
// of the 3D render (see postProcessing.md); both are opt-in hints and cost nothing otherwise.
//
// Without `pin` the live picture leaks back in slowly (`leak`, plus a soft swell every `interval`
// seconds, `heal`), so the damage builds and fades. `pin` at 1 lets nothing of the live picture in:
// the frame on screen at that moment becomes the reference that motion keeps tearing (F8 in the
// demo). Back at 0 it heals again.
uniform sampler2D screen_tex : hint_screen_texture;
uniform sampler2D history : hint_history_texture;
uniform sampler2D motion : hint_velocity_texture;
uniform float drag : hint_range(0.0, 16.0) = 2.0;       // pixels pushed per pixel of real motion
uniform float push : hint_range(0.0, 24.0) = 2.0;       // at least this many pixels per frame where anything moves
uniform float blockSize : hint_range(2.0, 64.0) = 16.0; // one motion vector per block of pixels
uniform float meshBoost : hint_range(0.0, 8.0) = 2.0;   // extra push on moving objects (not camera motion)
uniform float pin : hint_range(0.0, 1.0) = 0.0;         // 1 holds the current frame as the reference
uniform float leak : hint_range(0.0, 0.2) = 0.01;       // share of the live picture mixed in per frame
uniform float heal : hint_range(0.0, 0.3) = 0.03;       // extra leak at the top of each swell
uniform float interval : hint_range(1.0, 30.0) = 8.0;   // seconds between swells

void fragment() {
    vec2 size = CANVAS_SIZE;
    vec2 pixel = floor(UV * size);
    // One vector per block, read at the block centre.
    vec2 blockUv = (floor(pixel / blockSize) + 0.5) * blockSize / size;
    vec4 m = texture(motion, blockUv);
    vec2 moved = m.rg * size;                 // pixels per frame
    float speed = length(moved);
    vec2 shift = vec2(0.0);
    if (speed > 0.02) {
        float pixels = max(speed * drag, push) * (1.0 + meshBoost * m.b);
        shift = floor(moved / speed * pixels + 0.5);   // whole pixels keep the edges crisp
    }
    vec2 source = clamp((pixel + 0.5 - shift) / size, vec2(0.0), vec2(1.0));
    vec4 old = texture(history, source);
    vec4 live = texture(screen_tex, UV);
    float swell = pow(0.5 - 0.5 * cos(TIME * 6.2831853 / interval), 6.0);
    COLOR = mix(old, live, mix(leak + heal * swell, 0.0, pin)) * VERTEX_COLOR;
}
