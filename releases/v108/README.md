# Katsa v108

Stage 1 of the migration plan: frame-synchronization fixes and Camera3D projection modes. The engine still runs on LOVE 11.5; the `katsa` platform layer starts in the next stage.

- Fixed slow-motion stutter in per-tick gameplay state. Facing and animation blend weights authored in the fixed step (Stare Shooter body turn, walk/crouch blending) are now sampled with the same interpolation alpha as bodies through the new `engine/animation/stepValue.lua`. At TimeScale 0.1 the visual yaw changes on 110 of 119 frames instead of 12.
- Fixed Camera2D lagging behind interpolated Body2D visuals. `followTarget` now follows the drawn (interpolated) pose, which removes the jitter of the Ability Runner 2D sprite inside its Body2D at high refresh rates and in slow motion.
- Camera3D gained `projectionMode` (`Perspective` / `Orthographic`), `fov` and `orthoSize`; `near` and `far` are inspector fields. `fov` and the legacy `focalLength` are one lens (latest edit wins), so existing scenes render identically. Projection, pointer rays, picking, frustum culling, shadow receivers, billboards, world-space UI and debug gizmos support both modes. Software occlusion culling is skipped for orthographic cameras.
- Fixed skeleton animation looking like low FPS under TimeScale. `Animator.poseRate` was gated on scaled time, so a world at 0.5 posed every 2nd frame and at 0.1 every 10th. It now budgets poses per wall-clock second (`world.frameRealDelta`).
- Orthographic `Camera3D` zoom: new `zoom` property and `camera:zoomBy(steps)` (visible half-height `orthoSize / zoom`). Workspace shows `zoom`, `orthoSize` and `orthoNear` only in Orthographic mode; the mouse wheel zooms the free camera, which now inherits the scene camera's projection.
- Fixed orthographic cameras slicing the map when they approach the ground: clipping now starts behind the camera (`orthoNear`, default `-far`) instead of at a positive `near`.
- Test maintenance: the historical missing-manifest check now consumes its expected journal report, so the full legacy suite passes (1348 checks, previously one order-dependent failure).
- New guides: [Camera3D projection](source/docs/guides/rendering/camera3D.md) and [smoothing per-tick state](source/docs/guides/animation/stepValue.md). Updated Physics2D, testing and conventions documents.

Run `source` with LOVE 11.5 or open `Katsa-v108.love`. Previous versions are preserved. Persistent save identity remains `katsa-engine`. New focused suite: `love . --test-v108`.

See the [project README](source/README.md) for setup and guides, and [validation](validation/RESULTS.md) for checks performed on this release.
