-- Chunk meshing (runs in a worker). Three things keep the mesh small and pretty:
--   * only faces next to air or a see-through block exist (hidden faces are never built);
--   * greedy meshing merges neighbouring faces of one block type into a single rectangle;
--   * every face corner carries ambient occlusion (darker creases), computed from the blocks
--     around it. A rectangle is merged only where all four corner values are equal, so the
--     shading of uneven spots stays exact.
-- The mesh is split into 16-high sections so the renderer can cull them separately.
-- Vertex layout: x y z u v nx ny nz. The normal's direction is the face direction and its LENGTH
-- is the occlusion shade; the tile index and the repeat count are packed into u and v (see
-- assets/shaders/voxel.glsl, which unpacks both).
local ffi = require('ffi')
local Blocks = require('blocks')

local CHUNK, HEIGHT = Blocks.CHUNK, Blocks.HEIGHT
local SIZE = CHUNK * CHUNK * HEIGHT
local PAD = CHUNK + 2 -- one block of border on every horizontal side
local PADDED = PAD * PAD * (HEIGHT + 2)
local SECTION = 16
local STRIDE = { x = 1, z = PAD, y = PAD * PAD }
local SHADE = { [0] = 0.5, 0.68, 0.84, 1.0 }
local LOCAL_SIZE = { x = CHUNK, y = HEIGHT, z = CHUNK }

-- Per face: the slice axis a, the two mask axes A (columns) and B (rows), the outward sign, and
-- whether the texture runs against A / B so the picture stays upright.
local FACES = {
    { a = 'x', A = 'z', B = 'y', sign = 1, flipU = true, flipV = true },
    { a = 'x', A = 'z', B = 'y', sign = -1, flipU = false, flipV = true },
    { a = 'y', A = 'x', B = 'z', sign = 1, flipU = false, flipV = false },
    { a = 'y', A = 'x', B = 'z', sign = -1, flipU = false, flipV = false },
    { a = 'z', A = 'x', B = 'y', sign = 1, flipU = false, flipV = true },
    { a = 'z', A = 'x', B = 'y', sign = -1, flipU = true, flipV = true },
}

local CORNERS = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } }

local function point(face, slice, a, b)
    local p = { x = 0, y = 0, z = 0 }
    p[face.a], p[face.A], p[face.B] = slice, a, b
    return p
end

-- Orders the four corners so the first triangle winds like the outward normal.
for _, face in ipairs(FACES) do
    local function at(c)
        return point(face, 0, c[1], c[2])
    end
    local p1, p2, p3 = at(CORNERS[1]), at(CORNERS[2]), at(CORNERS[3])
    local ux, uy, uz = p2.x - p1.x, p2.y - p1.y, p2.z - p1.z
    local vx, vy, vz = p3.x - p1.x, p3.y - p1.y, p3.z - p1.z
    local n = { x = uy * vz - uz * vy, y = uz * vx - ux * vz, z = ux * vy - uy * vx }
    face.order = CORNERS
    if n[face.a] * face.sign < 0 then
        face.order = { CORNERS[4], CORNERS[3], CORNERS[2], CORNERS[1] }
    end
end

local Mesher = {}

