-- katsa.math: seeded random generators and polygon triangulation.
-- The generator is xorshift128+ seeded through SplitMix64, as in LÖVE; exact sequences differ.
local ffi = require('ffi')

local KMath = {}

local Generator = {}
Generator.__index = Generator

-- LuaJIT's bit library operates on uint64_t cdata, which gives exact 64-bit arithmetic.
local bxor, lshift, rshift = bit.bxor, bit.lshift, bit.rshift
local u64 = ffi.typeof('uint64_t')

local function splitmix(state)
    state.z = state.z + 0x9E3779B97F4A7C15ULL
    local z = state.z
    z = bxor(z, rshift(z, 30)) * 0xBF58476D1CE4E5B9ULL
    z = bxor(z, rshift(z, 27)) * 0x94D049BB133111EBULL
    return bxor(z, rshift(z, 31))
end

local function seedState(seed)
    local state = { z = u64(seed) }
    local a, b = splitmix(state), splitmix(state)
    if a == 0ULL and b == 0ULL then
        b = 1ULL
    end
    return a, b
end

-- xorshift128+ step returning a uint64.
local function step(self)
    local s1, s0 = self.s0, self.s1
    self.s0 = s0
    s1 = bxor(s1, lshift(s1, 23))
    s1 = bxor(bxor(s1, s0), bxor(rshift(s1, 18), rshift(s0, 5)))
    self.s1 = s1
    return s1 + s0
end

function Generator:setSeed(low, high)
    local seed = u64(low or 0)
    if high then
        seed = seed + u64(high) * 4294967296ULL
    end
    self.seed = seed
    self.s0, self.s1 = seedState(seed)
    self.spare = nil
end

function Generator:getSeed()
    return tonumber(self.seed % 4294967296ULL), tonumber(self.seed / 4294967296ULL)
end

-- Uniform number in [0, 1).
local function unit(self)
    return tonumber(rshift(step(self), 11)) / 9007199254740992
end

function Generator:random(a, b)
    if a == nil then
        return unit(self)
    end
    if b == nil then
        assert(a >= 1, 'random(m): upper bound must be at least 1')
        return math.floor(unit(self) * a) + 1
    end
    assert(a <= b, 'random(m, n): interval is empty')
    return math.floor(unit(self) * (b - a + 1)) + a
end

function Generator:randomNormal(stddev, mean)
    stddev, mean = stddev or 1, mean or 0
    if self.spare then
        local value = self.spare
        self.spare = nil
        return value * stddev + mean
    end
    local u1 = 1 - unit(self)
    local u2 = unit(self)
    local radius = math.sqrt(-2 * math.log(u1))
    self.spare = radius * math.sin(2 * math.pi * u2)
    return radius * math.cos(2 * math.pi * u2) * stddev + mean
end

function Generator:getState()
    return ('%016x%016x'):format(self.s0, self.s1):gsub('ULL', '')
end

function Generator:setState(text)
    local half = ('%x'):rep(16)
    local a, b = text:match('^(' .. half .. ')(' .. half .. ')$')
    assert(a, 'Invalid random generator state')
    self.s0 = ffi.cast('uint64_t',
        tonumber('0x' .. a:sub(1, 8))) * 4294967296ULL + tonumber('0x' .. a:sub(9))
    self.s1 = ffi.cast('uint64_t',
        tonumber('0x' .. b:sub(1, 8))) * 4294967296ULL + tonumber('0x' .. b:sub(9))
end

function KMath.newRandomGenerator(low, high)
    local self = setmetatable({}, Generator)
    self:setSeed(low or 0, high)
    return self
end

local shared = KMath.newRandomGenerator(os.time())

function KMath.setRandomSeed(low, high)
    shared:setSeed(low, high)
end

function KMath.getRandomSeed()
    return shared:getSeed()
end

function KMath.random(a, b)
    return shared:random(a, b)
end

function KMath.randomNormal(stddev, mean)
    return shared:randomNormal(stddev, mean)
end

-- Ear-clipping triangulation of a simple polygon given as x1, y1, x2, y2, ... or a flat table.
function KMath.triangulate(...)
    local points = ...
    if type(points) ~= 'table' then
        points = { ... }
    end
    assert(#points >= 6 and #points % 2 == 0, 'triangulate needs at least three vertices')
    local n = #points / 2
    local function x(i)
        return points[i * 2 - 1]
    end
    local function y(i)
        return points[i * 2]
    end
    local area = 0
    for i = 1, n do
        local j = i % n + 1
        area = area + x(i) * y(j) - x(j) * y(i)
    end
    local order = {}
    for i = 1, n do
        order[i] = area > 0 and i or n - i + 1
    end
    local function cross(a, b, c)
        return (x(b) - x(a)) * (y(c) - y(b)) - (y(b) - y(a)) * (x(c) - x(b))
    end
    local function inside(p, a, b, c)
        local d1, d2, d3 = cross(a, b, p), cross(b, c, p), cross(c, a, p)
        return d1 >= 0 and d2 >= 0 and d3 >= 0
    end
    local triangles = {}
    local guard = 0
    while #order > 3 do
        guard = guard + 1
        assert(guard <= n * n + 4, 'Cannot triangulate polygon (self-intersecting or degenerate)')
        local clipped = false
        for i = 1, #order do
            local a, b, c = order[(i - 2) % #order + 1], order[i], order[i % #order + 1]
            if cross(a, b, c) > 0 then
                local blocked = false
                for _, p in ipairs(order) do
                    if p ~= a and p ~= b and p ~= c and inside(p, a, b, c) then
                        blocked = true
                        break
                    end
                end
                if not blocked then
                    triangles[#triangles + 1] = { x(a), y(a), x(b), y(b), x(c), y(c) }
                    table.remove(order, i)
                    clipped = true
                    break
                end
            end
        end
        if not clipped then
            error('Cannot triangulate polygon (self-intersecting or degenerate)')
        end
    end
    local a, b, c = order[1], order[2], order[3]
    triangles[#triangles + 1] = { x(a), y(a), x(b), y(b), x(c), y(c) }
    return triangles
end

return KMath
