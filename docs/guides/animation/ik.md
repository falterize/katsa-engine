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

## The `InverseKinematics3D` node

Every solver is also available as one node, so rigs can be set up in the inspector without code.

### Setting one up

1. The scene loads the plugin: `plugins = { 'ik' }` in its `settings.lua`.
2. The model is instantiated (`Models.instantiate`) and has an `Animator` (every animated glTF does).
3. Create the node **anywhere under the model's root node**. It walks up its parents to the first
   one that carries the model and registers with that model's Animator. Created before the model
   exists? It keeps looking every frame until it finds it.
4. Pick `type`, then the bones (dropdowns list the model's bones) and the target.

```lua
local ik = world:create('InverseKinematics3D', {
    type = 'TwoBone',
    rootBone = 'mixamorig:RightArm', tipBone = 'mixamorig:RightHand',   -- mid bone = the tip's parent
    target = ball, pole = elbowHint,
}, botRoot)
```

In the Workspace: select the model's root node, add `InverseKinematics3D`, choose the bones in the
dropdowns and drag a `Node3D` onto `target` (and `pole`). Turn on `debug` to see the chain.

### Types

| `type` | Use | Settings shown |
| --- | --- | --- |
| `TwoBone` | arms, legs | rootBone, midBone, tipBone, target, pole, softness |
| `CCD` | chains with limits | rootBone, tipBone, target, iterations, tolerance, maxStep, jointLimit |
| `FABRIK` | long chains | rootBone, tipBone, target, pole, iterations, tolerance |
| `Jacobian` | smooth long chains (tentacles, cranes) | rootBone, tipBone, target, iterations, tolerance, maxStep, jointLimit, damping |
| `Spline` | tails, spines, ropes | rootBone, tipBone, splineOffset; the curve goes through the node's `Node3D` children |
| `LookAt` | heads, eyes, turrets | rootBone, tipBone, target, forward, maxAngle, smoothing |
| `FK` | pose by angles, no target | rootBone, tipBone, rotation, falloff, fkMode |

Always shown: `type`, `influence`, `priority`, `debug`. Fields that do not apply to the chosen type
are hidden. The `ikLab` scene shows both hands following a moving ball with bent elbows and a solver
switch.

### Property reference

| Property | Default | Types | Meaning |
| --- | --- | --- | --- |
| `type` | `TwoBone` | all | the solver (table above) |
| `influence` | 1 | all | 0..1 blend between the animated pose (0) and the solved pose (1) |
| `priority` | 0 | all | order among the modifiers of one model; lower runs first and later ones see its result |
| `debug` | false | all | draw the chain, the target and the pole over the 3D view |
| `enabled` | true | all | switch the node off without removing it |
| `tipBone` | | all | **required**: last bone of the chain (hand, foot, head, end effector) |
| `rootBone` | | all | first bone of the chain. Empty: TwoBone uses the tip's grandparent, other types a chain of just the tip |
| `midBone` | | TwoBone | elbow or knee. Empty: the tip's parent |
| `target` | none | TwoBone, CCD, FABRIK, Jacobian, LookAt | `Node3D` the tip reaches for or looks at; without it the solve is skipped |
| `pole` | none | TwoBone, FABRIK | `Node3D` the elbow or knee bends toward; without it the animated bend direction is kept |
| `softness` | 0 | TwoBone | model units over which the limb eases into full extension (avoids snapping straight) |
| `iterations` | 10 | CCD, FABRIK, Jacobian | solver passes per pose evaluation (1..64) |
| `tolerance` | 0.001 | CCD, FABRIK, Jacobian | stop when the tip is this close to the target (model units) |
| `maxStep` | 20 | CCD, Jacobian | largest rotation of one joint per iteration in degrees (0 = unlimited for CCD) |
| `jointLimit` | 0 | CCD, Jacobian | how far a joint may leave the animated pose in degrees (0 = unlimited) |
| `damping` | 0.2 | Jacobian | damping relative to the chain length; higher is steadier but slower to reach |
| `splineOffset` | 0 | Spline | slides the chain along the curve (model units) |
| `forward` | `{0, 0, 1}` | LookAt | bone-local axis that should face the target |
| `maxAngle` | 0 | LookAt | largest turn away from the animated facing in degrees (0 = unlimited) |
| `smoothing` | 0 | LookAt | follow speed in 1/second (0 turns instantly) |
| `rotation` | `{0, 0, 0}` | FK | euler degrees, applied Z·Y·X in each bone's local space |
| `falloff` | 1 | FK | multiplies the rotation per joint along the chain (0.8 curls a finger) |
| `fkMode` | `Additive` | FK | `Additive` turns the animated pose; `FromRest` ignores the animation |

### Changing settings at runtime

Every property can be changed at any time, from code or the inspector; the next pose evaluation uses
the new values. Switching `type` keeps the previous solver's state, so switching back is instant. To
move the target, move the target node; to fade IK in or out, animate `influence`.

### When nothing happens

| Symptom | Check |
| --- | --- |
| The bones do not move | the node is under the model's root node; the model has an Animator (an animated glTF); `tipBone` is set; `target` is set (not for Spline and FK); `influence` > 0 |
| Error `Bone X is not an ancestor of Y` | `rootBone` must be above `tipBone` in the same branch of the skeleton |
| Error `InverseKinematics3D needs tipBone` | choose `tipBone` in the dropdown |
| The elbow bends the wrong way | add a `pole` node in front of (or behind) the elbow |
| The limb snaps straight at full reach | raise `softness` |
| The head turns too far | set `maxAngle`; add `smoothing` for a slower follow |
| A chain jitters | lower `maxStep`, raise `damping` (Jacobian) or `iterations` |
| The dropdowns are empty | the node is not under a model yet; place it under the model's root node |

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

- **`IK.Jacobian`** (`bones`, `iterations`, `tolerance`, `damping`, `maxStep`, `limit`): damped
  least squares over three rotation axes per joint. All joints move together, which looks smooth on
  long chains and copes with targets near straight poses.
- **`IK.Spline`** (`bones`, `points`, `offset`): the chain follows a Catmull-Rom curve through
  `points` (nodes, `{x, y, z}` or a function returning the list). The first bone stays; bones keep
  their lengths; `offset` slides the chain along the curve.
- **`IK.FK`** (`bones`, `rotation`, `falloff`, `mode`, or `pose = { Bone = {x, y, z} }`): poses
  bones by euler angles (degrees, Z·Y·X) instead of reaching for a target.

Use TwoBone for limbs, LookAt for heads and turrets, FABRIK or Jacobian for long chains, CCD when
joints need limits, Spline for tails and ropes and FK for procedural poses.

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

`bones()` lets the base class blend by `influence` and draw the debug overlay. To offer the new
solver as a node type too, add it to `TYPES` and `SOLVERS` in `nodes/inverseKinematics3D.lua`, show
its settings with `visibleWhen = only('MyType')`, and add a test next to `v108_5/ikNode.lua`. The
scene `ikLab` shows the solvers on the XBot with an influence and debug toggle.
