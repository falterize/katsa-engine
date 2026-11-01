local Contacts = require('source.engine.physics.2d.contacts')

local Simulation = {}

local function capture(body, previous)
    local x, y = body:getPosition()
    if previous then
        body.previousX, body.previousY, body.previousAngle = x, y, body.raw:getAngle()
    else
        body.currentX, body.currentY, body.currentAngle = x, y, body.raw:getAngle()
    end
end

function Simulation.update(self, dt)
    if self.released then
        return
    end
    assert(not self._updating, 'Physics2D:update is not reentrant')
    assert(type(dt) == 'number' and dt >= 0 and dt < math.huge, 'Invalid Physics2D delta')
    require('source.engine.world.gravity').apply(self)
    self.stats.steps, self.stats.solverMilliseconds = 0, 0
    if self.paused then
        return
    end
    self._updating = true
    local started = katsa.timer.getTime()
    local ok, message = pcall(function()
        self:flush()
        Contacts.dispatch(self)
        if self.released then
            return
        end
        for _, body in ipairs(self.bodies) do
            body:applyProperties()
        end
        Contacts.dispatch(self)
        if self.released then
            return
        end
        self.accumulator = self.accumulator + dt
        while self.accumulator >= self.fixedDelta and self.stats.steps < self.maxSteps do
            for _, constraint in ipairs(self.constraints) do
                constraint:step(self.fixedDelta)
            end
            if self.beforeStep then
                self:beforeStep(self.fixedDelta)
            end
            for _, body in ipairs(self.bodies) do
                capture(body, true)
            end
            local solver = katsa.timer.getTime()
            self.world:update(self.fixedDelta, self.velocityIterations, self.positionIterations)
            self.stats.solverMilliseconds = self.stats.solverMilliseconds
                + (katsa.timer.getTime() - solver) * 1000
            for _, body in ipairs(self.bodies) do
                capture(body, false)
            end
            for _, constraint in ipairs(self.constraints) do
                constraint:checkBreak(self.fixedDelta)
            end
            Contacts.dispatch(self)
            if self.released then
                return
            end
            self.accumulator = self.accumulator - self.fixedDelta
            self.stats.steps = self.stats.steps + 1
            if self.afterStep then
                self:afterStep(self.fixedDelta)
            end
        end
        if self.released then
            return
        end
        if self.accumulator >= self.fixedDelta then
            local retained = self.accumulator % self.fixedDelta
            self.stats.droppedTime = self.stats.droppedTime + self.accumulator - retained
            self.accumulator = retained
        end
        for _, body in ipairs(self.bodies) do
            body:sync()
        end
        self.interpolationAlpha = self.accumulator / self.fixedDelta
        self.stats.bodies = #self.bodies
        self.stats.contacts = self.world:getContactCount()
        self.stats.joints = self.world:getJointCount()
        local sleeping, fixtures = 0, 0
        for _, body in ipairs(self.bodies) do
            sleeping = sleeping + (body:isSleeping() and 1 or 0)
            fixtures = fixtures + #body.fixtures
        end
        self.stats.sleeping, self.stats.fixtures = sleeping, fixtures
    end)
    self._updating = false
    self.stats.updateMilliseconds = (katsa.timer.getTime() - started) * 1000
    if not ok then
        error(message, 0)
    end
end

return Simulation
