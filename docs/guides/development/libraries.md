# Public libraries

source.engine exports node, world, ui, physics, audio, camera, renderer, input, models, resources, sceneManager, time, material, cframe, vector2, vector3, udim2 and math3d. Libraries also support direct require paths.

CFrame represents a rigid transform without scale. It supports translation, Euler angles, axis-angle, basis construction, lookAt, composition, inverse, local/world point and direction conversion, basis vectors, matrix export and spherical rotation interpolation. Vector3 supports scalar arithmetic, dot, cross, magnitude, unit and lerp. Arrays are compatible with the existing engine math. Engine forward is +Z; CFrame angles are radians, node.rotation uses degrees. Node3D:setCFrame writes its local pose and getWorldCFrame returns a rigid world frame; Node3D.size remains independent.

Resources owns images, fonts, shaders and canvases. Release scopes explicitly. Material supports world vertex/pixel injection, UI shaders and uniforms; shadow vertex code follows world vertex deformation. Time scales simulation while UI uses real time.

Audio scopes return Voice instances, support master/music/effects/ui groups, streams, pause/resume, looping and spatial mono/stereo emitters with min/max distance. Attaching a voice to a moving object updates its emitter position. Music/world sounds follow time scale; UI can remain unscaled.

Vector2 and UDim2 are array-compatible values with named components and arithmetic.
UDim2 has four Scale/Offset components. Scalar UI lengths use Vector2 Scale/Offset;
AnchorPoint uses Vector2 X/Y. UI.udim2 forwards to the same UDim2.new constructor.
See [UI layout](../ui/uiLayout.md) for units, assignment and inspector editing.

## Examples

```lua
local Vector3 = require('source.engine.math.vector3')
local CFrame = require('source.engine.math.cframe')

local a, b = Vector3.new(1, 0, 0), Vector3.new(0, 1, 0)
print(a:dot(b), a:cross(b), (a + b):unit(), a:lerp(b, 0.5))

local frame = CFrame.lookAt(Vector3.new(0, 5, 10), Vector3.new(0, 0, 0))
print(frame:pointToObjectSpace(Vector3.new(0, 0, 0)))   -- the origin as the camera sees it
local half = CFrame.new(0, 0, 0):lerp(frame, 0.5)

scene.audio:play('assets/audio/effects/click.wav', { group = 'ui', volume = 0.6 })
scene.audio:play('assets/audio/effects/hit.wav', { position = { 4, 0, 2 }, maxDistance = 60 })
```
