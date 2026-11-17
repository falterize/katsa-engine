-- Keyboard and mouse of the voxel player: look (captured mouse), walk/fly keys, the hotbar and
-- the break/place buttons. Tab frees the mouse for the engine menu and the block picker.
local Base = require('source.engine.input.input')

local Input = setmetatable({}, { __index = Base })
Input.__index = Input

local REPEAT_DELAY, DOUBLE_TAP = 0.22, 0.3

function Input.new(scene, state)
    local self = setmetatable(Base.new(scene, scene.controls), Input)
    self.state, self.captureWanted = state, true
    self.menuKey = scene.settings.presentation.menuKey or 'tab'
    self.buttons, self.cooldown, self.lastSpace = {}, 0, -1
    -- The engine's default free camera would also read W/A/S/D and the mouse; the voxel player
    -- owns them, so the default listeners are replaced by empty ones.
    self.actions:on('Move', function() end)
    self.actions:on('Look', function() end)
    return self
end

function Input:playing()
    local scene = self.scene
    return scene.manager.focused ~= false
        and self.captureWanted
        and not scene:consume('capturesInput')
        and not scene.showStats
        and not scene.freeDebugCamera
end

function Input:update(dt)
    local playing = self:playing()
    if katsa.mouse.getRelativeMode() ~= playing then
        katsa.mouse.setRelativeMode(playing)
    end
    Base.update(self, dt)
    local walker, down = self.state.walker, katsa.keyboard.isDown
    walker.forward = playing and ((down('w') and 1 or 0) - (down('s') and 1 or 0)) or 0
    walker.strafe = playing and ((down('d') and 1 or 0) - (down('a') and 1 or 0)) or 0
    walker.jump = playing and down('space')
    walker.descend = playing and down('lshift')
    walker.sprint = playing and down('lctrl')
    self.cooldown = math.max(0, self.cooldown - dt)
    if playing and self.cooldown == 0 then
        -- Holding a button repeats the action, like creative mode.
        if self.buttons[1] then
            self.state.interaction:breakBlock()
            self.cooldown = REPEAT_DELAY
        elseif self.buttons[2] then
            self.state.interaction:placeBlock()
            self.cooldown = REPEAT_DELAY
        end
    end
end

function Input:mapMouseButton(button, down)
    Base.mapMouseButton(self, button, down)
    self.buttons[button] = down or nil
    if not (down and self:playing()) then
        return
    end
    local interaction = self.state.interaction
    if button == 1 then
        interaction:breakBlock()
        self.cooldown = REPEAT_DELAY
    elseif button == 2 then
        interaction:placeBlock()
        self.cooldown = REPEAT_DELAY
    elseif button == 3 then
        interaction:pickBlock()
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
        self.state.look(dx, dy)
        return
    end
    Base.move(self, id, x, y, dx, dy)
end

function Input:toggleMenu()
    local hotbar = self.state.hotbar
    if hotbar.pickerOpen then
        hotbar:hidePicker()
    end
    self.captureWanted = not self.captureWanted
    self:reset()
    self.buttons = {}
    self.scene:emit('immersion', self.captureWanted)
    if self.menuButton then
        self.menuButton.text = self.captureWanted and 'Engine menu' or 'Resume game'
    end
    katsa.mouse.setRelativeMode(self:playing())
end

function Input:keypressed(key)
    if key == self.menuKey then
        self:toggleMenu()
        return
    end
    local state = self.state
    if key == 'e' and state.hotbar.pickerOpen then
        state.hotbar:togglePicker()
        return true
    end
    if not self:playing() then
        return Base.keypressed(self, key)
    end
    local slot = tonumber(key)
    if slot and slot >= 1 and slot <= 9 then
        state.hotbar:select(slot)
        return true
    end
    if key == 'space' then
        -- Double tap flies, like creative mode.
        local now = katsa.timer.getTime()
        if now - self.lastSpace < DOUBLE_TAP then
            state.walker:toggleFly()
        end
        self.lastSpace = now
        return true
    elseif key == 'f' then
        state.walker:toggleFly()
        return true
    elseif key == 'e' then
        state.hotbar:togglePicker()
        return true
    end
    return Base.keypressed(self, key)
end

function Input:wheelmoved(_, y)
    if not self:playing() then
        return false
    end
    self.state.hotbar:scroll(y > 0 and -1 or 1)
    return true
end

function Input:draw() end

return Input
