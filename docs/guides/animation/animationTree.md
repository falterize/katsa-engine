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
| `Animation` (`{ clip = 'Walk' }`, or just the clip name) | plays one clip; `loop`, `speed`, `order`, `mask`, `playMode`, `loopMode`, `startTime`, `endTime`, `stretch` |
| `Blend` | mixes `a` and `b` by `amount` (0..1); with `filter`, only those bones mix |
| `Blend3` | `a`, `b`, `c` on `amount` from -1 to 1 |
| `Blend1D` | clips on one parameter axis (`points = { { value, clip } ... }`), neighbours are mixed |
| `Blend2D` | clips in a plane (`x`, `y`, `points = { { x, y, clip } ... }`), Delaunay triangulation |
| `Add2` | `base` plus the additive `add` clip scaled by `amount` (0..1) |
| `Add3` | `base` plus additive `plus` (amount > 0) or `minus` (amount < 0) |
| `Sub2` | `base` minus the difference of `sub` to its reference pose, scaled by `amount` |
| `OneShot` | plays `shot` once over `input` when `request` is triggered |
| `Transition` | one of several `inputs`, chosen by a parameter, with a crossfade |
| `TimeScale` | multiplies the speed of its input |
| `TimeSeek` | moves its child's clips to a time when `seek` is set |
| `StateMachine` | states, transitions (`when`, `onFinish`), `switch`, `advance`, `priority`, `travel`, `End` |

`Blend1D` and `Blend2D` keep their clips in step (one shared phase, clip speeds scaled by length)
so a walk and a run do not drift apart. Pass `sync = false` to turn that off.

### Animation node

`playMode = 'Backward'` plays from the end; `loopMode` is `'None'`, `'Linear'` or `'PingPong'`
(it replaces `loop`); `startTime` / `endTime` play only that part of the clip (seconds);
`stretch` multiplies the speed of the part. The same settings are properties of an
`AnimationTrack` (`startTime`, `endTime`, `loopMode`).

### Blend spaces

`Blend2D` triangulates its points; the three clips of the triangle around the sample share the
weight, outside the hull the nearest edge decides. Points on one line (or fewer than three) use
gradient-band weights instead. `mode` (also on `Blend1D`): `'Interpolated'` (default),
`'Discrete'` (the nearest clip only) or `'Carry'` (discrete, and the new clip starts at the old
one's phase).

### Additive clips and filters

Clips under `Add2`/`Add3` (and a `OneShot` with `mode = 'Add'`) are additive tracks: the Animator
adds their difference to a reference pose on top of the mixed pose (`reference = 'firstFrame'`,
the default, or `'rest'`). Rotations compose, translations and scales add. Any of these nodes,
and `Blend`, accept `filter` (bone names, or `{ Bone = weight }`) and `filterChildren = true`
(adds the descendants); the filter becomes the bone mask of the clips below.

```lua
{ type = 'Add2', amount = 'lean', base = locomotion, add = 'Lean_Right', filter = { 'Spine_001' } }
```

### OneShot

```lua
{ type = 'OneShot', input = locomotion, shot = 'Wave', request = 'wave', fadeIn = 0.1, fadeOut = 0.2,
  filter = { 'Upper_Arm_R' }, filterChildren = true, abort = 'stopWave', restart = false }
tree:trigger('wave')
```

The shot plays once as a layer above `input` (it keeps `input` running underneath), fades in and
out and ends with its longest clip. `restart = true` restarts it when requested again;
`abort` names a trigger that fades it out early.

### Transition

```lua
{ type = 'Transition', param = 'stance', fade = 0.25, curve = 'smooth',
  inputs = { { 'Stand', stand }, { 'Crouch', crouch } } }
tree:set('stance', 'Crouch')   -- an input name or its 1-based index
```

`curve`: `'linear'`, `'smooth'`, `'easeIn'`, `'easeOut'` or a function of 0..1. `reset = false`
keeps the chosen input where it was. A change during a fade continues from the reached weights.

### StateMachine

Transitions are tried by `priority` (lower first, then as listed). Conditions: `when` (a parameter or
trigger name, or a function), `expression` (text over the parameters, for example
`'speed > 0.5 and not grounded'`; `math` functions work) or `onFinish`. Per transition: `fade`,
`curve`, `switch` (`'Immediate'`, `'Sync'` carries the phase, `'AtEnd'` waits until the clip is about
to end), `advance` (`'Auto'`, or `'Disabled'` for use by `travel` only), `reset`. A state may be
another `StateMachine`; going to the state `'End'` finishes the machine, so a parent's `onFinish`
transition fires. `tree:travel('Target')` walks the shortest chain of transitions and honours each
`switch`; with no chain it jumps directly. `tree:state()` is the first state machine's state.

```lua
{ type = 'TimeSeek', seek = 'rewind', child = clip }
tree:set('rewind', 0)   -- seeks to second 0, then the parameter clears itself
```

### Graphs as nodes

The same graph can be nodes in the Workspace. Put `AnimationGraphNode` children under an
`AnimationTree` (the first is the root); the children of a graph node are its inputs, in order
(Blend: a, b; Add2: base, add; OneShot: input, shot ...). `type` picks the kind and the inspector
shows only that kind's properties (the clip property lists the clips of the model). Names matter
for Transition inputs and StateMachine states; `pointX`/`pointY` place an input in a blend space;
`AnimationTransition` children describe the transitions of a StateMachine node. Numbers that
a table graph would give as a parameter name are `param` (name) or `value` (fixed).

```lua
local tree = world:create('AnimationTree', {}, modelRoot)
local mix = world:create('AnimationGraphNode', { type = 'Blend1D', param = 'speed' }, tree)
world:create('AnimationGraphNode', { type = 'Animation', clip = 'Idle', pointX = 0 }, mix)
world:create('AnimationGraphNode', { type = 'Animation', clip = 'Walk', pointX = 1 }, mix)
```

With `liveEdit` (default) the tree notices edits of the nodes and rebuilds itself, keeping the
parameters; `tree:rebuild()` does it on demand. A `definition` or `definitionFile` wins over nodes.

Demo: the `animationTreeLab` scene builds its graph from nodes (`scripts/builders/graph.lua`): Transition
stance, Add2 squat, OneShot wave on the arms, an AtEnd landing.

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
