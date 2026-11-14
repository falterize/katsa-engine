local Node = require('../../core.baseNode')
local Spatial = require('../../spatial.node2D')

local Body2D = Node.define('Body2D', 'Node2D')
Body2D.propertySchema = {
    bodyType = { options = { 'Static', 'Dynamic', 'Kinematic' } },
    mass = { min = 0.001 },
    density = { min = 0 },
    friction = { min = 0 },
    restitution = { min = 0 },
    gravityScale = {},
    linearDamping = { min = 0 },
    angularDamping = { min = 0 },
    autoSleep = {},
    bullet = {},
    fixedRotation = {},
    canCollide = {},
    canQuery = {},
    isTrigger = {},
    collisionGroup = {},
    enabled = {},
}

-- Live solver state, read and written through `node.physics` (docs/guides/physics/nodeAccess.md).
Body2D.computed = {
    velocity = {
        get = function(self)
            local body = rawget(self, 'physics')
            return body and body:getVelocity() or { 0, 0 }
        end,
        set = function(self, value)
            local body = rawget(self, 'physics')
            if body then
                body:setVelocity(value)
            end
        end,
    },
    angularVelocity = {
        get = function(self)
            local body = rawget(self, 'physics')
            return body and body:getAngularVelocity() or 0
        end,
        set = function(self, value)
            local body = rawget(self, 'physics')
            if body then
                body:setAngularVelocity(value)
            end
        end,
    },
    isSleeping = {
        get = function(self)
            local body = rawget(self, 'physics')
            return body ~= nil and body:isSleeping()
        end,
    },
}
Body2D.propertySchema.velocity = { readOnly = true, get = Body2D.computed.velocity.get }
Body2D.propertySchema.angularVelocity =
    { readOnly = true, get = Body2D.computed.angularVelocity.get }
Body2D.propertySchema.isSleeping = { readOnly = true, get = Body2D.computed.isSleeping.get }

function Body2D.initialize(self)
    self._independentBody = true
    self.bodyType = self.bodyType or 'Dynamic'
    self.density = self.density or 1
    self.friction = self.friction or 0.5
    self.restitution = self.restitution or 0
    self.gravityScale = self.gravityScale or 1
    self.linearDamping = self.linearDamping or 0.05
    self.angularDamping = self.angularDamping or 0.05
    self.autoSleep = self.autoSleep ~= false
    self.canQuery = self.canQuery ~= false
    self.canCollide = self.canCollide ~= false
    self.isTrigger = self.isTrigger == true
    self.collisionGroup = self.collisionGroup or 'Default'
end

function Body2D.mount(context, properties, parent)
    local node = Spatial.mount(context, properties, parent)
    assert(node._plane.physics2D, 'Call World2D:createPhysics before creating Body2D')
    node._plane.physics2D:addBody(node, { collider = properties.collider })
    return node
end

return Body2D
