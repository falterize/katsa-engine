shader_type spatial;
render_mode unshaded, shadows_disabled;

// Editor overlays (gizmos, the selection outline) must stay visible inside and behind other
// objects. The clip depth is squeezed into the first sliver of the depth range: every scene
// fragment is farther, so the depth test always passes, while the overlay's own parts keep
// their order among themselves.
void vertex() {
    vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    clip.z = -clip.w + (clip.z + clip.w) * 0.002;
    POSITION = clip;
}
