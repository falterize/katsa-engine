local Array = require('source.engine.math.array')

local Validate = {}

function Validate.number(value, name, minimum, maximum)
    if type(value) ~= 'number' or value ~= value or math.abs(value) == math.huge then
        error(name .. ' must be a finite number', 2)
    end
    if minimum and value < minimum then
        error(name .. ' must be at least ' .. tostring(minimum), 2)
    end
    if maximum and value > maximum then
        error(name .. ' must be at most ' .. tostring(maximum), 2)
    end
    return value
end

function Validate.vector(value, name, count)
    if not Array.is(value) then
        error(name .. ' must be a numeric table', 2)
    end
    for i = 1, count do
        local component = value[i]
        if
            type(component) ~= 'number'
            or component ~= component
            or math.abs(component) == math.huge
        then
            Validate.number(component, name .. '[' .. i .. ']')
        end
    end
end

return Validate
