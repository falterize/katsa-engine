-- katsa key names -> ImGuiKey enum names.
local Keymap = {}

local names = {
    ['return'] = 'Enter',
    kpenter = 'KeypadEnter',
    escape = 'Escape',
    tab = 'Tab',
    backspace = 'Backspace',
    delete = 'Delete',
    insert = 'Insert',
    home = 'Home',
    ['end'] = 'End',
    pageup = 'PageUp',
    pagedown = 'PageDown',
    space = 'Space',
    left = 'LeftArrow',
    right = 'RightArrow',
    up = 'UpArrow',
    down = 'DownArrow',
    lctrl = 'LeftCtrl',
    rctrl = 'RightCtrl',
    lshift = 'LeftShift',
    rshift = 'RightShift',
    lalt = 'LeftAlt',
    ralt = 'RightAlt',
}
for code = string.byte('a'), string.byte('z') do
    names[string.char(code)] = string.char(code):upper()
end
for digit = 0, 9 do
    names[tostring(digit)] = tostring(digit)
end
for number = 1, 12 do
    names['f' .. number] = 'F' .. number
end

-- The ImGuiKey constant for a katsa key name, or nil for keys ImGui has no use for.
function Keymap.key(C, name)
    local suffix = names[name]
    return suffix and C['ImGuiKey_' .. suffix] or nil
end

return Keymap
