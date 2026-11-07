-- Axis maths of the curve editor, free of any drawing or input: the value range, grid steps and
-- the pixel size a graph needs so wide ranges scroll instead of being squeezed.
local ipairs = require('../../math.array').ipairs

local Axes = {}

Axes.UNITS_PER_VIEW = 40 -- value units one viewport height shows before the graph scrolls
Axes.MAX_VIEWS = 8
Axes.PIXELS_PER_SECOND = 120 -- horizontal density of a time axis in seconds
Axes.PADDING = 14 -- clear space left and right of the plot, so end points sit off the edge

-- Value range of a track on one channel. It always contains 0..1 and every point, with a little
-- padding once the values leave 0..1.
function Axes.valueRange(points, valueOf)
    local low, high = 0, 1
    for _, point in ipairs(points) do
        local v = valueOf(point)
        low, high = math.min(low, v), math.max(high, v)
    end
    local pad = (high - low > 1) and (high - low) * 0.05 or 0
    low, high = low - pad, high + pad
    return low, math.max(low + 0.001, high)
end

-- Graph height for a viewport of `view` pixels: 0..1 fits it, wider ranges grow taller.
function Axes.height(view, low, high)
    return view * math.max(1, math.min(Axes.MAX_VIEWS, (high - low) / Axes.UNITS_PER_VIEW))
end

-- Graph width for a viewport of `view` pixels. A time axis in seconds keeps a constant density
-- and leaves a quarter viewport of empty time after the last point, so it can be dragged later.
-- `seconds` is nil on the fixed 0..1 axis, which always fits the viewport.
function Axes.width(view, seconds)
    if not seconds then
        return view, 0
    end
    local margin = view * 0.25
    return math.max(view, seconds * Axes.PIXELS_PER_SECOND + 2 * Axes.PADDING + margin), margin
end

-- A round grid step (1, 2, 5 x 10^n) that gives roughly `count` lines over `extent`.
function Axes.niceStep(extent, count)
    local raw = math.max(extent, 1e-9) / math.max(count, 1)
    local power = 10 ^ math.floor(math.log(raw) / math.log(10))
    local fraction = raw / power
    return (fraction <= 1 and 1 or fraction <= 2 and 2 or fraction <= 5 and 5 or 10) * power
end

return Axes
