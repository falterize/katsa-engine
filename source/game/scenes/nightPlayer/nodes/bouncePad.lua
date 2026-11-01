local BouncePad = {
    base = 'Mesh3D',
    properties = {
        launchSpeed = { hint = 'Upward launch speed in world units per second.', min = 0 },
    },
}

function BouncePad.initialize(self)
    self.enabled = self.enabled ~= false
    self.launchSpeed = self.launchSpeed or 160
    self:onDestroy(function()
        self.pendingLaunch = nil
    end)
    self.color = self.color or { 0.2, 0.85, 0.4, 1 }
end

function BouncePad:bindPhysics(physics, player)
    self:connect('contactBegin', function(other)
        if self.enabled and other and other.object == player then
            self.pendingLaunch = other
        end
    end)
    physics:addBody(self, { type = 'Static', friction = 0.7, restitution = 0 })
end

function BouncePad:update(dt)
    local body = self.pendingLaunch
    if self.enabled == false then
        self.pendingLaunch = nil
        return
    end
    if not body then
        return
    end
    self.pendingLaunch = nil
    if body.destroyed then
        return
    end
    self._launchVelocity = self._launchVelocity or {}
    local velocity = body:getVelocity(self._launchVelocity)
    velocity[2] = self.launchSpeed
    body:setVelocity(velocity)
    self:emit('launched', body)
end

function BouncePad.register(world)
    return world:registerNodeType('BouncePad', BouncePad)
end

return BouncePad
