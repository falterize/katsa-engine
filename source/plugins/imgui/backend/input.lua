local Keymap = require('./keymap')

-- Feeds katsa input events to ImGui's io. Every handler returns true when ImGui wants the event
-- (the pointer is over a window, a text field has focus ...), so the caller can stop it there.
local Input = {}
Input.__index = Input

function Input.new(C, io)
    return setmetatable({ C = C, io = io, held = {}, touch = nil }, Input)
end

-- ImGui's "no mouse" position: nothing is hovered.
local AWAY = -3.4028235e38

-- True while the game holds the cursor (relative mouse mode: first-person look). The cursor is
-- then not a pointer on the screen, so ImGui must not hover or click anything under it.
function Input:locked()
    return katsa.mouse.getRelativeMode() == true
end

-- Called every frame: moves ImGui's pointer away and lets go of the buttons the moment the game
-- takes the cursor, and restores nothing (the next real event sets the position again).
function Input:sync()
    local locked = self:locked()
    if locked and not self.wasLocked then
        self.C.ImGuiIO_AddMousePosEvent(self.io, AWAY, AWAY)
        for button = 0, 2 do
            self.C.ImGuiIO_AddMouseButtonEvent(self.io, button, false)
        end
    end
    self.wasLocked = locked
end

function Input:position(x, y)
    self.C.ImGuiIO_AddMousePosEvent(self.io, x, y)
end

-- Pointer ids: 'mouse' or a touch id. A touch acts as the left button.
function Input:pointerpressed(id, x, y)
    if id == 'mouse' and self:locked() then
        return false
    end
    self:position(x, y)
    if id ~= 'mouse' then
        self.touch = id
        self.C.ImGuiIO_AddMouseButtonEvent(self.io, 0, true)
    end
    return self.io.WantCaptureMouse
end

function Input:pointermoved(id, x, y)
    if id == 'mouse' and self:locked() then
        return false
    end
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
    if down and self:locked() then
        return false
    end
    self.C.ImGuiIO_AddMouseButtonEvent(self.io, button - 1, down)
    return self.io.WantCaptureMouse
end

function Input:wheelmoved(x, y)
    if self:locked() then
        return false
    end
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
