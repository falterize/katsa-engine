local Base = require('source.engine.input.input')

local Input = setmetatable({}, { __index = Base })
Input.__index = Input

function Input.new(scene, player, orbit)
    local self = setmetatable(Base.new(scene, scene.controls), Input)
    self.player, self.orbit, self.captureWanted = player, orbit, true
    self.menuKey = scene.settings.presentation.menuKey or 'tab'
    self.actions:bind('Move', { left = 'a', right = 'd', forward = 'w', back = 's' })
    self.actions:on('Move', function(_, movement, dt)
        if scene.freeDebugCamera then
            scene.camera:move(
                movement[1],
                movement[3],
                movement[2],
                dt,
                scene.controls.speed,
                scene.controls.verticalSpeed
            )
        else
            player:setMove(movement[1], movement[3])
        end
    end)
    self.actions:on('Look', function(_, look)
        if scene.freeDebugCamera then
            scene.camera:look(look[1], look[2], scene.controls.sensitivity)
        elseif self:playing() then
            orbit:look(look[1], look[2])
        end
    end)
    self.actions:on('Jump', function() end) -- The source FSM polls held Space.
    return self
end

function Input:playing()
    local scene = self.scene
    return scene.manager.focused ~= false
        and self.captureWanted
        and not (scene.workspace and scene.workspace.opened)
        and not scene.showStats
        and not (scene.debugOverlay and scene.debugOverlay.visible)
        and not scene.freeDebugCamera
end

function Input:update(dt)
    local playing = self:playing()
    if self.captureMouse ~= false and katsa.mouse.getRelativeMode() ~= playing then
        katsa.mouse.setRelativeMode(playing)
    end
    Base.update(self, dt)
    local input, keys = self.player.input, self.actions.keys
    input.jump = playing and keys.space == true
    input.sprint = playing and keys.lshift == true
    input.crouch = playing and (keys.lctrl == true or keys.c == true)
    input.shiftlock = playing and keys.q == true
    if not playing then
        self.player:setMove(0, 0)
    end
end

function Input:press(id, x, y)
    if id == 'mouse' and katsa.mouse.getRelativeMode() and self:playing() then
        return
    end
    Base.press(self, id, x, y)
end

function Input:move(id, x, y, dx, dy)
    if id == 'mouse' and katsa.mouse.getRelativeMode() and self:playing() then
        self.actions:look(dx, dy)
        return
    end
    Base.move(self, id, x, y, dx, dy)
end

function Input:toggleMenu()
    self.captureWanted = not self.captureWanted
    self:reset()
    self.player:setMove(0, 0)
    local input = self.player.input
    input.jump, input.sprint, input.crouch, input.shiftlock = false, false, false, false
    self.scene:setNavigationVisible(not self.captureWanted)
    if self.menuButton then
        self.menuButton.text = self.captureWanted and 'Engine menu' or 'Resume game'
    end
    if self.captureMouse ~= false then
        katsa.mouse.setRelativeMode(self:playing())
    end
end

function Input:keypressed(key)
    if key == self.menuKey then
        self:toggleMenu()
        return
    elseif key == 'f6' then
        self.scene.demo.retro.enabled = not self.scene.demo.retro.enabled
    end
    Base.keypressed(self, key)
end

function Input:wheelmoved(_, y)
    if not self:playing() then
        return false
    end
    self.orbit:zoom(y)
    return true
end

function Input:draw() end -- The original desktop game has no joystick overlay.

return Input
