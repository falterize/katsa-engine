local ipairs = require('../../math.array').ipairs
local Sequence = require('../../animation.sequence')
local Copy = require('../../animation.bindings').copy

local Model = {}

local function finite(value)
    return type(value) == 'number' and value == value and math.abs(value) < math.huge
end

function Model.insert(points, time, interpolation)
    assert(finite(time) and time > 0 and time < 1, 'New point time must be between 0 and 1')
    for _, point in ipairs(points) do
        assert(math.abs(point.time - time) >= 0.0001, 'A point already exists at this time')
    end
    local point = { time = time, value = Copy(Sequence.evaluate(points, time, interpolation)) }
    points[#points + 1] = point
    table.sort(points, function(a, b)
        return a.time < b.time
    end)
    for i, p in ipairs(points) do
        if p == point then
            if points[i - 1] then
                points[i - 1].outgoing = nil
            end
            if points[i + 1] then
                points[i + 1].incoming = nil
            end
            return i
        end
    end
end

function Model.time(points, index, time)
    assert(finite(time) and time >= 0 and time <= 1, 'Time must be a finite number within 0..1')
    local previous, nextPoint = points[index - 1], points[index + 1]
    assert(not previous or time > previous.time, 'Time must be after the previous point')
    assert(not nextPoint or time < nextPoint.time, 'Time must be before the next point')
    points[index].time = time
    points[index].incoming, points[index].outgoing = nil, nil
    if previous then
        previous.outgoing = nil
    end
    if nextPoint then
        nextPoint.incoming = nil
    end
end

function Model.remove(points, index)
    assert(#points > 2, 'A sequence needs at least two points')
    assert(index > 1 and index < #points, 'Keep the two endpoint points')
    table.remove(points, index)
    if points[index - 1] then
        points[index - 1].outgoing = nil
    end
    if points[index] then
        points[index].incoming = nil
    end
end

return Model
