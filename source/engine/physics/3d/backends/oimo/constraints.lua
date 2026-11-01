local O = require('source.engine.physics.3d.backends.oimo.types')
local vec = require('source.engine.physics.3d.internal.bodyPolicy').vec
local pairs = require('source.engine.math.array').pairs

local Constraints = {}

function Constraints:createJoint(kind, a, b, settings)
    local configClass = assert(O[kind .. 'JointConfig'], 'Unknown joint: ' .. tostring(kind))
    local config = configClass.new()
    config.rigidBody1 = a.raw
    config.rigidBody2 = b.raw
    if settings.anchor1 then
        config.localAnchor1 = vec(settings.anchor1, (a.initialScale or 1) / self.physics.units)
    end
    if settings.anchor2 then
        config.localAnchor2 = vec(settings.anchor2, (b.initialScale or 1) / self.physics.units)
    end
    for key, value in pairs(settings) do
        if key ~= 'anchor1' and key ~= 'anchor2' then
            config[key] = value
        end
    end
    local joint = O[kind .. 'Joint'].new(config)
    self.world:addJoint(joint)
    return joint
end

return Constraints
