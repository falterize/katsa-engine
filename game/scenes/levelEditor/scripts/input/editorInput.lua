-- Keyboard and mouse of the editor on top of the engine Input. It adds only what the InputMap
-- cannot express: the relative mouse motion while the look action is held, and the viewport
-- click (a press that no UI node took). Everything else is an action read from the map.
local Pointer = require('./pointer')
local Base = require('source.engine.input.input')

local Input = setmetatable({}, { __index = Base })
Input.__index = Input

function Input.new(scene, state)
    local self = setmetatable(Base.new(scene, scene.controls), Input)
    self.state = state
    self.lookActive = false
    -- The engine's default free camera would also read W/A/S/D and the mouse.
    self.actions:on('Move', function() end)
    self.actions:on('Look', function() end)
    return self
end

function Input:update(dt)
    -- A long press of a finger is the right click of touch screens.
    if Pointer.update(dt) and not self.state:overUI() then
        self.state.rmbTap = { x = Pointer.x, y = Pointer.y }
    end
    local fly = self.state.fly
    local looking = self.lookActive and self.map:isDown('editorLook') and fly ~= nil
    if katsa.mouse.getRelativeMode() ~= looking then
        katsa.mouse.setRelativeMode(looking)
    end
    Base.update(self, dt)
end

-- Touch: the first finger that no touch control owns acts as the mouse (left button), so every
-- panel and the viewport react to it; a long press is a right click (see update). Fingers on the
-- on-screen controls never reach the editor.
function Input:press(id, x, y)
    if id ~= 'mouse' then
        local touch = self.state.touch
        if touch and touch:press(id, x, y) then
            return
        end
        if not Pointer.id then
            Pointer.begin(id, x, y)
            self:mapMouseButton(1, true)
        end
    end
    Base.press(self, id, x, y)
end

function Input:release(id, x, y)
    local touch = self.state.touch
    if id ~= 'mouse' then
        if touch and touch:release(id, x, y) then
            return
        end
        if id == Pointer.id then
            Pointer.move(x or Pointer.x, y or Pointer.y, 0, 0)
            Pointer.finish()
            self:mapMouseButton(1, false)
        end
    end
    Base.release(self, id, x, y)
end

function Input:cancel(id)
    local touch = self.state.touch
    if id ~= 'mouse' then
        if touch and touch:release(id) then
            return
        end
        if id == Pointer.id then
            Pointer.finish()
            self:mapMouseButton(1, false)
        end
    end
    Base.cancel(self, id)
end

function Input:mapMouseButton(button, down)
    Base.mapMouseButton(self, button, down)
    if button == 2 then
        -- Looking starts only from a press in the viewport, never on a panel.
        self.lookActive = down and not self.state:overUI() or false
        if self.lookActive then
            self.rmb = { x = Pointer.getX(), y = Pointer.getY(), moved = 0, time = katsa.timer.getTime() }
        elseif not down and self.rmb then
            -- A short press that barely moved is a click, not a look: it asks for a context menu.
            local rmb = self.rmb
            if rmb.moved < 4 and katsa.timer.getTime() - rmb.time < 0.4 then
                self.state.rmbTap = { x = rmb.x, y = rmb.y }
            end
            self.rmb = nil
        end
    elseif button == 1 and down and not self.state:overUI() then
        self.state.viewportPressed = true
    end
end

function Input:move(id, x, y, dx, dy)
    if id ~= 'mouse' then
        local touch = self.state.touch
        if touch and touch:move(id, x, y, dx, dy) then
            return
        end
        if id == Pointer.id then
            Pointer.move(x, y, dx, dy)
        end
    end
    if id == 'mouse' and self.lookActive and katsa.mouse.getRelativeMode() then
        if self.rmb then
            self.rmb.moved = self.rmb.moved + math.abs(dx) + math.abs(dy)
        end
        self.state.fly:look(dx, dy)
        return
    end
    Base.move(self, id, x, y, dx, dy)
end

function Input:reset()
    Pointer.reset()
    if self.state.touch then
        self.state.touch:reset()
    end
    Base.reset(self)
end

function Input:draw() end

return Input
