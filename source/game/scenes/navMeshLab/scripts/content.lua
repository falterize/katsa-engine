local Mesh = require('source.engine.composition.mesh')
local Arena = require('./builders.arena')
local Yard = require('./builders.yard')
local JumpLinks = require('./behaviors.jumpLinks')
local Actions = require('./behaviors.actions')
local Patrol = require('./behaviors.patrol')

-- A walled arena with a jump yard and a baked NavMap3D. Eight NavAgent3D walkers chase a goal that
-- circles the arena; they route around the walls, jump the curbs when that is the shorter way and
-- avoid each other. A NavObstacle3D pillar slides through the middle. In the yard five patrolling
-- agents with different weights (areaCosts / actionCosts) show how one map serves agents that
-- choose differently: stairs and ramp, a jump down from the platform, a ladder, and a pond that
-- one walks around and another wades through.
local Lab = {}
Lab.__index = Lab

local AGENTS = 8

-- name, colour, areaCosts, actionCosts and the points of the patrol (see Yard.POINTS).
local PATROLLERS = {
    {
        name = 'Jumper',
        color = { 1, 0.55, 0.1, 1 },
        areas = 'water = 50',
        actions = 'jump = 0.3',
        route = { 'eastGround', 'platform' },
        start = { 38, 0, 22 },
    },
    {
        name = 'Hiker',
        color = { 0.9, 0.9, 0.3, 1 },
        areas = 'water = 50',
        actions = 'jump = off, climb = off',
        route = { 'ground', 'platform' },
        start = { 18, 0, 14 },
    },
    {
        name = 'Walker',
        color = { 0.2, 0.85, 0.35, 1 },
        areas = 'water = 50',
        actions = 'jump = off, climb = off',
        route = { 'pondWest', 'pondEast' },
        start = { 18, 0, 36 },
    },
    {
        name = 'Wader',
        color = { 0.3, 0.55, 1, 1 },
        areas = 'water = 1',
        actions = 'jump = off, climb = off',
        route = { 'pondWest', 'pondEast' },
        start = { 18, 0, 37 },
    },
    {
        name = 'Climber',
        color = { 0.85, 0.3, 0.9, 1 },
        areas = '',
        actions = 'jump = off, climb = 0.5',
        route = { 'ladderFoot', 'platform' },
        start = { 24, 0, 31 },
    },
}

function Lab.new(scene)
    local self = setmetatable({ scene = scene, time = 0 }, Lab)
    local world = scene.world
    world.environment.debug.gizmos.enabled = false
    world.environment.fog.enabled = false
    world.environment.ambient = { 150, 165, 185 }
    world.environment.shadows.enabled = true
    -- Baking samples the physics world, so the static arena needs a (gravity-free) solver.
    world:createPhysics({ backend = 'oimo', gravity = { 0, 0, 0 } })
    world:create('DirectionalLight3D', {
        name = 'Sun',
        rotation = { 55, 35, 0 },
        color = { 255, 238, 210 },
        brightness = 1,
    })
    Arena.build(world)
    Yard.build(world)

    world:updateNodes(1 / 60)
    self.map = world:create('NavMap3D', {
        name = 'ArenaNav',
        areaSize = { Arena.SIZE, Arena.SIZE },
        cellSize = 1,
        agentRadius = 1,
        castTop = 10,
        castBottom = -2,
    })
    self.map:bake()
    -- Where can an agent jump? That is this scene's rule (see behaviors/jumpLinks.lua).
    self.jumpLinks = JumpLinks.generate(self.map, { maxJump = 1.2, maxDrop = 4, distance = 6 })
    self.ladder = Yard.link(world, self.map)
    world.environment.debug.pathfinding.enabled = true
    world.environment.debug.pathfinding.drawDistance = 90

    self.goal = Mesh.create(world, {
        name = 'Goal',
        kind = 'sphere',
        size = { 1, 1, 1 },
        color = { 1, 0.85, 0.2, 1 },
        position = { 0, 0.5, 0 },
    })
    self.pillar = Mesh.create(world, {
        name = 'Pillar',
        size = { 3, 3, 3 },
        color = { 0.8, 0.25, 0.2, 1 },
        position = { 0, 1.5, -16 },
    })
    self.obstacle = world:create('NavObstacle3D', {
        name = 'PillarObstacle',
        shape = 'Circle',
        radius = 1.5,
    }, self.pillar)

    self.agents, self.patrols = {}, {}
    local function walker(name, options, color, size)
        -- The agent node itself moves with autoMove, so its visual is a child of it.
        options.name, options.navMap = name, self.map
        local agent = world:create('NavAgent3D', options)
        Mesh.create(world, {
            name = name .. 'Visual',
            kind = 'sphere',
            size = { size, size, size },
            color = color,
            position = { 0, size / 2, 0 },
        }, agent)
        self.agents[#self.agents + 1] = agent
        return agent
    end
    for i = 1, AGENTS do
        walker('Agent' .. i, {
            speed = 5 + (i % 3),
            radius = 0.7,
            targetNode = self.goal,
            position = { -20 + i * 4.5, 0, -22 },
        }, { 0.2 + 0.1 * i, 0.6, 1 - 0.1 * i, 1 }, 1.4)
    end
    self.crowdCount = AGENTS
    self.actions = Actions.new(self.agents)
    for _, agent in ipairs(self.agents) do
        self.actions:attach(agent)
    end
    for _, spec in ipairs(PATROLLERS) do
        local agent = walker(spec.name, {
            speed = 5,
            radius = 0.6,
            position = spec.start,
            areaCosts = spec.areas,
            actionCosts = spec.actions,
        }, spec.color, 1.2)
        self.actions:attach(agent)
        local points = {}
        for index, key in ipairs(spec.route) do
            points[index] = Yard.POINTS[key]
        end
        self.patrols[#self.patrols + 1] = Patrol.new(agent, points, 1.5)
    end
    scene.camera.position = { 14, 64, 0 }
    scene.camera.rotation = { -72, 0, 0 }
    return self
end

function Lab:setObstacleBlocking(enabled)
    self.obstacle.blocking = enabled
end

function Lab:update(dt)
    self.time = self.time + dt
    local t = self.time
    -- The goal patrols the open strip in front of the side walls; the pillar slides across the
    -- way the walkers take around the front wall.
    self.goal.position = { math.sin(t * 0.35) * 22, 0.5, -5 }
    self.pillar.position = { math.sin(t * 0.6) * 14, 1.5, -16 }
    for _, patrol in ipairs(self.patrols) do
        patrol:update(dt)
    end
    self.actions:update(dt)
    self.scene.world:updateNodes(dt)
end

return Lab
