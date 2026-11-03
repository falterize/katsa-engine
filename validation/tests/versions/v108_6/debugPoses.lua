-- Collision wireframes use the interpolated pose that the visuals use, not the newer solver pose.
local Module = {}

function Module.run(self)
    local Physics = require('source.engine.physics')
    local World = require('source.engine.world.world')
    local O = require('source.engine.physics.3d.valueTypes')
    local resources = self.manager.resources:scope()
    local world = World.new(resources)
    world.physics = Physics.new({ backend = 'jolt' })
    world.physics:setInterpolation(true)
    local ball = world:create('Body3D', {
        name = 'Faller',
        position = { 0, 30, 0 },
        size = { 1, 1, 1 },
        collider = { shape = 'Sphere', radius = 0.5 },
    })
    for _ = 1, 10 do
        world:updateNodes(1 / 60)
        world.physics:update(1 / 60)
    end
    -- One and a half fixed steps leave the interpolation halfway between two solver poses.
    world.physics:update(1.5 / 60)
    local physics = world.physics
    local body = ball.body
    self:check(physics.interpolate, 'interpolation is on for this test')
    local draw = O.DebugDraw.new()
    draw.line, draw.triangle = function() end, function() end
    physics.world:setDebugDraw(draw)
    physics.world:debugDraw()
    local poses = physics:debugPoses()
    local entry
    for _, candidate in ipairs(poses or {}) do
        if candidate.raw == body.raw then
            entry = candidate
        end
    end
    self:check(entry ~= nil, 'a moving body provides a debug pose')
    local renderY = body:getRenderMatrix()[8]
    local solver = O.Vec3.new()
    body.raw:getPositionTo(solver)
    self:check(math.abs(entry.y * physics.units - renderY) < 1e-6, 'the debug pose is the render pose')
    self:check(solver.y < entry.y - 1e-4, 'the solver pose is ahead of the render pose while falling')

    physics.world:debugDraw(poses)
    local mirror = O.Vec3.new()
    body.raw._nativeOriginal.getPositionTo(body.raw, mirror)
    self:check(math.abs(mirror.y - entry.y) < 1e-6, 'the drawing mirror shows the render pose')
    physics.world:debugDraw()
    body.raw._nativeOriginal.getPositionTo(body.raw, mirror)
    self:check(math.abs(mirror.y - solver.y) < 1e-6, 'the mirror returns to the solver pose afterwards')
    world:release()
    resources:release()
end

return Module
