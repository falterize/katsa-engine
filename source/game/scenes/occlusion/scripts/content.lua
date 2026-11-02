local ipairs = require('source.engine.math.array').ipairs
local Mesh = require('source.engine.composition.mesh')

local Lab = {}
Lab.__index = Lab

function Lab.new(scene)
    local self = setmetatable({ scene = scene, moving = false, time = 0 }, Lab)
    local world, environment = scene.world, scene.world.environment
    scene.camera.position, scene.camera.rotation = { 0, 25, -90 }, { 0, 0, 0 }
    environment.debug.gizmos.enabled, environment.fog.enabled = false, false
    require('./lighting.directional').create(world).enabled, environment.shadows.enabled =
        true, true
    environment.render.occlusionCulling = true
    scene.showStats = true
    Mesh.create(world, {
        name = 'Floor',
        kind = 'plane',
        position = { 0, -8, 130 },
        size = { 500, 0, 500 },
        surfaceAppearance = { colorMap = 'dirt' },
    })
    for x = 1, 16 do
        for z = 1, 16 do
            Mesh.create(world, {
                name = 'HiddenCube' .. x .. '.' .. z,
                position = { (x - 8.5) * 12, 5, 40 + z * 12 },
                size = { 9, 22, 9 },
                surfaceAppearance = { colorMap = 'bricks' },
            })
        end
    end
    self.wall = Mesh.create(world, {
        name = 'OccluderWall',
        position = { 0, 28, 10 },
        size = { 240, 100, 6 },
        surfaceAppearance = { colorMap = 'stone', alphaMode = 'Opaque' },
    })
    local vertices = {}
    for x = 0, 15 do
        for y = 0, 3 do
            local x1, x2, y1, y2 = -160 + x * 20, -140 + x * 20, y * 12, (y + 1) * 12
            for _, point in ipairs({
                { x1, y1 },
                { x2, y1 },
                { x1, y2 },
                { x1, y2 },
                { x2, y1 },
                {
                    x2,
                    y2,
                },
            }) do
                vertices[#vertices + 1] = { point[1], point[2], 0, 0, 0, 0, 0, -1 }
            end
        end
    end
    local geometry = require('source.engine.graphics.geometry.primitives').mesh(vertices)
    scene.resources:own(geometry.mesh)
    self.partialPanel = Mesh.create(world, {
        name = 'PartialOcclusionPanel',
        geometry = geometry,
        position = { 0, 0, 80 },
        size = { 1, 1, 1 },
        visible = false,
        doubleSided = true,
        color = { 0.2, 0.8, 0.9, 1 },
        unlit = true,
    })
    return self
end

function Lab:update(dt)
    self.time = self.time + dt
    if self.moving then
        self.wall.position[1] = math.sin(self.time) * 200
    end
    self.scene.world:updateNodes(dt)
end

return Lab
