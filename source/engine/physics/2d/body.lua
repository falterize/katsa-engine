local Shapes = require('source.engine.physics.2d.shapes')

local Body = {}
Body.__index = Body
local properties = {
    'bodyType',
    'density',
    'mass',
    'friction',
    'restitution',
    'gravityScale',
    'linearDamping',
    'angularDamping',
    'autoSleep',
    'fixedRotation',
    'bullet',
    'canCollide',
    'canQuery',
    'isTrigger',
    'collisionGroup',
    'enabled',
}

local function pose(object)
    if object.getWorldPose then
        return object:getWorldPose()
    end
    return object.position[1], object.position[2], object.rotation or 0
end

function Body.new(physics, object, settings)
    local x, y, rotation = pose(object)
    for key, value in pairs(settings) do
        if key ~= 'collider' then
            object[key == 'type' and 'bodyType' or key] = value
        end
    end
    local self = setmetatable({
        physics = physics,
        object = object,
        fixtures = {},
        overlaps = {},
        triggerOverlaps = {},
        collisionOverlaps = {},
        _defaultCollider = not settings.collider and not object.collider,
        collider = settings.collider
            or object.collider
            or { shape = 'Box', size = object.size or { 32, 32 } },
        previousX = x,
        previousY = y,
        previousAngle = math.rad(rotation),
        currentX = x,
        currentY = y,
        currentAngle = math.rad(rotation),
        raw = katsa.physics.newBody(
            physics.world,
            x * physics.factor,
            y * physics.factor,
            (object.bodyType or 'Dynamic'):lower()
        ),
    }, Body)
    self.raw:setAngle(math.rad(rotation))
    self.raw:setUserData(self)
    object.body = self
    physics._creationOrder = (physics._creationOrder or 0) + 1
    self._creationOrder = physics._creationOrder
    physics.bodies[#physics.bodies + 1] = self
    physics._bodyEpoch = (physics._bodyEpoch or 0) + 1
    local ok, message = pcall(self.applyProperties, self, true)
    if not ok then
        self:destroy()
        error(message, 0)
    end
    if object.onDestroy then
        object:onDestroy(function()
            self:destroy()
        end)
    end
    return self
end

function Body:descriptors()
    local result = self._descriptors or {}
    self._descriptors = result
    local count, explicit = 0, false
    for _, node in ipairs(self.object.children or {}) do
        if node:isA('Collider2D') then
            explicit = true
            if node.enabled ~= false then
                count = count + 1
                result[count] = node:descriptor()
            end
        end
    end
    if not explicit then
        local collider = self.collider
        if collider.shape == 'Compound' then
            for _, descriptor in ipairs(collider.children or {}) do
                count = count + 1
                result[count] = descriptor
            end
        else
            count = 1
            result[1] = collider
        end
    end
    for i = #result, count + 1, -1 do
        result[i] = nil
    end
    return require('source.engine.physics.2d.geometry.transform').descriptors(self, result)
end

function Body:rebuildFixtures(descriptors)
    local candidates, p, object = {}, self.physics, self.object
    local ok, message = pcall(function()
        for _, descriptor in ipairs(descriptors) do
            local shapes = Shapes.createAll(descriptor, p.factor, p.resources)
            for _, shape in ipairs(shapes) do
                local fixture = katsa.physics.newFixture(
                    self.raw,
                    shape,
                    descriptor.density or object.density or 1
                )
                shape:release()
                fixture:setUserData({
                    body = self,
                    collider = descriptor._nodeOwner,
                    descriptor = descriptor,
                })
                candidates[#candidates + 1] = fixture
            end
        end
    end)
    if not ok then
        for _, fixture in ipairs(candidates) do
            fixture:destroy()
        end
        self._shapeInputs = nil
        error(message, 0)
    end
    for _, fixture in ipairs(self.fixtures) do
        fixture:destroy()
    end
    self.fixtures = candidates
end

function Body:applyProperties(force)
    if self.destroyed or self._pendingDestroy then
        return
    end
    local o, r = self.object, self.raw
    local values, changed = self._properties or {}, force == true
    local channelChanged = self._properties
        and (
            self._properties.isTrigger ~= o.isTrigger
            or self._properties.canCollide ~= o.canCollide
        )
    self._properties = values
    for _, key in ipairs(properties) do
        changed = values[key] ~= o[key] or changed
        values[key] = o[key]
    end
    if self._defaultCollider then
        self.collider.size = o.size
    end
    local descriptors = self:descriptors()
    if Shapes.changed(self, descriptors) or channelChanged then
        self:rebuildFixtures(descriptors)
        changed = true
    end
    if changed then
        self.physics.collisionGroups:add(o.collisionGroup or 'Default')
        self.type = o.bodyType or 'Dynamic'
        r:setType(self.type:lower())
        r:setGravityScale(o.gravityScale or 1)
        r:setLinearDamping(o.linearDamping or 0.05)
        r:setAngularDamping(o.angularDamping or 0.05)
        r:setSleepingAllowed(o.autoSleep ~= false)
        r:setFixedRotation(o.fixedRotation == true)
        r:setBullet(o.bullet == true)
        r:setActive(o.enabled ~= false)
        for _, fixture in ipairs(self.fixtures) do
            local d = fixture:getUserData().descriptor
            fixture:setDensity(d.density or o.density or 1)
            fixture:setFriction(d.friction or o.friction or 0.5)
            fixture:setRestitution(d.restitution or o.restitution or 0)
            fixture:setSensor(d.isTrigger == true or o.isTrigger == true or o.canCollide == false)
        end
        r:resetMassData()
        if o.mass and self.type == 'Dynamic' then
            r:setMass(o.mass)
        end
        self:refreshFilters()
    end
    local x, y, angle = pose(o)
    if force or x ~= self._authoredX or y ~= self._authoredY or angle ~= self._authoredAngle then
        self:teleport(x, y, angle)
    end
end

function Body:refreshFilters()
    for _, fixture in ipairs(self.fixtures) do
        fixture:setFilterData(fixture:getFilterData())
    end
end

function Body:set(settings)
    self.physics:defer(function()
        if self.destroyed then
            return
        end
        for key, value in pairs(settings) do
            self.object[key == 'type' and 'bodyType' or key] = value
        end
        self:applyProperties()
    end)
    return self
end

function Body:setCollider(descriptor)
    self.physics:defer(function()
        if self.destroyed then
            return
        end
        local previous, default = self.collider, self._defaultCollider
        self.collider = descriptor
        self._defaultCollider = false
        local ok, message = pcall(self.applyProperties, self)
        if not ok then
            self.collider, self._defaultCollider, self._shapeInputs = previous, default, nil
            error(message, 0)
        end
    end)
end

function Body:teleport(x, y, rotation)
    if type(x) ~= 'number' then
        x, y, rotation = x[1], x[2], y
    end
    self.physics:defer(function()
        if self.destroyed then
            return
        end
        local angle = rotation and math.rad(rotation) or self.raw:getAngle()
        self.raw:setPosition(x * self.physics.factor, y * self.physics.factor)
        self.raw:setAngle(angle)
        self.raw:setAwake(true)
        self.previousX, self.previousY, self.previousAngle = x, y, angle
        self.currentX, self.currentY, self.currentAngle = x, y, angle
        self:sync()
    end)
end

function Body:sync()
    local f, o = self.physics.factor, self.object
    local x, y = self.raw:getPosition()
    x, y = x / f, y / f
    local angle = math.deg(self.raw:getAngle())
    if o.setWorldPose then
        o:setWorldPose(x, y, angle)
    else
        o.position[1], o.position[2], o.rotation = x, y, angle
    end
    self._authoredX, self._authoredY, self._authoredAngle = pose(o)
end

function Body:getPosition()
    local x, y = self.raw:getPosition()
    return x / self.physics.factor, y / self.physics.factor
end

function Body:getLinearVelocity()
    local x, y = self.raw:getLinearVelocity()
    return x / self.physics.factor, y / self.physics.factor
end

function Body:setLinearVelocity(x, y)
    local f = self.physics.factor
    self.raw:setLinearVelocity(x * f, y * f)
    self.raw:setAwake(true)
end

function Body:getAngularVelocity()
    return math.deg(self.raw:getAngularVelocity())
end
function Body:setAngularVelocity(value)
    self.raw:setAngularVelocity(math.rad(value))
end
function Body:getMass()
    return self.raw:getMass()
end
function Body:isSleeping()
    return not self.raw:isAwake()
end
function Body:wake()
    self.raw:setAwake(true)
end
function Body:sleep()
    self.raw:setAwake(false)
end

function Body:applyForce(x, y, px, py)
    if type(x) ~= 'number' then
        x, y = x[1], x[2]
    end
    local f = self.physics.factor
    if px then
        self.raw:applyForce(x * f, y * f, px * f, py * f)
    else
        self.raw:applyForce(x * f, y * f)
    end
end

function Body:applyImpulse(x, y, px, py)
    if type(x) ~= 'number' then
        x, y = x[1], x[2]
    end
    local f = self.physics.factor
    if px then
        self.raw:applyLinearImpulse(x * f, y * f, px * f, py * f)
    else
        self.raw:applyLinearImpulse(x * f, y * f)
    end
end

function Body:applyTorque(value)
    self.raw:applyTorque(value * self.physics.factor ^ 2)
end
function Body:applyAngularImpulse(value)
    self.raw:applyAngularImpulse(value * self.physics.factor ^ 2)
end

function Body:destroy()
    if self.destroyed or self._pendingDestroy then
        return
    end
    self._pendingDestroy = true
    self.physics:defer(function()
        if self.destroyed then
            return
        end
        for _, constraint in ipairs(self.physics.constraints) do
            if constraint._body0 == self or constraint._body1 == self then
                constraint:releaseJoint()
            end
        end
        self.raw:destroy()
        self.destroyed = true
        if self.object.body == self then
            self.object.body = nil
        end
        for i, body in ipairs(self.physics.bodies) do
            if body == self then
                table.remove(self.physics.bodies, i)
                self.physics._bodyEpoch = (self.physics._bodyEpoch or 0) + 1
                break
            end
        end
        self.fixtures, self.overlaps = {}, {}
    end)
end

function Body:setVelocity(value)
    self:setLinearVelocity(value[1], value[2])
end

function Body:getVelocity(out)
    out = out or {}
    out[1], out[2] = self:getLinearVelocity()
    return out
end

function Body:applyForceAt(value, position)
    self:applyForce(value[1], value[2], position[1], position[2])
end

function Body:applyImpulseAt(value, position)
    self:applyImpulse(value[1], value[2], position[1], position[2])
end

function Body:setMass(value)
    return self:set({ mass = value })
end

function Body:getContacts()
    local result = {}
    for other in pairs(self.overlaps) do
        if not other.destroyed then
            result[#result + 1] = other
        end
    end
    return result
end

function Body:teleportLocal(position, rotation)
    self.object.position = position
    self.object.rotation = rotation or self.object.rotation
    self:teleport(self.object:getWorldPose())
end

return Body
