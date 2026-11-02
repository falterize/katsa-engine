local Array = require('../math.array')
local ipairs = require('../math.array').ipairs
-- Serializable piecewise numeric/vector sequences; no callbacks in authored data.
local Sequence = {}

local function finite(v)
    return type(v) == 'number' and v == v and math.abs(v) < math.huge
end

function Sequence.handleTimes(a, b)
    local span = b.time - a.time
    return a.outgoing and a.outgoing[1] or a.time + span / 3,
        b.incoming and b.incoming[1] or b.time - span / 3
end

function Sequence.validate(points)
    assert(Array.is(points) and #points >= 2, 'Ramp needs at least two points')
    assert(
        points.interpolation == nil
            or points.interpolation == 'Linear'
            or points.interpolation == 'Curve',
        'Sequence interpolation must be Linear or Curve'
    )
    local previous = -1
    for _, point in ipairs(points) do
        assert(
            finite(point.time) and point.time >= 0 and point.time <= 1 and point.time > previous,
            'Ramp point times must increase within 0..1'
        )
        previous = point.time
        local value = point.value
        if Array.is(value) then
            assert(#value > 0, 'Ramp vector must not be empty')
            for _, component in ipairs(value) do
                assert(finite(component), 'Invalid Ramp vector')
            end
        else
            assert(finite(value), 'Ramp values must be numbers or numeric vectors')
        end
        assert(
            (Array.is(value) and Array.is(points[1].value)) or type(value) == type(points[1].value),
            'Ramp value types must match'
        )
        if Array.is(value) then
            assert(#value == #points[1].value, 'Ramp vector dimensions must match')
        end
        for _, name in ipairs({ 'incoming', 'outgoing' }) do
            local handle = point[name]
            if handle then
                assert(
                    finite(handle[1]) and finite(handle[2]) and handle[1] >= 0 and handle[1] <= 1,
                    'Bezier handle is {absoluteTime, normalizedValue}; time must be 0..1'
                )
            end
        end
    end
    for i = 1, #points - 1 do
        local a, b = points[i], points[i + 1]
        local outgoing, incoming = Sequence.handleTimes(a, b)
        assert(
            outgoing >= a.time and incoming <= b.time and outgoing <= incoming,
            'Bezier time handles must be monotone within their segment (including default handles)'
        )
    end
    return points
end

local function bezier(a, b, c, d, t)
    local s = 1 - t
    return s * s * s * a + 3 * s * s * t * b + 3 * s * t * t * c + t * t * t * d
end

function Sequence.evaluate(points, time, interpolation, out)
    interpolation = points.interpolation or interpolation or 'Linear'
    local first, last = points[1], points[#points]
    local a, b = first, first
    if time >= last.time then
        a, b = last, last
    elseif time > first.time then
        local low, high = 1, #points
        while high - low > 1 do
            local mid = math.floor((low + high) / 2)
            if points[mid].time <= time then
                low = mid
            else
                high = mid
            end
        end
        a, b = points[low], points[high]
    end
    local t = a == b and 0 or (time - a.time) / (b.time - a.time)
    if interpolation == 'Curve' and a ~= b then
        local h1 = a.outgoing or { a.time + (b.time - a.time) / 3, 1 / 3 }
        local h2 = b.incoming or { b.time - (b.time - a.time) / 3, 2 / 3 }
        assert(
            h1[1] >= a.time and h2[1] <= b.time and h1[1] <= h2[1],
            'Bezier time handles must be monotone within their segment'
        )
        local low, high = 0, 1
        for _ = 1, 18 do
            local mid = (low + high) / 2
            if bezier(a.time, h1[1], h2[1], b.time, mid) < time then
                low = mid
            else
                high = mid
            end
        end
        t = bezier(0, h1[2], h2[2], 1, (low + high) / 2)
    end
    if type(a.value) == 'number' then
        return a.value + (b.value - a.value) * t
    end
    out = out or {}
    for i = 1, #a.value do
        out[i] = a.value[i] + (b.value[i] - a.value[i]) * t
    end
    return out
end

function Sequence.linear(a, b)
    return { { time = 0, value = a }, { time = 1, value = b } }
end

return Sequence
