-- katsa.keyboard: key state and text input (love.keyboard compatible subset).
local Keys = require('source.katsa.platform.sdl2keys')

local Keyboard = {}
local platform
local keyRepeat = false

function Keyboard.setPlatform(p)
    platform = p
end

function Keyboard.setKeyRepeat(enabled)
    keyRepeat = enabled == true
end

function Keyboard.hasKeyRepeat()
    return keyRepeat
end

-- True when repeated key presses should be delivered (used by the event translator).
function Keyboard.acceptsRepeat()
    return keyRepeat
end

-- Keys and scancodes share names for the characters this layer maps, so one lookup serves both.
function Keyboard.isDown(...)
    for i = 1, select('#', ...) do
        local key = select(i, ...)
        if platform and platform:isScancodeDown(Keyboard.getScancodeFromKey(key)) then
            return true
        end
    end
    return false
end

function Keyboard.isScancodeDown(...)
    for i = 1, select('#', ...) do
        if platform and platform:isScancodeDown((select(i, ...))) then
            return true
        end
    end
    return false
end

function Keyboard.getScancodeFromKey(key)
    return key
end

function Keyboard.getKeyFromScancode(scancode)
    return scancode
end

function Keyboard.setTextInput(enabled)
    if platform then
        platform:setTextInput(enabled)
    end
end

function Keyboard.hasTextInput()
    return platform ~= nil and platform.textInput == true
end

Keyboard.scancodeNames = Keys.scancodeNames

return Keyboard
