shader_type canvas_item;

// Datamosh look: blocks of the picture stop following the scene, slide along a random direction and
// smear, like video frames whose motion data went wrong. Disabled by default (F7 or the Workspace).
//
// A real datamosh keeps the previous frame and applies motion vectors to it; the engine has no
// history buffer (see postProcessing.md), so this fakes it from the current frame only: every block
// keeps one random offset for `hold` seconds, then picks a new one.
uniform float blockSize : hint_range(8.0, 160.0) = 48.0;   // size of a block, in pixels
uniform float amount : hint_range(0.0, 1.0) = 0.45;        // share of blocks that go wrong
uniform float slide : hint_range(0.0, 4.0) = 1.5;          // how far a block slides, in block sizes
uniform float smear : hint_range(0.0, 1.0) = 0.6;          // 1 stretches the block into one colour
uniform float hold : hint_range(0.05, 2.0) = 0.35;         // seconds a block keeps its offset

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
    vec2 pixel = UV * CANVAS_SIZE;
    vec2 block = floor(pixel / blockSize);
    float tick = floor(TIME / hold);
    // Neighbouring blocks share a tick offset so the damage comes in clumps, not as noise.
    vec2 clump = floor(block / 2.0);
    float roll = hash(clump + tick * 7.31);
    vec2 uv = UV;
    if (roll < amount) {
        vec2 direction = vec2(hash(clump + tick * 1.7), hash(clump.yx + tick * 3.1)) - 0.5;
        vec2 center = (block + 0.5) * blockSize;
        // Stretch the block towards its centre (smear), then move it along the direction.
        vec2 source = mix(pixel, center, smear) + direction * 2.0 * slide * blockSize;
        uv = clamp(source / CANVAS_SIZE, vec2(0.0), vec2(1.0));
    }
    COLOR = texture(TEXTURE, uv) * VERTEX_COLOR;
}
