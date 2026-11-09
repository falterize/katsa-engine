local Mesh = require('source.engine.composition.mesh')
local Models = require('source.engine.import.models')

-- One AnimationTree on the shooter character. A StateMachine has three states: Ground (a
-- Blend1D of Player_Idle and Player_Walk driven by the `speed` parameter), Crouch and Air.
-- The buttons only set parameters; the graph decides weights, fades and transitions.
local Lab = {}
Lab.__index = Lab

local CHARACTER = 'source/game/scenes/stareShooter/assets/models/character.glb'

local function definition()
    return {
        type = 'StateMachine',
        start = 'Ground',
        states = {
            Ground = {
                type = 'Blend1D',
                param = 'speed',
                points = { { 0, 'Player_Idle' }, { 1, 'Player_Walk' } },
            },
            Crouch = { clip = 'Player_Crouch' },
            Air = { clip = 'Player_Jump', loop = false },
        },
        transitions = {
            { from = 'Ground', to = 'Crouch', when = 'crouching', fade = 0.2 },
            { from = 'Crouch', to = 'Ground', when = function(p) return not p.crouching end, fade = 0.2 },
            { from = 'Ground', to = 'Air', when = function(p) return not p.grounded end, fade = 0.1 },
            { from = 'Crouch', to = 'Air', when = function(p) return not p.grounded end, fade = 0.1 },
            { from = 'Air', to = 'Ground', when = 'grounded', fade = 0.15 },
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
    self.tree:set('crouching', false)
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
    self.tree:set('crouching', not self.tree:get('crouching'))
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
    return ('State: %s\nspeed %.2f  crouching %s  grounded %s'):format(
        tostring(tree.tree and tree.tree:state() or ''),
        tree:get('speed') or 0,
        tostring(tree:get('crouching')),
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
