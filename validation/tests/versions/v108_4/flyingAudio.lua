-- The flying emitter's kinematic body must survive a near-zero first frame delta.
local Module = {}

local function finite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

function Module.run(self)
    local host = require('source.game.runtime.application').new(self.manager, 'flyingAudio')
    host:load()
    local flying = host.demo.flying
    local maxSpeed = 0
    for _, dt in ipairs({ 1e-9, 1e-7, 0, 1 / 240 }) do
        host:update(dt, dt)
    end
    for _ = 1, 600 do
        host:update(1 / 60, 1 / 60)
        local v = flying.physics:getVelocity()
        maxSpeed = math.max(maxSpeed, math.abs(v[1]), math.abs(v[2]), math.abs(v[3]))
    end
    local p = flying.position
    self:check(
        finite(p[1]) and finite(p[2]) and finite(p[3]),
        'flyingAudio: emitter position stays finite after tiny frame deltas'
    )
    self:check(
        math.abs(p[1]) < 200 and p[2] > -50 and p[2] < 200 and p[3] < 400,
        'flyingAudio: emitter stays on its orbit instead of flying away'
    )
    self:check(
        maxSpeed < 500,
        string.format('flyingAudio: emitter speed stays bounded (peak %.0f)', maxSpeed)
    )
    host:release()
end

return Module
