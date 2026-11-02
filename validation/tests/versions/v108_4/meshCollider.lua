-- Static triangle-mesh colliders: a ball dropped on a sloped mesh stops on the surface.
local Module = {}

function Module.run(self)
    local Physics = require('source.engine.physics')
    local World = require('source.engine.world.world')
    local resources = self.manager.resources:scope()
    local world = World.new(resources)
    world.physics = Physics.new({ backend = 'jolt' })
    -- A plane rising 1 unit per 4 along +x, 40 x 40.
    local vertices = {
        { -20, -5, -20 },
        { 20, 5, -20 },
        { 20, 5, 20 },
        { -20, -5, 20 },
    }
    world:create('Body3D', {
        name = 'Terrain',
        bodyType = 'Static',
        position = { 0, 0, 0 },
        size = { 1, 1, 1 },
        collider = { shape = 'Mesh', vertices = vertices, indices = { 1, 3, 2, 1, 4, 3 } },
    })
    local ball = world:create('Body3D', {
        name = 'Ball',
        position = { 0, 12, 0 },
        size = { 1, 1, 1 },
        collider = { shape = 'Sphere', radius = 0.5 },
    })
    for _ = 1, 240 do
        world:updateNodes(1 / 60)
        world.physics:update(1 / 60)
    end
    local y = ball.position[2]
    -- The surface under x = ball.x is 0.25 * x; the ball rests about its radius above it.
    local surface = 0.25 * ball.position[1]
    self:check(y > surface and y < surface + 2, string.format('ball rests on the mesh (y %.2f vs surface %.2f)', y, surface))
    world:release()
    resources:release()
end

return Module
