# AnimationTree and retargeting

`AnimationTree` blends the clips of one `Animator` with a graph, the way Godot's AnimationTree
does. The tree only decides **weights and speeds**: every clip stays an `AnimationTrack`, so bone
masks, layers (`order`), markers and root motion keep working.

## Setup

```lua
local tree = world:create('AnimationTree', {
    definition = {
        type = 'StateMachine', start = 'Ground',
        states = {
            Ground = { type = 'Blend1D', param = 'speed', points = {
                { 0, 'Player_Idle' }, { 1, 'Player_Walk' }, { 2, 'Player_Run' } } },
            Air = { clip = 'Player_Fall' },
        },
        transitions = {
            { from = 'Ground', to = 'Air', when = function(p) return not p.grounded end, fade = 0.15 },
            { from = 'Air', to = 'Ground', when = 'grounded', fade = 0.1 },
        },
    },
}, modelRoot)                       -- or `animator = model.animator`
tree:set('speed', 1.4)
tree:set('grounded', true)
tree:trigger('jump')
tree:travel('Air')
tree:connect('StateChanged', function(machine, from, to) end)
```

Place the node under the model instance (or set `animator`); it connects as soon as the model
exists. Large graphs can live in a Lua file that returns the definition table: set
`definitionFile`. The inspector shows `active`, `animator`, `definitionFile` and the read-only
current `state`.

## Graph nodes

| Type | Does |
| --- | --- |
| `Animation` (`{ clip = 'Walk' }`, or just the clip name) | plays one clip; `loop`, `speed`, `order`, `mask` |
| `Blend` | mixes two inputs by `param` (0..1) |
| `Blend1D` | clips placed on one parameter axis (`points = { { value, clip } ... }`), neighbours are mixed |
| `Blend2D` | clips placed in a plane (`param`/`paramY`), weights by inverse distance |
| `TimeScale` | multiplies the speed of its input |
| `StateMachine` | states, transitions with `when` (parameter name, function or trigger), `fade`, `travel` |

`Blend1D` and `Blend2D` keep their clips in step (one shared phase, clip speeds scaled by length)
so a walk and a run do not drift apart. Pass `sync = false` to turn that off.

## Retargeting

An `Animator` used to refuse a clip from another skeleton. Now `animator:load(clip, { retarget = true })`
(the default for clips of a foreign model) converts the clip to the model's rest pose:

- bones match by name; case, punctuation and prefixes such as `mixamorig:` are ignored;
- `boneMap = { SourceBone = 'TargetBone' }` overrides pairs by hand;
- rotation = (targetRest · sourceRest⁻¹) · key, translation = targetRest + (key − sourceRest) · boneLengthRatio,
  scale = targetRest · key / sourceRest (cubic-spline tangents follow);
- a clip that keeps fewer than half of its channels is refused with the list of missing bones.

Both rigs must share bone orientation conventions (T-pose against A-pose is fine, a rig with
flipped bone axes is not). Not included: additive blending and IK-aware retargeting; use the
`InverseKinematics3D` node on top for foot placement.

Tests: `validation/tests/versions/v108_7/animationTree.lua`.
