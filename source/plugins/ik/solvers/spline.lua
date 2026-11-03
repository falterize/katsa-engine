-- Spline IK: a chain follows a curve, the way a tail, rope, tentacle or a snake body follows a
-- path. The curve is a Catmull-Rom spline through control points given in world space.
--
--   IK.Spline.new({ bones = { 'Tail1', 'Tail2', 'Tail3', 'Tail4' },
--                   points = { nodeA, nodeB, nodeC, { 0, 5, 3 } },   -- nodes, {x, y, z} or a function
--                   offset = 0 })                                    -- slides the chain along the curve
--
-- The first bone stays where it is; bones keep their lengths and turn so each joint lies on the
-- curve at the distance it had along the chain, starting from the curve point nearest the first
-- bone. Beyond the curve end the chain points along the last tangent.
local Modifier = require('../modifier')

local Spline = Modifier.extend()

local SAMPLES = 12

function Spline.new(settings)
    return setmetatable({}, Spline):read(settings)
end

function Spline:read(settings)
    self:configure(settings)
    self.chain = settings.bones
    assert(self.chain and #self.chain >= 2, 'Spline needs a `bones` chain of at least two bones')
    self.points = settings.points
    self.offset = settings.offset or 0
    return self
end

function Spline:bones()
    return self.chain
end

local function catmull(p0, p1, p2, p3, t)
    local t2, t3 = t * t, t * t * t
    local out = {}
    for i = 1, 3 do
        out[i] = 0.5
            * (
                2 * p1[i]
                + (p2[i] - p0[i]) * t
                + (2 * p0[i] - 5 * p1[i] + 4 * p2[i] - p3[i]) * t2
                + (3 * p1[i] - p0[i] - 3 * p2[i] + p3[i]) * t3
            )
    end
    return out
end

-- Polyline approximation with cumulative lengths.
local function sample(points)
    local line, lengths = {}, { 0 }
    local count = #points
    for i = 1, count - 1 do
        local p0, p1, p2, p3 = points[math.max(1, i - 1)], points[i], points[i + 1], points[math.min(count, i + 2)]
        for step = 0, SAMPLES - (i == count - 1 and 0 or 1) do
            line[#line + 1] = catmull(p0, p1, p2, p3, step / SAMPLES)
        end
    end
    for i = 2, #line do
        local a, b = line[i - 1], line[i]
        lengths[i] = lengths[i - 1] + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
    end
    return line, lengths
end

local function pointAt(line, lengths, s)
    local last = #line
    if s <= 0 then
        return line[1][1], line[1][2], line[1][3]
    end
    if s >= lengths[last] then
        -- Continue along the final tangent.
        local a, b = line[last - 1], line[last]
        local d = math.max(lengths[last] - lengths[last - 1], 1e-9)
        local k = (s - lengths[last]) / d
        return b[1] + (b[1] - a[1]) * k, b[2] + (b[2] - a[2]) * k, b[3] + (b[3] - a[3]) * k
    end
    local low, high = 1, last
    while high - low > 1 do
        local mid = math.floor((low + high) / 2)
        if lengths[mid] <= s then
            low = mid
        else
            high = mid
        end
    end
    local k = (s - lengths[low]) / math.max(lengths[high] - lengths[low], 1e-9)
    local a, b = line[low], line[high]
    return a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k
end

-- Arc length of the polyline point nearest to (x, y, z).
local function nearest(line, lengths, x, y, z)
    local best, bestSq = 0, math.huge
    for i = 1, #line - 1 do
        local a, b = line[i], line[i + 1]
        local abx, aby, abz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
        local lenSq = abx * abx + aby * aby + abz * abz
        local t = lenSq > 0 and math.max(0, math.min(1, ((x - a[1]) * abx + (y - a[2]) * aby + (z - a[3]) * abz) / lenSq)) or 0
        local qx, qy, qz = a[1] + abx * t, a[2] + aby * t, a[3] + abz * t
        local dSq = (x - qx) ^ 2 + (y - qy) ^ 2 + (z - qz) ^ 2
        if dSq < bestSq then
            bestSq, best = dSq, lengths[i] + (lengths[i + 1] - lengths[i]) * t
        end
    end
    return best
end

function Spline:solve(skeleton)
    local source = self.points
    if type(source) == 'function' then
        source = source()
    end
    if not source or #source < 2 then
        return
    end
    local points = {}
    for i, value in ipairs(source) do
        local x, y, z = Modifier.point(value)
        local mx, my, mz = skeleton:toModel(x, y, z)
        points[i] = { mx, my, mz }
    end
    local line, lengths = sample(points)
    local rx, ry, rz = skeleton:getPosition(self.chain[1])
    local s = nearest(line, lengths, rx, ry, rz) + self.offset
    local distances = {}
    for i = 1, #self.chain - 1 do
        local ax, ay, az = skeleton:getPosition(self.chain[i])
        local bx, by, bz = skeleton:getPosition(self.chain[i + 1])
        distances[i] = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2 + (bz - az) ^ 2)
    end
    for i = 1, #self.chain - 1 do
        s = s + distances[i]
        local x, y, z = pointAt(line, lengths, s)
        skeleton:aim(self.chain[i], self.chain[i + 1], x, y, z)
    end
end

return Spline
