local ipairs = require('source.engine.math.array').ipairs

local Game = {}

function Game:update(dt, realDt)
    if self.debugOverlay and self.debugOverlay.visible and self.debugOverlay._syncDebug then
        self.debugOverlay._syncDebug()
    end
    local profiler = self.manager.profiler
    local updateStamp = profiler:begin() or (self.showStats and love.timer.getTime())
    if self.world.activeCamera then
        self.camera = self.world.activeCamera
    end
    if self.character and not self.freeDebugCamera then
        self.character.camera = self.camera
    end
    local sceneDt = dt
    local uiDt = realDt or dt
    -- Wall-clock frame time for throttles (Animator.poseRate) that must not slow with TimeScale.
    self.world.frameRealDelta = uiDt
    dt = require('source.engine.world.clock').delta(self.world.root, dt)
    if self.lifecycle then
        self.lifecycle.update2D(self.demo, sceneDt, realDt or uiDt)
    else
        self.ui:update(uiDt, sceneDt)
        for _, board in ipairs(self.world.billboards) do
            board.ui:update(realDt or dt)
        end
    end
    self.time = self.time + dt
    self.workspace:update(realDt or dt)
    if self.world.activeCamera then
        self.camera = self.world.activeCamera
    end
    local inputStamp = profiler:begin()
    self.input:update((self.workspace.editing or self.workspace.popup) and 0 or dt)
    profiler:finish('Input', inputStamp)
    local nodesStamp = profiler:begin()
    if self.lifecycle then
        self.lifecycle.update(self.demo, dt)
        self.lifecycle.update3D(self.demo, dt)
    else
        if self.demo and self.demo.update then
            self.demo:update(dt)
        elseif not self.demo then
            self.world:updateNodes(dt)
        end
        self.systems:update(dt)
    end
    profiler:finish('Node/gameplay/physics update', nodesStamp)
    if self.model and not self.model.animator and not self.model.controller then
        local animationStamp = profiler:begin()
        self.model:update(dt)
        profiler:finish('Node animation', animationStamp)
    end
    self.world:updateCameras(dt)
    if self.character and not self.freeDebugCamera then
        self.character.camera = self.camera
    end
    if self.world.activeCamera then
        self.camera:update(love.graphics.getDimensions())
    end
    local audioStamp = profiler:begin()
    self.audio:update(self.camera)
    profiler:finish('Audio', audioStamp)
    self:syncButtons()
    if updateStamp then
        self.updateMilliseconds = (love.timer.getTime() - updateStamp) * 1000
    end
    profiler:finish('Scene update', updateStamp)
end

return Game
