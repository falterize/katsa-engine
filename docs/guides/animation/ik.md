# Inverse kinematics (`ik` plugin)

The `ik` plugin adds skeleton modifiers for 3D rigs. A modifier runs once per pose evaluation,
after animation sampling and before the pose matrices are rebuilt, so it edits the freshly
animated pose and never accumulates between frames. Animation stays in charge of everything the
modifier does not touch; `influence` blends the two.

```lua
local IK = require('source.engine.plugins').require('ik')   -- scene settings: plugins = { 'ik' }

local arm = IK.TwoBone.new({
    root = 'mixamorig:RightArm', mid = 'mixamorig:RightForeArm', tip = 'mixamorig:RightHand',
    target = crate,             -- a node, an {x, y, z} world point, or a function returning one
    pole = elbowHint,           -- optional: the bend points toward it
    softness = 2,
})
arm:attach(model.animator)      -- Animator:addModifier; arm:detach() removes it
arm.influence = 0.75            -- 0 = pure animation, 1 = full solve
arm.debug = true                -- draws the chain, target and pole with the bone debug overlay
```

Targets and poles are **world** positions. The plugin converts them into model space
(`model.root` transform, including scale) so rigs can be moved, rotated and scaled freely.

## Common settings

| Field | Meaning |
| --- | --- |
| `target`, `pole` | Node, `{x, y, z}` or function; a missing target skips the solve |
| `influence` | 0..1 blend between the animated pose and the solved pose |
| `priority` | Order on one animator, lower first (later modifiers see earlier edits) |
| `enabled`, `debug` | Switch the modifier off / draw its overlay |

## Solvers

- **`IK.TwoBone`** (`root`, `mid`, `tip`, `softness`): analytic arm or leg. Bone lengths are
  preserved; unreachable targets straighten the limb toward the target; `softness` (model
  units) eases the last stretch so the joint does not snap straight. Without a pole the limb
  keeps the bend direction of the animation.
- **`IK.LookAt`** (`bone` or `bones`, `weights`, `forward`, `maxAngle`, `speed`): aims the
  bone-local `forward` axis at the target. A chain (spine, neck, head) shares the turn by
  `weights`; `maxAngle` limits the turn away from the animated facing (degrees); `speed`
  smooths target changes (1/second).
- **`IK.Fabrik`** (`bones`, `iterations`, `tolerance`, `pole`): any chain length, root pinned,
  last bone reaches for the target. `pole` twists the inner joints around the root-to-tip axis.
- **`IK.Ccd`** (`bones`, `iterations`, `tolerance`, `maxStep`, `limits`): cyclic coordinate
  descent. `maxStep` caps the rotation per joint per iteration and `limits` (degrees, by bone
  name) cap how far a joint's local rotation may leave the animated pose.

Use TwoBone for limbs, LookAt for heads and turrets, FABRIK for long chains and CCD when joints
need limits.

## Bone pose access

`IK.Skeleton.new(model)` wraps an instantiated model. Positions and rotations are in model
space; rotations are `{x, y, z, w}` quaternions (`IK.Quat` has the helpers).

```lua
local skeleton = IK.Skeleton.new(model)
local x, y, z = skeleton:getPosition('mixamorig:Head')   -- model space
local wx, wy, wz = skeleton:toWorld(x, y, z)
skeleton:getRotation(bone)                               -- global rotation (shared table)
skeleton:getLocalRotation(bone)                          -- copy of the local rotation
skeleton:setRotation(bone, q)                            -- global
skeleton:setLocalRotation(bone, q)
skeleton:rotate(bone, delta)                             -- apply a global delta rotation
skeleton:aim(bone, child, x, y, z)                       -- turn bone so `child` points at (x, y, z)
```

Global transforms are derived from the current local poses, so an edit is visible to the next
query immediately. Bones authored as matrices (not TRS) cannot be driven.

## Writing a solver

```lua
local Modifier = require('source.engine.plugins').require('ik').SkeletonModifier
local MyIK = Modifier.extend()
function MyIK.new(settings) local self = setmetatable({}, MyIK); self:configure(settings); return self end
function MyIK:bones() return { 'Bone1', 'Bone2' } end      -- every bone solve() may rotate
function MyIK:solve(skeleton, dt)
    local x, y, z = self:modelPoint(skeleton, self.target)   -- target in model space
    if x then skeleton:aim('Bone1', 'Bone2', x, y, z) end
end
```

`bones()` lets the base class blend by `influence` and draw the debug overlay. The scene
`ikLab` shows all four solvers on the XBot with an influence and debug toggle.
