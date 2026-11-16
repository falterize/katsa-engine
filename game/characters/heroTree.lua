-- The animation graph of the hero as nodes: they show in the Workspace under `HeroTree`, and
-- editing a property there changes the live animation (the tree rebuilds itself).
--   OneShot Wave        `wave`: the jump clip plays once on the arms only (filter) over the rest
--   StateMachine        Ground <-> Air (the landing waits for the end of the clip: AtEnd)
--   Transition Ground   `stance` crossfades between Stand and Crouch (smooth curve)
--   Add2 Stand          `squat` adds the crouch pose on top of the walk, from nothing to fully
--   TimeScale Stride    `stride` speeds the walk cycle up with the movement (negative: backward)
--   TimeScale *Rate     `crouchRate` plays the crouch clips (0 on the spot, negative backward)
--   Blend1D Walk        idle -> walk over `speed`
local Graph = {}

-- The walk cycle's playback rate for a ground speed, matching the controller scene (stareShooter):
-- the clip plays 2.5x at walking pace and 3.5x at running pace; idle stays at 1x.
local WALK_SPEED, RUN_SPEED = 5, 8

-- Sets the playback parameters from the controller's `walkScale` (0 standing still, negative while
-- moving backward relative to the facing) and the ground speed.
function Graph.setRate(tree, walkScale, speed)
    local sign = walkScale < 0 and -1 or 1
    tree:set('stride', walkScale == 0 and 1 or sign * Graph.stride(speed))
    tree:set('crouchRate', walkScale)
end

-- The parameters of a character standing still on the ground.
function Graph.init(tree)
    tree:set('speed', 0)
    tree:set('stride', 1)
    tree:set('crouchRate', 0)
    tree:set('stance', 'Stand')
    tree:set('squat', 0)
    tree:set('grounded', true)
end

function Graph.stride(speed)
    if speed <= WALK_SPEED then
        return 1 + 1.5 * math.max(0, speed) / WALK_SPEED
    end
    return math.min(3.5, 2.5 + (speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED))
end

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
    node(world, wave, { name = 'WaveClip', type = 'Animation', clip = 'Player_Jump', speed = 2 })

    local ground =
        node(world, machine, { name = 'Ground', type = 'Transition', param = 'stance', fade = 0.25, curve = 'smooth' })
    node(world, machine, { name = 'Air', type = 'Animation', clip = 'Player_Jump', loopMode = 'None', speed = 2 })
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
    -- `crouchRate` is the crouch clip's playback rate: signed (negative while walking backward) and
    -- 0 on the spot, so a crouching character holds its pose when it stands still.
    local crouchRate = node(world, ground, { name = 'Crouch', type = 'TimeScale', param = 'crouchRate' })
    node(world, crouchRate, { name = 'CrouchClip', type = 'Animation', clip = 'Player_Crouch' })
    -- `stride` (1 at walking pace, more when running) speeds the walk cycle up with the movement.
    local stride = node(world, stand, { name = 'Stride', type = 'TimeScale', param = 'stride' })
    local walk = node(world, stride, { name = 'Walk', type = 'Blend1D', param = 'speed' })
    local squatRate = node(world, stand, { name = 'SquatRate', type = 'TimeScale', param = 'crouchRate' })
    node(world, squatRate, { name = 'Squat', type = 'Animation', clip = 'Player_Crouch' })
    node(world, walk, { name = 'Idle', type = 'Animation', clip = 'Player_Idle', pointX = 0 })
    node(world, walk, { name = 'Step', type = 'Animation', clip = 'Player_Walk', pointX = 1 })
    return wave
end

return Graph
