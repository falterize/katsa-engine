-- Human text for an InputMap binding ('key:lctrl+key:s' -> 'Ctrl+S'). Pure Lua.
local Shortcut = {}

local NAMES = {
    lctrl = 'Ctrl', rctrl = 'Ctrl', lshift = 'Shift', rshift = 'Shift', lalt = 'Alt', ralt = 'Alt',
    delete = 'Del', escape = 'Esc', ['return'] = 'Enter', space = 'Space',
}

function Shortcut.format(binding)
    if not binding then
        return ''
    end
    local parts = {}
    for part in binding:gmatch('[^+]+') do
        local kind, name = part:match('^(%w+):(.+)$')
        if kind == 'mouse' then
            parts[#parts + 1] = 'Mouse ' .. name
        elseif kind == 'key' then
            parts[#parts + 1] = NAMES[name] or (#name == 1 and name:upper()) or (name:sub(1, 1):upper() .. name:sub(2))
        elseif kind then
            parts[#parts + 1] = name
        end
    end
    return table.concat(parts, '+')
end

-- The first binding of an action as text, or ''.
function Shortcut.of(map, action)
    if not map or not map:hasAction(action) then
        return ''
    end
    return Shortcut.format(map:getEvents(action)[1])
end

return Shortcut
