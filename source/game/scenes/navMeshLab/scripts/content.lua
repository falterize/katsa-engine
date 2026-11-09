local Mesh = require('source.engine.composition.mesh')

-- A walled arena with a baked NavMap. Eight NavAgent3D walkers chase a goal that circles the
-- arena; they route around the walls and around each other. A NavObstacle3D pillar slides
-- through the middle: the agents re-route as the mesh changes under it.
local Lab = {}
Lab.__index = Lab

local AGENTS = 8
local WALLS = {
    { 0, -10, 24, 2 },
    { -14, 8, 2, 20 },
    { 14, 8, 2, 20 },
    { 0, 16, 14, 2 },
}

local function wall(world, index, x, z, width, depth)
    local position = { x, 1.5, z }
    local size = { width, 3, depth }
    local body = world:create('Body3D', {
        name = 'Wall' .. index,
        bodyType = 'Static',
        position = position,
        size = size,
    })
    Mesh.create(world, { name = 'WallVisual' .. index, size = size, color = { 0.55, 0.5, 0.45, 1 } }, body)
end

function Lab.new(scene)
    local self = setmetatable({ scene = scene, time = 0 }, Lab)
    local world = scene.world
    world.environment.debug.gizmos.enabled = false
    world.environment.fog.enabled = false
    world.environment.ambient = { 150, 165, 185 }
    world.environment.shadows.enabled = true
    -- Baking samples the physics world, so the static arena needs a (gravity-free) solver.
    world:createPhysics({ backend = 'oimo', gravity = { 0, 0, 0 } })
    local floor = world:create('Body3D', {
        name = 'Floor',
        bodyType = 'Static',
        position = { 0, -0.5, 0 },
        size = { 60, 1, 60 },
    })
    Mesh.create(world, {
        name = 'FloorVisual',
        size = { 60, 1, 60 },
        surfaceAppearance = { colorMap = 'stone' },
    }, floor)
    world:create('DirectionalLight3D', {
        name = 'Sun',
        rotation = { 55, 35, 0 },
        color = { 255, 238, 210 },
        brightness = 1,
    })
    for index, w in ipairs(WALLS) do
        wall(world, index, w[1], w[2], w[3], w[4])
    end

    world:updateNodes(1 / 60)
    self.map = world:create('NavMap', {
        name = 'ArenaNav',
        areaSize = { 60, 60 },
        cellSize = 1,
        agentRadius = 1,
        castTop = 10,
        castBottom = -2,
    })
    self.map:bake()
    world.environment.debug.pathfinding.enabled = true

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
        position = { 0, 1.5, 4 },
    })
    self.obstacle = world:create('NavObstacle3D', {
        name = 'PillarObstacle',
        shape = 'Circle',
        radius = 1.5,
    }, self.pillar)

    self.agents = {}
    for i = 1, AGENTS do
        local holder = world:create('Node3D', {
            name = 'Walker' .. i,
            position = { -20 + i * 4.5, 0, -22 },
        })
        Mesh.create(world, {
            name = 'WalkerVisual' .. i,
            kind = 'sphere',
            size = { 1.4, 1.4, 1.4 },
            color = { 0.2 + 0.1 * i, 0.6, 1 - 0.1 * i, 1 },
            position = { 0, 0.7, 0 },
        }, holder)
        self.agents[i] = world:create('NavAgent3D', {
            name = 'Agent' .. i,
            navMap = self.map,
            speed = 5 + (i % 3),
            radius = 0.7,
            targetNode = self.goal,
        }, holder)
    end
    scene.camera.position = { 0, 38, -34 }
    scene.camera.rotation = { -52, 0, 0 }
    return self
end

function Lab:setObstacleBlocking(enabled)
    self.obstacle.blocking = enabled
end

function Lab:update(dt)
    self.time = self.time + dt
    local t = self.time
    self.goal.position = { math.sin(t * 0.35) * 22, 0.5, math.cos(t * 0.35) * 6 + 4 }
    self.pillar.position = { math.sin(t * 0.6) * 8, 1.5, 4 }
    self.scene.world:updateNodes(dt)
end

return Lab
