-- Lua body/shape representation shared by the two adapters. This module does
-- not create or step a simulation world. It keeps the historical raw/math API,
-- debug geometry and exact sensor narrow phase compatible with v101.
local Bodies = require('source.engine.physics.3d.backends.oimo.bodies')
local Colliders = require('source.engine.physics.3d.backends.oimo.colliders')
local Contacts = require('source.engine.physics.3d.backends.oimo.contacts')

local Compatibility = {}

function Compatibility:createBody(object, settings, scale)
    return Bodies.create(self.physics, object, settings, scale)
end

function Compatibility:createColliderCandidate()
    return Bodies.createColliderCandidate()
end

function Compatibility:addCollider(body, collider)
    return Colliders.add(body, collider)
end

function Compatibility:bindContact(body, shape)
    shape:setContactCallback(Contacts.create(body))
end

function Compatibility:refreshFilters(body)
    Colliders.refreshFilters(body)
end

return Compatibility
