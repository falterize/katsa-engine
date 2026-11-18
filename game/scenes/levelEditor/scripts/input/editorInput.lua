-- Keyboard and mouse of the editor on top of the engine Input. It adds only what the InputMap
-- cannot express: the relative mouse motion while the look action is held, and the viewport
-- click (a press that no UI node took). Everything else is an action read from the map.
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
    local fly = self.state.fly
    local looking = self.lookActive and self.map:isDown('editorLook') and fly ~= nil
    if katsa.mouse.getRelativeMode() ~= looking then
        katsa.mouse.setRelativeMode(looking)
    end
    Base.update(self, dt)
end

function Input:mapMouseButton(button, down)
    Base.mapMouseButton(self, button, down)
    if button == 2 then
        -- Looking starts only from a press in the viewport, never on a panel.
        self.lookActive = down and not self.state:overUI() or false
    elseif button == 1 and down and not self.state:overUI() then
        self.state.viewportPressed = true
    end
end

function Input:move(id, x, y, dx, dy)
    if id == 'mouse' and self.lookActive and katsa.mouse.getRelativeMode() then
        self.state.fly:look(dx, dy)
        return
    end
    Base.move(self, id, x, y, dx, dy)
end

function Input:draw() end

return Input
