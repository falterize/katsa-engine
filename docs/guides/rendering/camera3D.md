# Camera3D projection

Camera3D supports two projection modes selected by `projectionMode`:

| Mode | Lens property | Behavior |
| --- | --- | --- |
| `Perspective` (default) | `fov` | Distant objects shrink. `fov` is the vertical field of view in degrees (1..179). |
| `Orthographic` | `orthoSize` | Constant scale at every depth. `orthoSize` is half of the visible height in world units; the width follows the aspect ratio. |

`near` and `far` apply to both modes and must satisfy `0 < near < far`. Workspace shows `fov` only
for Perspective and `orthoSize` only for Orthographic.

```lua
local camera = world:create('Camera3D', { fov = 70, near = 0.5, far = 800 })
camera.projectionMode = 'Orthographic'
camera.orthoSize = 12 -- 24 world units visible from top to bottom
```

## fov and focalLength

`fov` and the legacy `focalLength` describe the same lens (`focalLength = referenceHeight / (2 * tan(fov / 2))`).
Assign either one; the most recently changed value wins and the other is derived. Scenes written
against `focalLength` keep their exact previous projection, and a camera created without `fov`
reports the equivalent angle.

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
