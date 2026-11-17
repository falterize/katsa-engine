-- Terrain generation of one chunk (runs in a worker). Deterministic from the seed and the chunk
-- coordinates; trees stay clear of the chunk border so a chunk never writes into a neighbour.
local ffi = require('ffi')
local bit = require('bit')
local Blocks = require('blocks')

local CHUNK, HEIGHT = Blocks.CHUNK, Blocks.HEIGHT
local SEA = 22

local Terrain = {}

local function hash(x, z, seed)
    local h = bit.bxor(x * 374761393, z * 668265263, seed * 1442695041)
    h = bit.bxor(h, bit.rshift(h, 13)) * 1274126177
    h = bit.bxor(h, bit.rshift(h, 16))
    return bit.band(h, 0xFFFFFF) / 0xFFFFFF
end

local function smooth(t)
    return t * t * (3 - 2 * t)
end

local function valueNoise(x, z, seed)
    local ix, iz = math.floor(x), math.floor(z)
    local fx, fz = smooth(x - ix), smooth(z - iz)
    local a, b = hash(ix, iz, seed), hash(ix + 1, iz, seed)
    local c, d = hash(ix, iz + 1, seed), hash(ix + 1, iz + 1, seed)
    return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fz
end

-- Terrain height of a world column.
function Terrain.height(x, z, seed)
    local hills = valueNoise(x / 64, z / 64, seed) * 0.6
        + valueNoise(x / 24, z / 24, seed + 1) * 0.3
        + valueNoise(x / 9, z / 9, seed + 2) * 0.1
    return math.floor(12 + hills * 40)
end

local function index(x, y, z)
    return x + z * CHUNK + y * CHUNK * CHUNK
end

local function tree(blocks, x, y, z)
    local trunk = 4 + (x + z) % 2
    for dy = 1, trunk do
        blocks[index(x, y + dy, z)] = Blocks.LOG
    end
    for dy = trunk - 1, trunk + 2 do
        local radius = dy >= trunk + 1 and 1 or 2
        for dx = -radius, radius do
            for dz = -radius, radius do
                local at = index(x + dx, y + dy, z + dz)
                if
                    blocks[at] == 0
                    and (math.abs(dx) + math.abs(dz) < radius * 2 or dy == trunk)
                then
                    blocks[at] = Blocks.LEAVES
                end
            end
        end
    end
end

-- Returns a Lua string of CHUNK*CHUNK*HEIGHT block ids (index = x + z*16 + y*256).
function Terrain.generate(cx, cz, seed)
    local blocks = ffi.new('uint8_t[?]', CHUNK * CHUNK * HEIGHT)
    for z = 0, CHUNK - 1 do
        for x = 0, CHUNK - 1 do
            local wx, wz = cx * CHUNK + x, cz * CHUNK + z
            local h = math.min(HEIGHT - 12, Terrain.height(wx, wz, seed))
            local top, under = Blocks.GRASS, Blocks.DIRT
            if h <= SEA + 1 then
                top, under = Blocks.SAND, Blocks.SANDSTONE
            elseif h >= 42 then
                top, under = Blocks.SNOW, Blocks.STONE
            end
            for y = 0, h do
                local id = Blocks.STONE
                if y == h then
                    id = top
                elseif y >= h - 3 then
                    id = under
                elseif y > 2 and hash(wx * 31 + y, wz, seed + 9) < 0.012 then
                    id = Blocks.COAL
                end
                blocks[index(x, y, z)] = id
            end
            if
                top == Blocks.GRASS
                and x >= 3 and x <= CHUNK - 4 and z >= 3 and z <= CHUNK - 4
                and hash(wx, wz, seed + 5) < 0.012
            then
                tree(blocks, x, h, z)
            end
        end
    end
    return ffi.string(blocks, CHUNK * CHUNK * HEIGHT)
end

return Terrain
