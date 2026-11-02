local unpack = require('../../math.array').unpack
local ipairs = require('../../math.array').ipairs
local M = require('../../math.math3d')
local A = require('../../math.affine')

local S = {}

function S.initialize(object)
    local skin = object.skin
    if object.geometry._skinEnvelopes then
        skin.envelopes = object.geometry._skinEnvelopes
        S.update(object)
        return
    end
    skin.envelopes = {}
    local vertices = object.geometry.vertices
    for _, v in ipairs(vertices) do
        for i = 1, object.geometry.eightWeights and 8 or 4 do
            local offset = i > 4 and 4 or 0
            if v[12 + i + offset] > 0 then
                local joint = skin.palette[v[8 + i + offset] + 1] + 1
                assert(skin.definition.joints[joint], 'Vertex joint index exceeds skin skeleton')
                local x, y, z =
                    M.transform(skin.definition.inverseBindMatrices[joint], v[1], v[2], v[3])
                skin.envelopes[joint] =
                    math.max(skin.envelopes[joint] or 0, math.sqrt(x * x + y * y + z * z))
            end
        end
    end
    S.update(object)
end

local function fullUpdate(object)
    local skin = object.skin
    local definition = skin.definition
    skin.inverse = A.inverse(skin.node.world, skin.inverse)
    local radius = 0
    local changed = false
    skin.result = skin.result or M.identity()
    skin.temp = skin.temp or M.identity()
    for i, joint in ipairs(skin.palette) do
        joint = joint + 1
        local node = skin.model.nodes[definition.joints[joint] + 1]
        M.multiply(skin.inverse, node.world, skin.temp)
        local envelope = skin.envelopes[joint] or 0
        local m = skin.temp
        local norm = math.sqrt(
            m[1] ^ 2
                + m[2] ^ 2
                + m[3] ^ 2
                + m[5] ^ 2
                + m[6] ^ 2
                + m[7] ^ 2
                + m[9] ^ 2
                + m[10] ^ 2
                + m[11] ^ 2
        )
        radius = math.max(radius, math.sqrt(m[4] ^ 2 + m[8] ^ 2 + m[12] ^ 2) + envelope * norm)
        M.multiply(skin.temp, definition.inverseBindMatrices[joint], skin.result)
        local matrix = skin.matrices[i] or {}
        skin.matrices[i] = matrix
        for j = 1, 16 do
            if matrix[j] ~= skin.result[j] then
                changed = true
            end
            matrix[j] = skin.result[j]
        end
    end
    object._skinRadius = radius
    if changed then
        object.shadowRevision = (object.shadowRevision or 0) + 1
    end
end

local function matrixChanged(values, matrix)
    if not matrix then
        return true
    end
    local changed = false
    for i = 1, 16 do
        if values[i] ~= matrix[i] then
            values[i] = matrix[i]
            changed = true
        end
    end
    return changed
end

function S.update(object)
    local skin = object.skin
    local cache = skin._paletteInputs
    if not cache then
        cache = { root = {}, entries = {} }
        skin._paletteInputs = cache
    end
    local changed = not cache.valid
        or cache.count ~= #skin.palette
        or cache.radius ~= object._skinRadius
    changed = matrixChanged(cache.root, skin.node.world) or changed
    for i, paletteJoint in ipairs(skin.palette) do
        local joint = paletteJoint + 1
        local node = skin.model.nodes[skin.definition.joints[joint] + 1]
        local entry = cache.entries[i]
        if not entry then
            entry = { world = {}, bind = {}, output = {} }
            cache.entries[i] = entry
            changed = true
        end
        changed = entry.node ~= node
            or entry.joint ~= joint
            or entry.envelope ~= skin.envelopes[joint]
            or changed
        entry.node, entry.joint, entry.envelope = node, joint, skin.envelopes[joint]
        changed = matrixChanged(entry.world, node.world) or changed
        changed = matrixChanged(entry.bind, skin.definition.inverseBindMatrices[joint]) or changed
        changed = matrixChanged(entry.output, skin.matrices[i]) or changed
    end
    if not changed then
        skin.paletteReused = true
        return
    end
    -- Commit the snapshot only after the palette has been rebuilt successfully;
    -- an interrupted update must retry rather than reuse partially written data.
    cache.valid = false
    fullUpdate(object)
    for i = 1, #skin.palette do
        matrixChanged(cache.entries[i].output, skin.matrices[i])
    end
    for i = #cache.entries, #skin.palette + 1, -1 do
        cache.entries[i] = nil
    end
    cache.count, cache.radius, cache.valid = #skin.palette, object._skinRadius, true
    skin.paletteReused = false
end

function S.bind(shader, object)
    if not shader:hasUniform('skinEnabled') then
        return
    end
    local skin = object and object.skin
    shader:send('skinEnabled', skin ~= nil)
    if shader:hasUniform('skinExtended') then
        shader:send('skinExtended', skin ~= nil and object.geometry.eightWeights == true)
    end
    if skin then
        shader:send('skinBones', 'row', unpack(skin.matrices))
    end
end

return S
