local pairs = require('../math.array').pairs

local Input = {}
Input.__index = Input

function Input.new(scene, layout)
    -- The map belongs to the scene manager, so bindings survive scene changes; a standalone
    -- Input (tests, tools) gets its own.
    local manager = scene.manager
    local map = manager and manager.inputMap or require('source.engine.input.inputMap').new()
    return setmetatable({
        scene = scene,
        layout = layout,
        actions = require('source.engine.input.actions').new(),
        map = map,
        -- Actions the scene's `settings.input` added; `close` removes them with the scene.
        sceneActions = map:addMissing(scene.settings and scene.settings.input),
        captures = {},
        axisX = 0,
        axisY = 0,
        up = 0,
        down = 0,
    }, Input)
end

-- Called when the scene ends: its own actions leave the shared map, project actions stay.
function Input:close()
    for _, name in ipairs(self.sceneActions) do
        self.map:removeAction(name)
    end
    self.sceneActions = {}
end

function Input:reset()
    self.actions:reset()
    self.map:reset()
    for id, c in pairs(self.captures) do
        if c.node then
            c.node.ui:pointer(c.node, 'cancel', 0, 0, id)
        end
        if c.pendingClick then
            require('source.engine.world.picking').each(c.pendingClick.detectors, 'cancel', id)
        end
    end
    if self.hovered and not self.hovered.destroyed then
        self.hovered.ui:pointer(self.hovered, 'leave', 0, 0, 'mouse')
    end
    self.hovered = nil
    self.hoverX, self.hoverY = nil, nil
    self.captures = {}
    self.axisX, self.axisY, self.up, self.down = 0, 0, 0, 0
    self.joystickId = nil
    self.cameraId = nil
    katsa.mouse.setRelativeMode(false)
end
require('./pointers').install(Input)
require('./movement').install(Input)
require('./gamepads').install(Input)

function Input:keypressed(key)
    local focused = require('source.engine.ui.widgets.textFocus').current
    if focused then
        return focused:sendKey(key)
    end
    self.map:setEventStrength('key:' .. key, 1)
    self.actions:keypressed(key)
    return false
end

function Input:textinput(text)
    local focused = require('source.engine.ui.widgets.textFocus').current
    if focused then
        focused:insertText(text)
        return true
    end
    return false
end

function Input:keyreleased(key)
    self.map:setEventStrength('key:' .. key, 0)
    self.actions:keyreleased(key)
end

-- Mouse buttons and the wheel reach the map from the scene runtime (any button, not only the
-- pointer's primary one). A wheel notch is a momentary event.
function Input:mapMouseButton(button, down)
    self.map:setEventStrength('mouse:' .. button, down and 1 or 0)
end

function Input:mapWheel(_, y)
    if y ~= 0 then
        self.map:tapEvent(y > 0 and 'wheel:up' or 'wheel:down')
    end
end

-- Presses a named action from code: an InputMap action when the map has it, else a built-in one
-- (Jump, Interact).
function Input:trigger(action)
    if self.map:hasAction(action) then
        self.map:triggerAction(action)
        return
    end
    self.actions:trigger(action)
end

function Input:cancel(id)
    local capture = self.captures[id]
    if not capture then
        return
    end
    if capture.node then
        capture.node.ui:pointer(capture.node, 'cancel', 0, 0, id)
    end
    if self.joystickId == id then
        self.joystickId = nil
        self.axisX, self.axisY = 0, 0
    end
    if self.cameraId == id then
        self.cameraId = nil
        self.actions.pendingLook[1], self.actions.pendingLook[2] = 0, 0
    end
    self.captures[id] = nil
end

function Input:draw()
    if self.layout then
        if not self.joystickView then
            self.joystickView = require('source.engine.input.joystickView').new(self)
        end
        self.joystickView:update()
    end
end

return Input
