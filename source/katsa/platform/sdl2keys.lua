-- Maps SDL keycodes and scancodes to LÖVE-style key and scancode names.
local Keys = {}

local scancodeNames = {}

local function set(from, names)
    for i, name in ipairs(names) do
        scancodeNames[from + i - 1] = name
    end
end

local letters = {}
for c = 97, 122 do
    letters[#letters + 1] = string.char(c)
end
set(4, letters)
set(30, { '1', '2', '3', '4', '5', '6', '7', '8', '9', '0' })
set(40, { 'return', 'escape', 'backspace', 'tab', 'space', '-', '=', '[', ']', '\\', 'nonusbackslash', ';', "'", '`', ',', '.', '/', 'capslock' })
set(58, { 'f1', 'f2', 'f3', 'f4', 'f5', 'f6', 'f7', 'f8', 'f9', 'f10', 'f11', 'f12', 'printscreen', 'scrolllock', 'pause', 'insert', 'home', 'pageup', 'delete', 'end', 'pagedown', 'right', 'left', 'down', 'up', 'numlock' })
set(84, { 'kp/', 'kp*', 'kp-', 'kp+', 'kpenter', 'kp1', 'kp2', 'kp3', 'kp4', 'kp5', 'kp6', 'kp7', 'kp8', 'kp9', 'kp0', 'kp.', 'nonusbackslash', 'application', 'power', 'kp=' })
set(104, { 'f13', 'f14', 'f15', 'f16', 'f17', 'f18', 'f19', 'f20', 'f21', 'f22', 'f23', 'f24' })
set(224, { 'lctrl', 'lshift', 'lalt', 'lgui', 'rctrl', 'rshift', 'ralt', 'rgui' })
-- Android back/menu style keys arrive as SDL scancodes 270+ on some builds.
scancodeNames[118] = 'menu'

Keys.scancodeNames = scancodeNames

local keyOverrides = { application = 'menu' }

local SCANCODE_MASK = 0x40000000

-- Returns key name, scancode name for an SDL keysym.
function Keys.fromSDL(sym, scancode)
    local scancodeName = scancodeNames[scancode] or 'unknown'
    local key
    if sym >= 32 and sym < 127 then
        key = string.char(sym)
        if key == ' ' then
            key = 'space'
        end
    elseif sym == 13 then
        key = 'return'
    elseif sym == 27 then
        key = 'escape'
    elseif sym == 8 then
        key = 'backspace'
    elseif sym == 9 then
        key = 'tab'
    elseif sym == 127 then
        key = 'delete'
    elseif sym >= SCANCODE_MASK then
        key = scancodeNames[sym - SCANCODE_MASK] or 'unknown'
    else
        key = scancodeName
    end
    return keyOverrides[key] or key, scancodeName
end

-- Reverse lookup used by keyboard.isDown / isScancodeDown.
local scancodeByName = {}
for code, name in pairs(scancodeNames) do
    scancodeByName[name] = scancodeByName[name] or code
end
Keys.scancodeByName = scancodeByName

return Keys
