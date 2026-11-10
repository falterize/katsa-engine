# Independent worlds and ViewportFrame

Properties use the engine's lowerCamelCase convention. World3D.CurrentCamera is
also accepted as an alias of currentCamera.

```lua
local frame = scene.ui:create('ViewportFrame', {
    position = { 0, 20, 0, 100 },
    size = { 0, 360, 0, 240 },
    renderScale = 1,
}, scene.ui.content)
local root = scene.ui:create('World3D', { name = 'PreviewWorld' }, frame)
local camera = root:create('Camera3D', { position = { 0, 30, -100 } })
root.currentCamera = camera
root._world.environment.ambient = { 120, 140, 180 }
root._world.environment.sky.enabled = false
root:create('Mesh3D', { position = { 0, 10, 30 }, size = { 20, 20, 20 } })
local overlay = root:create('World2D', { name = 'PreviewUI' })
local preview = overlay:button({
    position = { 0, 8, 1, -40 },
    size = { 0, 100, 0, 32 },
    text = 'Preview input',
}, overlay.content)
preview:connect('press', function()
    print('Pressed')
end)
```

World3D roots expose create(type, properties, parent), currentCamera and update(dt).
The existing world service and world.root remain available. Only a live Camera3D
belonging to that same world can be assigned. Assign nil to suspend 3D drawing
while retaining World2D overlays. Workspace uses a camera node selector.

A ViewportFrame owns at most one World3D. Its world is a scene/resource boundary
with independent cameras, lighting, particles, custom types and physics. Its
resource scope shares immutable assets with the scene cache. Destroying the frame
destroys its world and releases targets/subscriptions. Moving its world between
different host scene scopes is rejected.

renderScale is 0.25..2; target pixels are ceil(resolved frame pixels * scale).
World2D resolves against these target dimensions. Display and pointer coordinates
use the same scale; reducing renderScale also changes pixel-offset widget sizes.
autoUpdate defaults true. Visible, enabled frames tick their world using their
owning UI's dt. With autoUpdate=false, call root:update(dt) explicitly. Hidden or
disabled frames suspend automatic updates. Hidden frames do not draw; disabled
widgets retain the existing UI rendering semantics.

Environment is automatically created directly beneath every World3D and World2D.
It owns the categorized Debug and particle settings; 3D also owns lighting, sky,
fog, shadows and rendering settings.
Exactly one is required; moving, deleting alone or duplicating it is rejected.
It owns ambient, brightness, toneMapping, exposure and the existing sun, shadows,
lightSettings, sky, fog and gizmos settings. world.environment references this same
node for compatibility. Each world has independent mutable environment settings.

World2D is the screen UI owner beneath World3D; its CanvasGroups/widgets/modifiers
retain their API. ScreenUI is an alias of the same class. Game scenes draw their
main World2D explicitly; ViewportFrame draws its own overlays. In-frame widgets
receive pointer capture/release/cancellation. Unhandled taps can activate that
world's ClickDetector3D. Camera dragging/gameplay controls must be authored in code.
BillboardUI and SurfaceUI render inside previews; their separate surface input
routing is not forwarded by ViewportFrame in this release. Offscreen worlds do
not replace the main audio listener. Authored scripts must control model animation,
interaction sources and audio. Existing effects render through the same pipeline;
this does not introduce absent systems such as full skeletal animation.

Each visible viewport adds a full scene pass, color/depth target, UI canvas and
shadow atlas. Reduce preview sizes/counts, renderScale and shadow/light budgets
on mobile. No phone FPS target is promised.

## Adornee

ClickDetector3D.adornee selects the Node3D (a mesh or a group of meshes) tested against the nearest raycast hit.
Without it, a valid Parent Mesh3D is used. Other geometry still occludes the target.
positionSource remains the player/observer used for the radius check, with an
explicit world.interactionSource fallback. Distance is measured to the target's
world origin. There is no implicit camera position fallback.

ParticleEmitter3D.adornee selects spatial emission support within its own world:
Node3D, Mesh3D or Attachment3D. The emitter's position/rotation/scale are local to
that support. Without it, the nearest spatial parent is used. Removing an explicit
support stops births until cleared/reassigned. Existing world particles drain;
local particles retain the last support pose. Adornee never reparents the node.
