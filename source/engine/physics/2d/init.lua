local Body = require('./body')
local Contacts = require('./contacts')
local Simulation = require('./simulation')
local Queries = require('./queries')
local Drawing = require('./drawing')

local Physics2D = {}
Physics2D.__index = Physics2D

function Physics2D.new(options)
    options = options or {}
    local units = options.unitsPerMeter or options.units or 64
    assert(type(units) == 'number' and units > 0 and units < math.huge, 'Invalid 2D units')
    local gravity = require('source.engine.world.gravity').options(options, 2, { 0, -9.81 * units })
    -- Do not change katsa.physics.setMeter: that global also affects other worlds.
    local factor = katsa.physics.getMeter() / units
    local self = setmetatable({
        backendName = 'Box2D',
        units = units,
        factor = factor,
        gravity = gravity,
        fixedDelta = options.fixedDelta or 1 / 60,
        maxSteps = options.maxSteps or 8,
        velocityIterations = options.velocityIterations or 8,
        positionIterations = options.positionIterations or 3,
        interpolate = options.interpolate ~= false,
        accumulator = 0,
        interpolationAlpha = 0,
        paused = false,
        bodies = {},
        constraints = {},
        events = {},
        commands = {},
        debug = options.debugSettings
            or require('source.engine.physics.2d.debugSettings').create(options.debug),
        stats = { steps = 0, droppedTime = 0, updateMilliseconds = 0, solverMilliseconds = 0 },
        world = katsa.physics.newWorld(gravity[1] * factor, gravity[2] * factor, true),
    }, Physics2D)
    assert(self.fixedDelta > 0 and self.fixedDelta < math.huge, 'Invalid 2D fixedDelta')
    assert(self.maxSteps >= 1 and self.maxSteps % 1 == 0, 'Invalid 2D maxSteps')
    self.collisionGroups = require('source.engine.core.groups').new(function(registry)
        for _, body in ipairs(self.bodies) do
            if registry.renamed and body.object.collisionGroup == registry.renamed[1] then
                body.object.collisionGroup = registry.renamed[2]
            end
            if not registry.bits[body.object.collisionGroup or 'Default'] then
                body.object.collisionGroup = 'Default'
            end
            body:refreshFilters()
        end
    end)
    Contacts.install(self)
    return self
end

function Physics2D:addBody(object, settings)
    assert(
        not self.released and not self.world:isLocked(),
        'Cannot add a body during a solver callback'
    )
    return Body.new(self, object, settings or {})
end

function Physics2D:defer(callback)
    assert(type(callback) == 'function', 'Expected a deferred function')
    if self.world:isLocked() or self._dispatching or self._querying then
        self.commands[#self.commands + 1] = callback
    else
        callback()
    end
end

function Physics2D:flush()
    while #self.commands > 0 do
        local commands = self.commands
        self.commands = {}
        for _, callback in ipairs(commands) do
            callback()
        end
    end
end

function Physics2D:addCollisionGroup(name)
    return self.collisionGroups:add(name)
end

function Physics2D:setGroupsCollidable(a, b, enabled)
    self.collisionGroups:add(a)
    self.collisionGroups:add(b)
    self.collisionGroups:set(a, b, enabled ~= false)
end

function Physics2D:groupsCollide(a, b)
    return self.collisionGroups:interacts(a, b)
end

function Physics2D:setInterpolation(enabled)
    self.interpolate = enabled == true
end

function Physics2D:setGravity(x, y)
    if type(x) ~= 'number' then
        x, y = x[1], x[2]
    end
    assert(
        type(x) == 'number'
            and type(y) == 'number'
            and x == x
            and y == y
            and math.abs(x) < math.huge
            and math.abs(y) < math.huge,
        'Gravity vector must be finite'
    )
    if self.world:isLocked() then
        self:defer(function()
            self:setGravity(x, y)
        end)
        return
    end
    self.world:setGravity(x * self.factor, y * self.factor)
    for _, body in ipairs(self.bodies) do
        if body.type == 'Dynamic' then
            body:wake()
        end
    end
    self.gravity[1], self.gravity[2] = x, y
    require('source.engine.world.gravity').read(self, x, y)
end

function Physics2D:getGravity()
    local x, y = self.world:getGravity()
    return x / self.factor, y / self.factor
end

function Physics2D:release()
    if self.released then
        return
    end
    self:defer(function()
        if self.released then
            return
        end
        for i = #self.constraints, 1, -1 do
            self.constraints[i]:releaseJoint()
        end
        for i = #self.bodies, 1, -1 do
            self.bodies[i]:destroy()
        end
        self.world:destroy()
        if self.queryWorld then
            self.queryWorld:destroy()
        end
        self.events, self.commands, self._drawOrder, self.constraints = {}, {}, {}, {}
        self.queryFixture, self.queryBody, self.chainQueryBody = nil, nil, nil
        self.released = true
    end)
end

Physics2D.update = Simulation.update
Physics2D.raycast = Queries.raycast
Physics2D.raycastAll = Queries.raycastAll
Physics2D.overlapPoint = Queries.overlapPoint
Physics2D.overlapBox = Queries.overlapBox
Physics2D.overlapCircle = Queries.overlapCircle
Physics2D.draw = Drawing.draw
Physics2D.drawDebug = Drawing.debug

return Physics2D
