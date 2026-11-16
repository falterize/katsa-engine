# Ragdoll

The `ragdoll` plugin turns a skinned humanoid model into physical bodies. Enable it in the
scene settings (`plugins = { 'ragdoll' }`) and add a `Ragdoll3D` node under the model root:

```lua
local ragdoll = world:create('Ragdoll3D', {
    name = 'PlayerRagdoll',
    source = playerBody, -- optional Body3D whose velocity the ragdoll inherits
}, model.root)
ragdoll.active = true
ragdoll:update()
```

While `active` is on, the node builds one capsule `Body3D` per segment (hips, chest, head, upper
arm, forearm, thigh, shin on both sides) joined by `RagdollConstraint3D`, and an Animator
modifier writes the bodies' poses back to the bones. Switching it off removes the bodies and the
animation takes over again. Bones are found by name (`Hips`, `Spine`, `UpperArm.L`, ...); a model
without a recognised skeleton reports the reason in the read-only `status` property.

| Property | Meaning |
| --- | --- |
| `active` | builds / removes the physical rig |
| `source` | `Body3D` that supplies the initial velocity |
| `density`, `friction`, `damping` | body material |
| `thickness` | capsule radius relative to the segment length |
| `jointLimit` | maximum joint swing, degrees |
| `priority` | modifier order among other Animator modifiers |

`ragdoll:getBody('Hips')` returns the `Body3D` of a segment (nil while off). The stareShooter
scene shows it: press R or the Ragdoll button; the walking capsule is paused and follows the
pelvis, and switching back stands the character up above where it lay.
