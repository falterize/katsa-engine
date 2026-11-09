local pairs = require('../math.array').pairs

local Input = {}
Input.__index = Input

function Input.new(scene, layout)
    return setmetatable({
        scene = scene,
        layout = layout,
        actions = require('source.engine.input.actions').new(),
        captures = {},
        axisX = 0,
        axisY = 0,
        up = 0,
        down = 0,
    }, Input)
end

function Input:reset()
    self.actions:reset()
    for id, c in pairs(self.captures) do
        if c.node then
            c.node.ui:pointer(c.node, 'cancel', 0, 0, id)
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
        return focused:editKey(key)
    end
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
    self.actions:keyreleased(key)
end

function Input:trigger(action)
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
