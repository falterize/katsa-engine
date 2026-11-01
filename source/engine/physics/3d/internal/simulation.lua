local ipairs = require('source.engine.math.array').ipairs
local Triggers = require('source.engine.physics.3d.triggers')
local Simulation = {}

local function step(physics, dt)
    local started = katsa.timer.getTime()
    physics.world:step(dt)
    physics.stats.solverMilliseconds = physics.stats.solverMilliseconds
        + (katsa.timer.getTime() - started) * 1000
    started = katsa.timer.getTime()
    Triggers.step(physics)
    physics.stats.triggerMilliseconds = physics.stats.triggerMilliseconds
        + (katsa.timer.getTime() - started) * 1000
end

function Simulation.install(Physics, Body3D)
    function Physics:update(dt)
        if self.released then
            return
        end
        assert(
            not self._stepping and not self._flushing and not self._querying,
            'Physics:update is not reentrant'
        )
        require('source.engine.world.gravity').apply(self)
        self.stats.steps = 0
        self.stats.triggerQueries, self.stats.triggerCandidates, self.stats.triggerPairs = 0, 0, 0
        self.stats.updateMilliseconds, self.stats.solverMilliseconds, self.stats.triggerMilliseconds =
            0, 0, 0
        if self.paused then
            return
        end
        if self._interpolationMode ~= self.interpolate then
            self:setInterpolation(self.interpolate)
        end
        local started = katsa.timer.getTime()
        assert(
            type(dt) == 'number' and dt == dt and dt >= 0 and dt < math.huge,
            'Physics delta must be finite and nonnegative'
        )
        for _, body in ipairs(self.bodies) do
            body:applyProperties()
        end
        self.accumulator = self.accumulator + dt
        local steps = 0
        while self.accumulator >= self.fixedDelta and steps < self.maxSteps do
            for _, constraint in ipairs(self.constraints or {}) do
                constraint:step(self.fixedDelta)
            end
            if self.beforeStep then
                self.beforeStep(self, self.fixedDelta)
            end
            if self.interpolate then
                for _, body in ipairs(self.bodies) do
                    if body.type ~= 'Static' then
                        body:beginRenderStep()
                    end
                end
            end
            self._stepping = true
            local ok, message = pcall(step, self, self.fixedDelta)
            self._stepping = false
            self:flushBodyChanges()
            if self.released then
                self.stats.steps = steps + 1
                return
            end
            if not ok then
                error(message, 0)
            end
            if self.interpolate then
                for _, body in ipairs(self.bodies) do
                    if body.type ~= 'Static' then
                        body:endRenderStep()
                    end
                end
            end
            self.accumulator = self.accumulator - self.fixedDelta
            steps = steps + 1
        end
        if self.accumulator >= self.fixedDelta then
            self.stats.droppedTime = self.stats.droppedTime + self.accumulator
            self.accumulator = self.accumulator % self.fixedDelta
        end
        for _, body in ipairs(self.bodies) do
            if body.type ~= 'Static' then
                body:sync()
            end
        end
        self.stats.steps = steps
        self.interpolationAlpha = self.accumulator / self.fixedDelta
        self.stats.updateMilliseconds = (katsa.timer.getTime() - started) * 1000
    end
end

return Simulation
