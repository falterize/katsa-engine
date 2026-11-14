-- node.physics / .space / .raw / .node access for 3D and 2D bodies, raycast hits and world:raycast.
local World = require('source.engine.world.world')

local Module = {}

local function near(a, b, tolerance)
    return math.abs(a - b) <= (tolerance or 0.01)
end

function Module.run(self)
    local resources = self.manager.resources:scope()
    local world = World.new(resources)
    world:createPhysics({ backend = 'oimo', gravity = { 0, 0, 0 } })
    local box = world:create('Body3D', { position = { 0, 10, 0 }, size = { 2, 2, 2 } })
    local body = box.physics
    self:check(
        body and body.node == box and body.space == world.physics and body.raw ~= nil,
        'Body3D node.physics links back to .node, .space and .raw'
    )
    self:check(
        world.physics:physicsOf(body.raw) == body and world.physics:nodeOf(body.raw) == box,
        'The physics space maps a backend body back to its physics object and node'
    )
    box.velocity = { 3, 0, 0 }
    local v = box.velocity
    self:check(
        near(v[1], 3) and near(box.physics:getVelocity()[1], 3),
        'Body3D velocity reads and writes the solver'
    )
    box.angularVelocity = { 0, 2, 0 }
    self:check(
        near(box.angularVelocity[2], 2),
        'Body3D angularVelocity reads and writes the solver'
    )
    self:check(box.isSleeping == false, 'Body3D isSleeping reflects the solver')
    self:check(not pcall(function()
        box.isSleeping = true
    end), 'Body3D isSleeping is read only')
    local reused = {}
    self:check(body:getVelocity(reused) == reused, 'getVelocity(out) fills the provided table')
    local floor = world:create('Body3D', {
        position = { 20, 10, 0 },
        size = { 2, 2, 2 },
        bodyType = 'Static',
    })
    local hit = world:raycast({ 10, 10, 0 }, { 30, 10, 0 })
    self:check(
        hit and hit.physics == floor.physics and hit.node == floor,
        'world:raycast returns hit.physics and hit.node'
    )
    self:check(world.root.physics == nil, 'Nodes without a body have no physics object')
    world:release()
    resources:release()

    local world2, ui, physics, make, release = self:environment({ gravity = { 0, 0 } })
    local ball = make(100, 100, 'Dynamic', { shape = 'Circle', radius = 10 })
    local wall = make(200, 100, 'Static', { shape = 'Box', size = { 20, 200 } })
    self:check(
        ball.physics.node == ball and ball.physics.space == physics and ball.physics.raw ~= nil,
        'Body2D node.physics links back to .node, .space and .raw'
    )
    self:check(
        physics:nodeOf(ball.physics.raw) == ball,
        'The 2D physics space maps a backend body back to its node'
    )
    ball.velocity = { 30, 0 }
    self:check(near(ball.velocity[1], 30), 'Body2D velocity reads and writes the solver')
    local hit2 = ui:raycast({ 100, 100 }, { 300, 100 })
    self:check(
        hit2 and hit2.physics == wall.physics and hit2.node == wall,
        'World2D raycast returns hit.physics and hit.node'
    )
    release()
end

return Module
