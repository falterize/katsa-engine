local ipairs = require('source.engine.math.array').ipairs

local Game = {}

-- Runs instead of update while the window is unfocused or minimised, if the scene defines it.
-- Only the scene's own hook runs: no UI, animation, camera or rendering work.
function Game:updateInBackground(dt, realDt)
    local demo = self.demo
    if demo and demo.updateInBackground then
        -- The world's TimeScale applies exactly as in a focused update: a hosted server keeps
        -- its pace when the window loses focus.
        local scaled = require('source.engine.world.clock').delta(self.world.root, dt)
        return demo:updateInBackground(scaled, realDt)
    end
end

-- Moves the on-screen joystick to the nearest spot no scene UI covers (a scene's own panels may sit
-- over the default corner). Runs once, on the second frame, when the scene UI exists.
function Game:clearJoystickSpot()
    local joystick = self.controls and self.controls.joystick
    local ui = self.ui
    if not joystick or joystick.custom then
        return
    end
    local function free(cx, cy)
        for step = 0, 8 do
            local angle, reach = step * math.pi / 4, step == 0 and 0 or joystick.radius
            local x = (cx + math.cos(angle) * reach) * ui.scale + ui.offsetX
            local y = (cy + math.sin(angle) * reach) * ui.scale + ui.offsetY
            if ui:hit(x, y) then
                return false
            end
        end
        return true
    end
    if free(joystick.x, joystick.y) then
        return
    end
    local best, bestDistance
    local width, height = ui.width, ui.height
    for _, row in ipairs({ 570 / 720, 630 / 720, 450 / 720, 330 / 720 }) do
        for column = 1, 11 do
            local x, y = width * column / 12, height * row
            local distance = (x - joystick.x) ^ 2 + (y - joystick.y) ^ 2
            if (not best or distance < bestDistance) and free(x, y) then
                best, bestDistance = { x, y }, distance
            end
        end
    end
    if best then
        joystick.x, joystick.y = best[1], best[2]
        joystick.relocated = true
    else
        -- Full-screen tool UI (galleries, viewports): the scene's own widgets take every touch.
        joystick.blocked = true
    end
end

function Game:update(dt, realDt)
    self.frames = (self.frames or 0) + 1
    if self.frames == 2 then
        self:clearJoystickSpot()
    end
    if self.debugOverlay and self.debugOverlay.visible and self.debugOverlay._syncDebug then
        self.debugOverlay._syncDebug()
    end
    if self.console then
        self.console:update()
    end
    local profiler = self.manager.profiler
    local updateStamp = profiler:begin() or (self.showStats and katsa.timer.getTime())
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
        self.camera:update(katsa.graphics.getDimensions())
    end
    local audioStamp = profiler:begin()
    self.audio:update(self.camera)
    profiler:finish('Audio', audioStamp)
    self:syncButtons()
    if updateStamp then
        self.updateMilliseconds = (katsa.timer.getTime() - updateStamp) * 1000
    end
    profiler:finish('Scene update', updateStamp)
end

return Game
