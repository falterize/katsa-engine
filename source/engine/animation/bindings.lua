local Array = require('source.engine.math.array')
local pairs = require('source.engine.math.array').pairs

local Bindings = {}

function Bindings.copy(value)
    if require('source.engine.math.managedValue').is(value) then
        return value:clone()
    end
    if not Array.is(value) then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[key] = Bindings.copy(item)
    end
    return result
end

function Bindings.set(target, key, value)
    assert(not target.destroyed, 'Animation target was destroyed')
    if target.body and (key == 'position' or key == 'rotation') then
        assert(
            target.body.type ~= 'Dynamic',
            'Tween of a dynamic body pose is unsupported; use forces or a kinematic body'
        )
        local position = key == 'position' and value or target.position
        local rotation = key == 'rotation' and value or target.rotation
        target.body:teleportLocal(position, rotation)
    else
        local current = target[key]
        if Array.is(value) and Array.is(current) and #current == #value then
            for i = 1, #value do
                current[i] = value[i]
            end
        else
            target[key] = Bindings.copy(value)
        end
    end
    if target.ui then
        target.ui:invalidate()
    end
end

return Bindings
