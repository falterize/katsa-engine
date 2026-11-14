local Mesh = require('source.engine.composition.mesh')
local Models = require('source.engine.import.models')

-- One AnimationTree on the shooter character, built from the node types of the tree:
--   OneShot      `wave`: the jump clip plays once on the arms only (filter) over everything below
--   StateMachine Ground <-> Air (the landing waits for the end of the clip: switch = 'AtEnd')
--   Transition   `stance` crossfades between standing and the crouch clip (smooth curve)
--   Add2         `squat` adds the crouch pose on top of the walk, from nothing to fully
--   Blend1D      idle -> walk over `speed`
-- The buttons only set parameters; the graph decides weights, fades and transitions.
local Lab = {}
Lab.__index = Lab

local CHARACTER = 'assets/models/characters/player.glb'

local function definition()
    return {
        type = 'OneShot',
        request = 'wave',
        fadeIn = 0.15,
        fadeOut = 0.25,
        filter = { 'Upper_Arm_L', 'Upper_Arm_R' },
        filterChildren = true,
        shot = { clip = 'Player_Jump' },
        input = {
            type = 'StateMachine',
            start = 'Ground',
            states = {
                Ground = {
                    type = 'Transition',
                    param = 'stance',
                    fade = 0.25,
                    curve = 'smooth',
                    inputs = {
                        {
                            'Stand',
                            {
                                type = 'Add2',
                                amount = 'squat',
                                add = { clip = 'Player_Crouch' },
                                base = {
                                    type = 'Blend1D',
                                    param = 'speed',
                                    points = { { 0, 'Player_Idle' }, { 1, 'Player_Walk' } },
                                },
                            },
                        },
                        { 'Crouch', { clip = 'Player_Crouch' } },
                    },
                },
                Air = { clip = 'Player_Jump', loop = false },
            },
            transitions = {
                { from = 'Ground', to = 'Air', when = function(p) return not p.grounded end, fade = 0.1 },
                { from = 'Air', to = 'Ground', when = 'grounded', fade = 0.15, switch = 'AtEnd' },
            },
        },
    }
end

function Lab.new(scene)
    local self = setmetatable({ scene = scene, airTime = 0 }, Lab)
    local world = scene.world
    world.environment.debug.gizmos.enabled = false
    world.environment.fog.enabled = false
    world.environment.ambient = { 150, 165, 185 }
    world.environment.shadows.enabled = true
    Mesh.create(world, {
        name = 'Floor',
        position = { 0, -0.25, 0 },
        size = { 40, 0.5, 40 },
        surfaceAppearance = { colorMap = 'stone' },
    })
    world:create('DirectionalLight3D', {
        name = 'Sun',
        rotation = { 55, 35, 0 },
        color = { 255, 238, 210 },
        brightness = 1,
    })
    self.model = Models.load(CHARACTER, scene.resources)
    local _, root = Models.instantiate(world, self.model, { name = 'Hero', rotation = { 0, 0, 0 } })
    for _, clip in ipairs(self.model.animations) do
        if clip.name == 'Player_Jump' then
            self.jumpLength = clip.duration
        end
    end
    assert(self.jumpLength, 'Player_Jump is missing from the character')
    self.tree = world:create('AnimationTree', { name = 'HeroTree', definition = definition() }, root)
    self.tree:set('speed', 0)
    self.tree:set('stance', 'Stand')
    self.tree:set('squat', 0)
    self.tree:set('grounded', true)
    world.environment.sky.enabled = true
    scene.camera.position = { 0, 1.3, -4 }
    scene.camera.rotation = { -4, 0, 0 }
    return self
end

function Lab:setSpeed(value)
    self.tree:set('speed', math.max(0, math.min(1, value)))
end

function Lab:toggleCrouch()
    self.tree:set('stance', self.tree:get('stance') == 'Stand' and 'Crouch' or 'Stand')
end

-- Squat steps 0, 0.5, 1: the crouch pose added over the walk by the Add2 node.
function Lab:cycleSquat()
    local value = self.tree:get('squat') or 0
    value = value >= 1 and 0 or value + 0.5
    self.tree:set('squat', value)
    return value
end

function Lab:wave()
    self.tree:trigger('wave')
end

function Lab:jump()
    if self.tree:get('grounded') then
        self.tree:set('grounded', false)
        -- The jump clip plays once; the machine returns to Ground when it has finished.
        self.airTime = self.jumpLength
    end
end

-- Text for the HUD: the machine's current state and its parameters.
function Lab:describe()
    local tree = self.tree
    return ('State: %s  stance %s\nspeed %.2f  squat %.1f  grounded %s'):format(
        tostring(tree.tree and tree.tree:state() or ''),
        tostring(tree:get('stance')),
        tree:get('speed') or 0,
        tree:get('squat') or 0,
        tostring(tree:get('grounded'))
    )
end

function Lab:update(dt)
    if self.airTime > 0 then
        self.airTime = self.airTime - dt
        if self.airTime <= 0 then
            self.tree:set('grounded', true)
        end
    end
    self.scene.world:updateNodes(dt)
    if self.refreshStatus then
        self.refreshStatus()
    end
end

return Lab
