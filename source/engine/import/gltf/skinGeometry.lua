local unpack = require('../../math.array').unpack
local ipairs = require('../../math.array').ipairs
local Geometry = require('../../graphics.geometry.primitives')

local Skin = { maxPalette = 32 }

function Skin.build(vertices, resources, requestedLimit)
    local influences = vertices[1] and #vertices[1] == 24 and 8 or 4
    local limit = requestedLimit or Skin.maxPalette
    -- A triangle is indivisible. Retain all its joints instead of silently dropping weights.
    if limit < Skin.maxPalette then
        for i = 1, #vertices, 3 do
            local seen, count = {}, 0
            for k = i, i + 2 do
                for j = 1, influences do
                    local offset = j > 4 and 4 or 0
                    local vertex = vertices[k]
                    local joint = vertex[8 + j + offset]
                    if vertex[12 + j + offset] > 0 and not seen[joint] then
                        seen[joint], count = true, count + 1
                    end
                end
            end
            limit = math.max(limit, count)
        end
    end
    assert(limit <= Skin.maxPalette, 'Triangle exceeds the GPU bone palette capacity')
    local batches = {}
    local current, palette, lookup

    local function reset()
        current, palette, lookup = {}, {}, {}
    end

    local function flush()
        if #current == 0 then
            return
        end
        local geometry = Geometry.mesh(Geometry.normals(current), true)
        resources:own(geometry.mesh)
        batches[#batches + 1] = { geometry = geometry, palette = palette }
    end
    reset()
    for i = 1, #vertices, 3 do
        local needed, seen = {}, {}
        for k = i, i + 2 do
            local v = vertices[k]
            for j = 1, influences do
                local offset = j > 4 and 4 or 0
                local joint = v[8 + j + offset]
                if v[12 + j + offset] > 0 and not lookup[joint] and not seen[joint] then
                    needed[#needed + 1] = joint
                    seen[joint] = true
                end
            end
        end
        if #palette + #needed > limit then
            flush()
            reset()
            needed = {}
            seen = {}
            for k = i, i + 2 do
                for j = 1, influences do
                    local v = vertices[k]
                    local offset = j > 4 and 4 or 0
                    local joint = v[8 + j + offset]
                    if v[12 + j + offset] > 0 and not seen[joint] then
                        needed[#needed + 1] = joint
                        seen[joint] = true
                    end
                end
            end
        end
        for _, joint in ipairs(needed) do
            palette[#palette + 1] = joint
            lookup[joint] = #palette - 1
        end
        for k = i, i + 2 do
            local v = { unpack(vertices[k]) }
            for j = 1, influences do
                local index = 8 + j + (j > 4 and 4 or 0)
                v[index] = lookup[v[index]] or 0
            end
            current[#current + 1] = v
        end
    end
    flush()
    return batches, limit
end

return Skin
