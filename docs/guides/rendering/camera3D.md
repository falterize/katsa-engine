# Camera3D projection

Camera3D supports two projection modes selected by `projectionMode`:

| Mode | Lens property | Behavior |
| --- | --- | --- |
| `Perspective` (default) | `fov` | Distant objects shrink. `fov` is the vertical field of view in degrees (1..179). |
| `Orthographic` | `orthoSize`, `zoom` | Constant scale at every depth. The visible half-height in world units is `orthoSize / zoom`; the width follows the aspect ratio. |

`far` applies to both modes. Perspective requires `0 < near < far`. Workspace shows `fov` and `near`
only for Perspective, and `orthoSize` and `orthoNear` only for Orthographic.

```lua
local camera = world:create('Camera3D', { fov = 70, near = 0.5, far = 800 })
camera.projectionMode = 'Orthographic'
camera.orthoSize = 12 -- 24 world units visible from top to bottom at zoom 1
camera.zoom = 2 -- magnify: 12 world units visible from top to bottom
camera:zoomBy(1) -- one wheel step in: zoom * 1.1, clamped to 0.01..1000
```

`zoom` and `orthoSize` exist only for orthographic cameras: Workspace hides both (and `orthoNear`) in Perspective
mode and shows `fov` and `near` instead. Use `orthoSize` for the framing a scene authors and `zoom` for runtime
magnification. The mouse wheel zooms the free debug camera while it is orthographic, and the free camera
inherits the scene camera's projection, `orthoSize`, `orthoNear` and `zoom`.

## fov and focalLength

`fov` and the legacy `focalLength` describe the same lens (`focalLength = referenceHeight / (2 * tan(fov / 2))`).
Assign either one; the most recently changed value wins and the other is derived. Scenes written
against `focalLength` keep their exact previous projection, and a camera created without `fov`
reports the equivalent angle.

## Orthographic clipping

An orthographic camera has no eye point: its position is the center of the view plane, and geometry
behind that plane is legitimately visible. A tilted camera near the ground therefore sees floor that
lies "behind" its position. If clipping started at a positive `near`, that part of the map would be
sliced off along a straight line and more would disappear the closer the camera got to the ground.

`orthoNear` is the clip start along the view direction. When it is unset (the default) clipping starts
at `-far`, so nothing behind the camera plane is cut. Set it to a number to restore a hard near plane.
`camera.nearClip` always reports the value in effect for either mode. To zoom an orthographic
camera change `orthoSize`; moving the camera along its view direction does not change the scale.

## Behavior in orthographic mode

- Mesh and particle shaders receive the orthographic `viewProjection`; depth maps near to -1 and far to +1.
- `camera:project(point)`, `camera:screenRay(x, y)`, picking, pointer routing and world-space UI use the
  parallel projection. Orthographic pointer rays share the view direction and start on the view plane.
- Frustum culling uses constant side planes. Shadow receiver bounds are a box rather than a pyramid.
- `camera:pixelsPerUnitAt(depth)` returns pixels per world unit for either mode. Billboards with
  `sizeMode = 'Screen'` therefore keep a constant pixel size.
- The sky still draws with the camera's `fov` lens because it is infinitely far away.
- Software occlusion culling projects with a perspective divide and is skipped while a camera is
  orthographic. Frustum, distance and shadow culling remain active.

Custom code that projects points should call `camera:project`, `camera:viewToScreen`,
`camera:screenRay` or `camera:pixelsPerUnitAt` instead of using `camera.focal` directly.
`camera.focal` remains available as the perspective lens value.

See the focused checks in `source/tests/versions/v108/camera3D.lua` (run with `love . --test-v108`).
