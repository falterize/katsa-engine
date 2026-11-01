local pairs = require('source.engine.math.array').pairs
-- Named actions with scene-owned bindings; no polling of stale OS-held keys.
local Actions = {}
Actions.__index = Actions

function Actions.new()
    return setmetatable({
        keys = {},
        pressed = {},
        pendingLook = { 0, 0 },
        values = { Move = { 0, 0, 0 }, Look = { 0, 0 }, Jump = false, Interact = false },
        bindings = {
            Move = { left = 'a', right = 'd', forward = 'w', back = 's', up = 'e', down = 'q' },
            Jump = { key = 'space' },
            Interact = { key = 'f' },
        },
        listeners = {},
    }, Actions)
end

function Actions:define(name, binding)
    assert(self.values[name] == nil, 'Action already defined')
    self.values[name] = false
    self.bindings[name] = binding or {}
end

function Actions:bind(name, binding)
    assert(self.values[name] ~= nil, 'Unknown action')
    self.bindings[name] = binding
end

function Actions:on(name, callback)
    assert(self.values[name] ~= nil and type(callback) == 'function', 'Invalid action listener')
    self.listeners[name] = callback
end

function Actions:trigger(name)
    assert(self.values[name] ~= nil, 'Unknown action')
    self.pressed[name] = true
end

function Actions:keypressed(key)
    if not self.keys[key] then
        for name, binding in pairs(self.bindings) do
            if binding.key == key then
                self:trigger(name)
            end
        end
    end
    self.keys[key] = true
end

function Actions:keyreleased(key)
    self.keys[key] = nil
end

function Actions:held(key)
    return key and self.keys[key] and 1 or 0
end

function Actions:look(x, y)
    self.pendingLook[1] = self.pendingLook[1] + x
    self.pendingLook[2] = self.pendingLook[2] + y
end

function Actions:updateMove(x, z, up, down)
    local look = self.values.Look
    look[1], look[2] = self.pendingLook[1], self.pendingLook[2]
    self.pendingLook[1], self.pendingLook[2] = 0, 0
    local b = self.bindings.Move
    local m = self.values.Move
    m[1] = x + self:held(b.right) - self:held(b.left)
    m[2] = up - down + self:held(b.up) - self:held(b.down)
    m[3] = z + self:held(b.forward) - self:held(b.back)
    local length = math.max(1, math.sqrt(m[1] ^ 2 + m[3] ^ 2))
    m[1], m[3] = m[1] / length, m[3] / length
    for name, binding in pairs(self.bindings) do
        if type(self.values[name]) == 'boolean' then
            self.values[name] = self:held(binding.key) > 0
        end
    end
    return m
end

function Actions:consume(name)
    local pressed = self.pressed[name]
    self.pressed[name] = nil
    return pressed == true
end

function Actions:value(name)
    assert(self.values[name] ~= nil, 'Unknown action')
    return self.values[name]
end

function Actions:reset()
    self.keys, self.pressed = {}, {}
    self.pendingLook[1], self.pendingLook[2] = 0, 0
    local m, l = self.values.Move, self.values.Look
    m[1], m[2], m[3], l[1], l[2] = 0, 0, 0, 0, 0
    for name, value in pairs(self.values) do
        if type(value) == 'boolean' then
            self.values[name] = false
        end
    end
end

return Actions
