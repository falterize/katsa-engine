-- A found route: world-space points plus a cursor for agents that follow it.
local Path = {}
Path.__index = Path

local function distance(a, b)
    local dx, dy, dz = a[1] - b[1], a[2] - b[2], (a[3] or 0) - (b[3] or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Path.new(points, cost)
    local self = setmetatable({ points = points, cost = cost or 0, index = 1, length = 0 }, Path)
    for index = 2, #points do
        self.length = self.length + distance(points[index - 1], points[index])
    end
    return self
end

function Path:isFinished()
    return self.index > #self.points
end

-- Advances past every point within `radius` of the agent and returns the next target
-- (x, y[, z]) or nil when the route is complete.
function Path:target(x, y, z, radius)
    radius = radius or 0.5
    local here = { x, y, z }
    while self.index <= #self.points and distance(here, self.points[self.index]) <= radius do
        self.index = self.index + 1
    end
    local point = self.points[self.index]
    if point then
        return point[1], point[2], point[3]
    end
end

-- Unit direction from the agent to its next target, or 0, 0 (and 0 for z) when finished.
function Path:direction(x, y, z, radius)
    local tx, ty, tz = self:target(x, y, z, radius)
    if not tx then
        return 0, 0, 0
    end
    local dx, dy, dz = tx - x, ty - y, (tz or 0) - (z or 0)
    local length = math.sqrt(dx * dx + dy * dy + dz * dz)
    if length == 0 then
        return 0, 0, 0
    end
    return dx / length, dy / length, dz / length
end

function Path:reset()
    self.index = 1
end

return Path
