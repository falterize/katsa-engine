-- Chunk meshing (runs in a worker): emits only the faces a player can see, i.e. faces whose
-- neighbouring block is air or see-through. Hidden faces between two solid blocks never exist.
local ffi = require('ffi')
local Blocks = require('blocks')

local CHUNK, HEIGHT = Blocks.CHUNK, Blocks.HEIGHT
local LAYER = CHUNK * CHUNK
local SIZE = CHUNK * CHUNK * HEIGHT
local TILES, INSET = 4, 0.0008

-- Corners per face: x, y, z offsets in the block and u, v in the tile (0..1). They are reordered
-- below so the first triangle's winding matches the face normal.
local FACES = {
    { dx = 1, dy = 0, dz = 0, tile = 'side', c = { { 1, 0, 0, 1, 1 }, { 1, 1, 0, 1, 0 }, { 1, 1, 1, 0, 0 }, { 1, 0, 1, 0, 1 } } },
    { dx = -1, dy = 0, dz = 0, tile = 'side', c = { { 0, 0, 0, 0, 1 }, { 0, 1, 0, 0, 0 }, { 0, 1, 1, 1, 0 }, { 0, 0, 1, 1, 1 } } },
    { dx = 0, dy = 1, dz = 0, tile = 'top', c = { { 0, 1, 0, 0, 0 }, { 0, 1, 1, 0, 1 }, { 1, 1, 1, 1, 1 }, { 1, 1, 0, 1, 0 } } },
    { dx = 0, dy = -1, dz = 0, tile = 'bottom', c = { { 0, 0, 0, 0, 0 }, { 1, 0, 0, 1, 0 }, { 1, 0, 1, 1, 1 }, { 0, 0, 1, 0, 1 } } },
    { dx = 0, dy = 0, dz = 1, tile = 'side', c = { { 0, 0, 1, 0, 1 }, { 1, 0, 1, 1, 1 }, { 1, 1, 1, 1, 0 }, { 0, 1, 1, 0, 0 } } },
    { dx = 0, dy = 0, dz = -1, tile = 'side', c = { { 0, 0, 0, 1, 1 }, { 0, 1, 0, 1, 0 }, { 1, 1, 0, 0, 0 }, { 1, 0, 0, 0, 1 } } },
}

for _, face in ipairs(FACES) do
    local a, b, c = face.c[1], face.c[2], face.c[3]
    local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    if nx * face.dx + ny * face.dy + nz * face.dz < 0 then
        face.c = { face.c[4], face.c[3], face.c[2], face.c[1] }
    end
end

local Mesher = {}

local function toBlocks(data)
    return ffi.cast('const uint8_t*', data)
end

-- `data` and the neighbour strings are block arrays; a missing neighbour counts as solid.
-- Returns a flat array of vertices (8 numbers each: x y z u v nx ny nz, 6 vertices per face),
-- positions relative to the chunk centre, and the face count.
function Mesher.build(data, neighbours)
    assert(#data == SIZE, 'Chunk data has the wrong size')
    local blocks = toBlocks(data)
    local side = {
        [1] = neighbours.px and toBlocks(neighbours.px),
        [-1] = neighbours.nx and toBlocks(neighbours.nx),
        [2] = neighbours.pz and toBlocks(neighbours.pz),
        [-2] = neighbours.nz and toBlocks(neighbours.nz),
    }
    local list = Blocks.list
    local out, n, faces = {}, 0, 0
    local half, mid = CHUNK / 2, HEIGHT / 2

    local function neighbour(x, y, z, face)
        if y < 0 then
            return 1
        elseif y >= HEIGHT then
            return 0
        end
        if x >= 0 and x < CHUNK and z >= 0 and z < CHUNK then
            return blocks[x + z * CHUNK + y * LAYER]
        end
        local other
        if x < 0 then
            other, x = side[-1], x + CHUNK
        elseif x >= CHUNK then
            other, x = side[1], x - CHUNK
        elseif z < 0 then
            other, z = side[-2], z + CHUNK
        else
            other, z = side[2], z - CHUNK
        end
        return other and other[x + z * CHUNK + y * LAYER] or 1
    end

    for y = 0, HEIGHT - 1 do
        for z = 0, CHUNK - 1 do
            for x = 0, CHUNK - 1 do
                local id = blocks[x + z * CHUNK + y * LAYER]
                if id ~= 0 then
                    local def = list[id]
                    for f = 1, 6 do
                        local face = FACES[f]
                        local other = neighbour(x + face.dx, y + face.dy, z + face.dz)
                        local hidden
                        if other == 0 then
                            hidden = false
                        elseif other == id then
                            hidden = true
                        else
                            hidden = not (list[other] and list[other].transparent)
                        end
                        if not hidden then
                            faces = faces + 1
                            local tile = def[face.tile]
                            local u0, v0 = (tile % TILES) / TILES, math.floor(tile / TILES) / TILES
                            local span = 1 / TILES
                            local c = face.c
                            for _, k in ipairs({ 1, 2, 3, 1, 3, 4 }) do
                                local p = c[k]
                                out[n + 1] = x + p[1] - half
                                out[n + 2] = y + p[2] - mid
                                out[n + 3] = z + p[3] - half
                                out[n + 4] = u0 + (p[4] * (1 - 2 * INSET) + INSET) * span
                                out[n + 5] = v0 + (p[5] * (1 - 2 * INSET) + INSET) * span
                                out[n + 6], out[n + 7], out[n + 8] = face.dx, face.dy, face.dz
                                n = n + 8
                            end
                        end
                    end
                end
            end
        end
    end
    return out, faces
end

return Mesher
