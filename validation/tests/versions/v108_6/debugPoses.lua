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
    local body = ball.physics
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

    -- poseMode: Both draws the solver pass as well, tinted, so it makes about twice the lines.
    local camera = { project = function(_, p) return p[1] + 100, p[2] + 100 end }
    physics.debugEnabled = true
    physics:drawDebug(camera)
    local lines, tints = 0, {}
    local original = physics.debugDraw.line
    physics.debugDraw.line = function(draw, a, b, color)
        lines = lines + 1
        tints[#tints + 1] = physics.debugTint ~= nil
        return original(draw, a, b, color)
    end
    physics._debugSettings.poseMode = 'Render'
    physics:drawDebug(camera)
    local render = lines
    lines, tints = 0, {}
    physics._debugSettings.poseMode = 'Both'
    physics:drawDebug(camera)
    local tinted = 0
    for _, flag in ipairs(tints) do
        tinted = tinted + (flag and 1 or 0)
    end
    self:check(render > 0 and lines == render * 2 and tinted == render, 'Both draws the solver shapes tinted over the render shapes')
    self:check(physics.debugTint == nil, 'the tint does not leak into later draws')
    world:release()
    resources:release()
end

return Module