-- Border-padded copies of the chunk: block ids and an "opaque" flag for occlusion.
local function pad(data, neighbours)
    local ids = ffi.new('uint8_t[?]', PADDED)
    local opaque = ffi.new('uint8_t[?]', PADDED)
    local list = Blocks.list
    local own = ffi.cast('const uint8_t*', data)
    local sides = {
        px = neighbours.px and ffi.cast('const uint8_t*', neighbours.px),
        nx = neighbours.nx and ffi.cast('const uint8_t*', neighbours.nx),
        pz = neighbours.pz and ffi.cast('const uint8_t*', neighbours.pz),
        nz = neighbours.nz and ffi.cast('const uint8_t*', neighbours.nz),
    }
    local function put(px, py, pz, id)
        local at = px + pz * PAD + py * PAD * PAD
        ids[at] = id
        opaque[at] = (id ~= 0 and not (list[id] and list[id].transparent)) and 1 or 0
    end
    for y = 0, HEIGHT - 1 do
        for z = -1, CHUNK do
            for x = -1, CHUNK do
                local id
                if x >= 0 and x < CHUNK and z >= 0 and z < CHUNK then
                    id = own[x + z * CHUNK + y * CHUNK * CHUNK]
                elseif (x < 0 or x >= CHUNK) and (z < 0 or z >= CHUNK) then
                    id = 0 -- diagonal neighbours are not sent: treated as air for occlusion
                elseif x < 0 then
                    id = sides.nx and sides.nx[CHUNK - 1 + z * CHUNK + y * CHUNK * CHUNK] or 1
                elseif x >= CHUNK then
                    id = sides.px and sides.px[z * CHUNK + y * CHUNK * CHUNK] or 1
                elseif z < 0 then
                    id = sides.nz and sides.nz[x + (CHUNK - 1) * CHUNK + y * CHUNK * CHUNK] or 1
                else
                    id = sides.pz and sides.pz[x + y * CHUNK * CHUNK] or 1
                end
                put(x + 1, y + 1, z + 1, id)
            end
        end
    end
    -- Below the world is solid (no bottom faces), above it is open sky.
    for z = 0, PAD - 1 do
        for x = 0, PAD - 1 do
            put(x, 0, z, 1)
        end
    end
    return ids, opaque
end

local function sectionBuffer(sections, index)
    local section = sections[index]
    if not section then
        section = { sy = index, vertices = {}, n = 0, faces = 0 }
        sections[index] = section
    end
    return section
end

local function emit(sections, face, slice, a0, b0, w, h, tile, ao)
    local sy
    if face.a == 'y' then
        sy = math.floor(slice / SECTION)
    else
        sy = math.floor(b0 / SECTION)
    end
    local section = sectionBuffer(sections, sy)
    local out, n = section.vertices, section.n
    local plane = slice + (face.sign > 0 and 1 or 0)
    local tx, ty = tile % 4, math.floor(tile / 4)
    local normal = { x = 0, y = 0, z = 0 }
    normal[face.a] = face.sign
    local corner = {}
    for k = 1, 4 do
        local c = face.order[k]
        local oA, oB = c[1], c[2]
        local p = point(face, plane, a0 + oA * w, b0 + oB * h)
        local shade = SHADE[ao[oA + 2 * oB + 1]]
        local lu = (face.flipU and (1 - oA) or oA) * w
        local lv = (face.flipV and (1 - oB) or oB) * h
        corner[k] = {
            p.x - CHUNK / 2,
            p.y - sy * SECTION - SECTION / 2,
            p.z - CHUNK / 2,
            tx * 32 + 8 + lu,
            ty * 32 + 8 + lv,
            normal.x * shade,
            normal.y * shade,
            normal.z * shade,
            ao = ao[oA + 2 * oB + 1],
        }
    end
    -- Split along the diagonal with the smaller brightness difference (no stripes).
    local order
    if corner[1].ao + corner[3].ao > corner[2].ao + corner[4].ao then
        order = { 2, 3, 4, 2, 4, 1 }
    else
        order = { 1, 2, 3, 1, 3, 4 }
    end
    for _, k in ipairs(order) do
        local v = corner[k]
        for j = 1, 8 do
            out[n + j] = v[j]
        end
        n = n + 8
    end
    section.n, section.faces = n, section.faces + 1
end

