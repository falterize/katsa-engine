-- Oimo solver adapter. The compatibility helpers are reused by Jolt; this
-- world is only constructed when Oimo itself is selected for simulation.
local O = require('source.engine.physics.3d.backends.oimo.types')
local Extensions = require('source.engine.core.extensions')
local Bodies = require('source.engine.physics.3d.backends.oimo.bodies')
local vec = require('source.engine.physics.3d.internal.bodyPolicy').vec
local Compatibility = require('source.engine.physics.3d.backends.oimo.compatibility')

local Adapter = setmetatable({}, { __index = Compatibility })
Adapter.__index = Adapter

function Adapter.new(physics, settings)
    return setmetatable({
        physics = physics,
        world = O.World.new(2, vec(physics.gravity, 1 / physics.units)),
    }, Adapter)
end

function Adapter:pointInverseMass(body, x, y, z)
    return Bodies.pointInverseMass(body, x, y, z)
end

-- Oimo shapes/settings are already committed by the common body API. Unlike
-- a native adapter, it needs no second representation to prepare or update.
function Adapter:wrapBody(body) end

function Adapter:prepareCollider(candidate) end

function Adapter:rebuild(body, candidate) end

function Adapter:applySettings(body, values) end

function Adapter:release() end

Extensions.apply(Adapter, require('source.engine.physics.3d.backends.oimo.constraints'))
return Adapter
