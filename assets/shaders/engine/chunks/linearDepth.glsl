// linear_depth(raw): view-space distance along the camera axis for a raw value read from a
// hint_depth_texture sampler (0..1). Works for perspective and orthographic cameras. Needs the
// `projectionMatrix` uniform declared before the include; pixel stage only.
#ifdef STAGE_PIXEL
highp float linear_depth(highp float raw) {
    highp float ndc = raw * 2.0 - 1.0;
    if (projectionMatrix[3][3] > 0.5) {
        return (ndc - projectionMatrix[3][2]) / projectionMatrix[2][2];
    }
    return projectionMatrix[3][2] / (ndc - projectionMatrix[2][2]);
}
#endif
