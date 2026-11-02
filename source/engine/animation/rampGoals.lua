local Array = require('../math.array')
local ipairs = require('../math.array').ipairs
local pairs = require('../math.array').pairs
local Sequence = require('./sequence')
local Copy = require('./bindings').copy

local Goals = {}

local function numeric(value)
    if type(value) == 'number' then
        return value == value and math.abs(value) < math.huge
    end
    if not Array.is(value) or #value < 2 or #value > 4 then
        return false
    end
    for _, v in ipairs(value) do
        if not numeric(v) or type(v) ~= 'number' then
            return false
        end
    end
    return true
end

function Goals.candidates(ramp)
    local target = ramp:getTarget()
    local result = {}
    if not target or target.destroyed then
        return result
    end
    if ramp:isLifetime() then
        for key, value in pairs({ size = 1, color = { 1, 1, 1 }, transparency = 0, rotation = 0 }) do
            result[#result + 1] = { key = key, value = value }
        end
    else
        for _, field in ipairs(require('source.engine.editor.inspectors.properties').list(target)) do
            if not field.readOnly and numeric(field.value) then
                result[#result + 1] =
                    { key = field.key, value = field.value, labels = field.labels }
            end
        end
    end
    table.sort(result, function(a, b)
        return a.key < b.key
    end)
    return result
end

function Goals.value(ramp, key)
    local target = ramp:getTarget()
    if target and not ramp:isLifetime() and numeric(target[key]) then
        return Copy(target[key])
    end
    for _, field in ipairs(Goals.candidates(ramp)) do
        if field.key == key then
            return Copy(field.value)
        end
    end
    error('Unknown or nonnumeric Ramp goal: ' .. tostring(key))
end

function Goals.add(ramp, key, value)
    local current = Goals.value(ramp, key)
    value = Copy(value or current)
    assert(numeric(value), 'Ramp goal must be a finite number or vector')
    assert(
        type(value) == type(current) and (not Array.is(value) or #value == #current),
        'Ramp goal dimensions do not match target'
    )
    ramp.goals[key] = value
    ramp.bindings[key] = Sequence.linear(Copy(current), Copy(value))
    ramp.bindings[key].interpolation = 'Linear'
    if ramp.ui then
        ramp.ui:invalidate()
    end
    return ramp
end

function Goals.ensureTarget(ramp)
    local target = ramp:getTarget()
    for key in pairs(ramp.goals) do
        if target[key] == nil then
            target[key] = Goals.value(ramp, key)
        end
    end
end

return Goals
