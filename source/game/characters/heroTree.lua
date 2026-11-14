-- The animation graph of the hero as nodes: they show in the Workspace under `HeroTree`, and
-- editing a property there changes the live animation (the tree rebuilds itself).
--   OneShot Wave        `wave`: the jump clip plays once on the arms only (filter) over the rest
--   StateMachine        Ground <-> Air (the landing waits for the end of the clip: AtEnd)
--   Transition Ground   `stance` crossfades between Stand and Crouch (smooth curve)
--   Add2 Stand          `squat` adds the crouch pose on top of the walk, from nothing to fully
--   Blend1D Walk        idle -> walk over `speed`
local Graph = {}

local function node(world, parent, properties)
    return world:create('AnimationGraphNode', properties, parent)
end

function Graph.build(world, tree)
    local wave = node(world, tree, {
        name = 'ArmsWave',
        type = 'OneShot',
        request = 'wave',
        fadeIn = 0.15,
        fadeOut = 0.25,
        filter = 'Upper_Arm_L, Upper_Arm_R',
        filterChildren = true,
    })
    local machine = node(world, wave, { name = 'Locomotion', type = 'StateMachine', startState = 'Ground' })
    node(world, wave, { name = 'WaveClip', type = 'Animation', clip = 'Player_Jump' })

    local ground =
        node(world, machine, { name = 'Ground', type = 'Transition', param = 'stance', fade = 0.25, curve = 'smooth' })
    node(world, machine, { name = 'Air', type = 'Animation', clip = 'Player_Jump', loopMode = 'None' })
    world:create('AnimationTransition', {
        name = 'Fall',
        from = 'Ground',
        to = 'Air',
        expression = 'not grounded',
        fade = 0.1,
    }, machine)
    world:create('AnimationTransition', {
        name = 'Land',
        from = 'Air',
        to = 'Ground',
        param = 'grounded',
        fade = 0.15,
        switch = 'AtEnd',
    }, machine)

    local stand = node(world, ground, { name = 'Stand', type = 'Add2', param = 'squat' })
    node(world, ground, { name = 'Crouch', type = 'Animation', clip = 'Player_Crouch' })
    local walk = node(world, stand, { name = 'Walk', type = 'Blend1D', param = 'speed' })
    node(world, stand, { name = 'Squat', type = 'Animation', clip = 'Player_Crouch' })
    node(world, walk, { name = 'Idle', type = 'Animation', clip = 'Player_Idle', pointX = 0 })
    node(world, walk, { name = 'Step', type = 'Animation', clip = 'Player_Walk', pointX = 1 })
    return wave
end

return Graph
