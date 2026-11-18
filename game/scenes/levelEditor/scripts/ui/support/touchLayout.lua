-- Geometry of the on-screen touch controls, pure Lua. A control is { x, y, size }: the centre as a
-- fraction of the viewport (so it follows the dock sizes) and a diameter in UI units. Sticks and
-- buttons are circles. Positions are always kept fully inside the viewport.
local Layout = {}

Layout.MIN_SIZE, Layout.MAX_SIZE = 40, 220

-- name -> kind; the order is the draw order and the reverse of the hit order.
Layout.NAMES = { 'moveStick', 'lookStick', 'up', 'down', 'fast' }
Layout.KIND = { moveStick = 'stick', lookStick = 'stick', up = 'button', down = 'button', fast = 'button' }
Layout.LABEL = { moveStick = 'Move', lookStick = 'Look', up = 'Up', down = 'Down', fast = 'Fast' }

function Layout.defaults()
    return {
        moveStick = { x = 0.13, y = 0.74, size = 120 },
        lookStick = { x = 0.87, y = 0.74, size = 120 },
        up = { x = 0.88, y = 0.40, size = 56 },
        down = { x = 0.88, y = 0.52, size = 56 },
        fast = { x = 0.13, y = 0.46, size = 56 },
    }
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

-- A complete controls table: unknown names are dropped, missing or invalid values fall back to the
-- defaults, sizes and fractions are clamped.
function Layout.merge(data)
    local result = Layout.defaults()
    if type(data) == 'table' then
        for name, control in pairs(result) do
            local given = data[name]
            if type(given) == 'table' then
                for _, key in ipairs({ 'x', 'y', 'size' }) do
                    local value = given[key]
                    if type(value) == 'number' and value == value and math.abs(value) < math.huge then
                        control[key] = value
                    end
                end
            end
            control.x, control.y = clamp(control.x, 0, 1), clamp(control.y, 0, 1)
            control.size = clamp(control.size, Layout.MIN_SIZE, Layout.MAX_SIZE)
        end
    end
    return result
end

-- Centre (pixels) and radius of a control in a viewport `width` x `height`, kept inside it.
function Layout.circle(control, width, height)
    local radius = math.min(control.size / 2, width / 2, height / 2)
    local cx = clamp(control.x * width, radius, math.max(radius, width - radius))
    local cy = clamp(control.y * height, radius, math.max(radius, height - radius))
    return cx, cy, radius
end

-- The topmost control under (px, py) (viewport pixels), or nil.
function Layout.hit(controls, width, height, px, py)
    for index = #Layout.NAMES, 1, -1 do
        local name = Layout.NAMES[index]
        local cx, cy, radius = Layout.circle(controls[name], width, height)
        if (px - cx) ^ 2 + (py - cy) ^ 2 <= radius ^ 2 then
            return name
        end
    end
    return nil
end

-- Stick deflection of a finger at (px, py): x right, y up, length limited to 1, with a small
-- dead zone in the middle.
function Layout.axes(control, width, height, px, py)
    local cx, cy, radius = Layout.circle(control, width, height)
    local ax, ay = (px - cx) / radius, (cy - py) / radius
    local length = math.sqrt(ax * ax + ay * ay)
    if length < 0.1 then
        return 0, 0
    end
    if length > 1 then
        ax, ay = ax / length, ay / length
    end
    return ax, ay
end

-- Moves a control so its centre is at (px, py), kept inside the viewport.
function Layout.moveTo(control, width, height, px, py)
    local _, _, radius = Layout.circle(control, width, height)
    control.x = clamp(px, radius, math.max(radius, width - radius)) / width
    control.y = clamp(py, radius, math.max(radius, height - radius)) / height
end

function Layout.resize(control, delta)
    control.size = clamp(control.size + delta, Layout.MIN_SIZE, Layout.MAX_SIZE)
end

return Layout