-- `data` and the neighbour strings are block arrays (px, nx, pz, nz). Returns the list of
-- sections { sy, vertices (flat numbers), faces } and the total face count.
function Mesher.build(data, neighbours)
    assert(#data == SIZE, 'Chunk data has the wrong size')
    local ids, opaque = pad(data, neighbours)
    local list = Blocks.list
    local transparent = {}
    for id, def in ipairs(list) do
        transparent[id] = def.transparent or false
    end
    local sections = {}
    local total = 0

    for _, face in ipairs(FACES) do
        local sa, sA, sB = LOCAL_SIZE[face.a], LOCAL_SIZE[face.A], LOCAL_SIZE[face.B]
        local stepSlice, stepA, stepB = STRIDE[face.a], STRIDE[face.A], STRIDE[face.B]
        local outward = stepSlice * face.sign
        local mask = {}
        for slice = 0, sa - 1 do
            for b = 0, sB - 1 do
                for a = 0, sA - 1 do
                    local cell = (slice + 1) * stepSlice + (a + 1) * stepA + (b + 1) * stepB
                    local id = ids[cell]
                    local key = 0
                    if id ~= 0 then
                        local other = ids[cell + outward]
                        local visible
                        if other == 0 then
                            visible = true
                        elseif other == id then
                            visible = false
                        else
                            visible = transparent[other] or false
                        end
                        if visible then
                            local def = list[id]
                            local tile = face.a == 'y' and (face.sign > 0 and def.top or def.bottom)
                                or def.side
                            -- Occlusion of the four corners (0 darkest .. 3 open).
                            local front = cell + outward
                            local ao, flat = {}, true
                            for index = 0, 3 do
                                local dA = (index % 2 == 1) and 1 or -1
                                local dB = (index >= 2) and 1 or -1
                                local s1 = opaque[front + dA * stepA]
                                local s2 = opaque[front + dB * stepB]
                                local c = opaque[front + dA * stepA + dB * stepB]
                                local value = (s1 == 1 and s2 == 1) and 0 or 3 - (s1 + s2 + c)
                                ao[index + 1] = value
                                if value ~= ao[1] then
                                    flat = false
                                end
                            end
                            if flat then
                                key = 1 + tile * 4 + ao[1]
                            else
                                key = 100000
                                    + tile
                                    + 16 * (ao[1] + 4 * ao[2] + 16 * ao[3] + 64 * ao[4])
                            end
                        end
                    end
                    mask[a + b * sA] = key
                end
            end
            -- Greedy rectangles over the slice mask (uneven-shade cells stay single).
            for b = 0, sB - 1 do
                for a = 0, sA - 1 do
                    local key = mask[a + b * sA]
                    if key ~= 0 then
                        local w, h = 1, 1
                        if key < 100000 then
                            while a + w < sA and mask[a + w + b * sA] == key do
                                w = w + 1
                            end
                            local growing = true
                            while growing and b + h < sB do
                                if face.B == 'y' and (b + h) % SECTION == 0 then
                                    break -- never cross a section boundary
                                end
                                for k = 0, w - 1 do
                                    if mask[a + k + (b + h) * sA] ~= key then
                                        growing = false
                                        break
                                    end
                                end
                                if growing then
                                    h = h + 1
                                end
                            end
                        end
                        for r = 0, h - 1 do
                            for k = 0, w - 1 do
                                mask[a + k + (b + r) * sA] = 0
                            end
                        end
                        local tile, ao
                        if key < 100000 then
                            tile, ao = math.floor((key - 1) / 4), {}
                            for i = 1, 4 do
                                ao[i] = (key - 1) % 4
                            end
                        else
                            local packed = key - 100000
                            tile = packed % 16
                            local code = math.floor(packed / 16)
                            ao = { code % 4, math.floor(code / 4) % 4, math.floor(code / 16) % 4, math.floor(code / 64) % 4 }
                        end
                        emit(sections, face, slice, a, b, w, h, tile, ao)
                        total = total + 1
                    end
                end
            end
        end
    end
    local result = {}
    for _, section in pairs(sections) do
        result[#result + 1] = { sy = section.sy, vertices = section.vertices, faces = section.faces }
    end
    return result, total
end

return Mesher
