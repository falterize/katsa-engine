local Mesh = require('source.engine.composition.mesh')
local Arena = require('./builders.arena')
local Yard = require('./builders.yard')
local JumpLinks = require('./behaviors.jumpLinks')
local Walker = require('./behaviors.physicalWalker')
local Patrol = require('./behaviors.patrol')

-- A walled arena with a jump yard and a baked NavMap3D. Eight NavAgent3D walkers chase a goal that
-- tours the whole location; they route around the walls, jump the curbs when that is the shorter way and
-- avoid each other. A NavObstacle3D pillar slides through the middle. In the yard five patrolling
-- agents with different weights (areaCosts / actionCosts) show how one map serves agents that
-- choose differently: stairs and ramp, a jump down from the platform, a ladder, and a pond that
-- one walks around and another wades through.
local Lab = {}
Lab.__index = Lab

local AGENTS = 8

-- The goal tours the whole location (corners of its loop, x and z): through the pillar's lane,
-- over the curbs, round the walled block and across the yard.
local TOUR = {
    { -8, -20 }, { 8, -14 }, { 24, -20 }, { 30, -6 }, { 22, 16 },
    { -5, 26 }, { -24, 22 }, { -28, -4 }, { -18, -24 },
}
local GOAL_SPEED = 4.5

-- name, colour, areaCosts, actionCosts and the points of the patrol (see Yard.POINTS).
local PATROLLERS = {
    {
        name = 'Jumper',
        color = { 1, 0.55, 0.1, 1 },
        areas = 'water = 50',
        actions = 'jump = 0.3, climb = off',
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

local tourLength = 0
for i, a in ipairs(TOUR) do
    local b = TOUR[i % #TOUR + 1]
    tourLength = tourLength + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
end

-- Point at `distance` along the closed TOUR loop.
local function tourPoint(distance)
    distance = distance % tourLength
    for i, a in ipairs(TOUR) do
        local b = TOUR[i % #TOUR + 1]
        local length = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
        if distance <= length then
            local f = distance / length
            return a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
        end
        distance = distance - length
    end
    return TOUR[1][1], TOUR[1][2]
end

function Lab.new(scene)
    local self = setmetatable({ scene = scene, time = 0 }, Lab)
    local world = scene.world
    world.environment.debug.gizmos.enabled = false
    world.environment.fog.enabled = false
    world.environment.ambient = { 150, 165, 185 }
    world.environment.shadows.enabled = true
    -- Baking samples the physics world; the walkers are dynamic bodies with real gravity.
    scene:createPhysics({ gravity = { 0, -24.5, 0 }, unitsPerMeter = 1 })
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
        cellSize = 0.5,
        agentHeight = 1.8, -- the capsules' height
        agentRadius = 0.5, -- one cell of margin around walls and drops for the physical capsules
        castTop = 10,
        castBottom = -2,
        maxStep = 0.3, -- what a physical capsule climbs: stair steps (0.2) yes, curbs (0.9) no
    })
    self.map:bake()
    -- Where can an agent jump? That is this scene's rule (see behaviors/jumpLinks.lua).
    self.jumpLinks = JumpLinks.generate(self.map, { maxJump = 1.2, maxDrop = 4, distance = 5, spacing = 2 })
    self.ladder = Yard.link(world, self.map)
    world.environment.debug.pathfinding.enabled = true
    world.environment.debug.pathfinding.drawDistance = 90

    self.goal = Mesh.create(world, {
        name = 'Goal',
        kind = 'sphere',
        size = { 1, 1, 1 },
        color = { 1, 0.85, 0.2, 1 },
        position = { TOUR[1][1], 0.5, TOUR[1][2] },
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

    self.agents, self.walkers, self.patrols = {}, {}, {}
    local function walker(name, options, color)
        options.name, options.navMap, options.color = name, self.map, color
        local made = Walker.new(world, options, self.walkers)
        self.walkers[#self.walkers + 1] = made
        self.agents[#self.agents + 1] = made.agent
        return made
    end
    for i = 1, AGENTS do
        walker('Agent' .. i, {
            speed = 5 + (i % 3),
            radius = 0.6,
            targetNode = self.goal,
            actionCosts = 'jump = 0.6', -- cheap enough to hop a curb instead of walking round it
            position = { -20 + i * 4.5, 0, -22 },
        }, { 0.2 + 0.1 * i, 0.6, 1 - 0.1 * i, 1 })
    end
    self.crowdCount = AGENTS
    for _, spec in ipairs(PATROLLERS) do
        local made = walker(spec.name, {
            speed = 5,
            radius = 0.6,
            position = spec.start,
            areaCosts = spec.areas,
            actionCosts = spec.actions,
        }, spec.color)
        local points = {}
        for index, key in ipairs(spec.route) do
            points[index] = Yard.POINTS[key]
        end
        self.patrols[#self.patrols + 1] = Patrol.new(made.agent, points, 1.5)
    end
    -- One physics hook steers every walker before each fixed step.
    world.physics.beforeStep = function()
        for _, made in ipairs(self.walkers) do
            made:step()
        end
    end
    scene.camera.position = { 14, 64, 0 }
    scene.camera.rotation = { -72, 0, 0 }
    return self
end

function Lab:setObstacleBlocking(enabled)
    self.obstacle.blocking = enabled
    -- Solid red while it blocks the NavMesh, a faint green ghost while agents may walk through it.
    self.pillar.color = enabled and { 0.8, 0.25, 0.2, 1 } or { 0.3, 0.9, 0.4, 0.35 }
end

function Lab:update(dt)
    self.time = self.time + dt
    local t = self.time
    -- The goal travels the TOUR loop at a steady pace; the pillar slides across the lane the
    -- walkers take past the front wall (the tour crosses it).
    local x, z = tourPoint(t * GOAL_SPEED)
    self.goal.position = { x, 0.5, z }
    self.pillar.position = { math.sin(t * 0.6) * 14, 1.5, -16 }
    for _, patrol in ipairs(self.patrols) do
        patrol:update(dt)
    end
    self.scene.physics:update(dt)
    self.scene.world:updateNodes(dt)
end

return Lab
