local Keymap = require('./keymap')

-- Feeds katsa input events to ImGui's io. Every handler returns true when ImGui wants the event
-- (the pointer is over a window, a text field has focus ...), so the caller can stop it there.
local Input = {}
Input.__index = Input

function Input.new(C, io)
    return setmetatable({ C = C, io = io, held = {}, touch = nil }, Input)
end

function Input:position(x, y)
    self.C.ImGuiIO_AddMousePosEvent(self.io, x, y)
end

-- Pointer ids: 'mouse' or a touch id. A touch acts as the left button.
function Input:pointerpressed(id, x, y)
    self:position(x, y)
    if id ~= 'mouse' then
        self.touch = id
        self.C.ImGuiIO_AddMouseButtonEvent(self.io, 0, true)
    end
    return self.io.WantCaptureMouse
end

function Input:pointermoved(id, x, y)
    if id == 'mouse' or id == self.touch then
        self:position(x, y)
    end
    return self.io.WantCaptureMouse
end

function Input:pointerreleased(id, x, y)
    local captured = self.io.WantCaptureMouse
    if id == self.touch then
        self:position(x, y)
        self.C.ImGuiIO_AddMouseButtonEvent(self.io, 0, false)
        self.touch = nil
    end
    return captured
end

-- Mouse buttons arrive separately from pointer events: 1 left, 2 right, 3 middle.
function Input:mousebutton(button, down)
    self.C.ImGuiIO_AddMouseButtonEvent(self.io, button - 1, down)
    return self.io.WantCaptureMouse
end

function Input:wheelmoved(x, y)
    self.C.ImGuiIO_AddMouseWheelEvent(self.io, x, y)
    return self.io.WantCaptureMouse
end

function Input:key(name, down)
    local key = Keymap.key(self.C, name)
    if key then
        self.C.ImGuiIO_AddKeyEvent(self.io, key, down)
    end
    return self.io.WantCaptureKeyboard
end

function Input:textinput(text)
    if self.io.WantTextInput then
        self.C.ImGuiIO_AddInputCharactersUTF8(self.io, text)
        return true
    end
    return false
end

return Input
