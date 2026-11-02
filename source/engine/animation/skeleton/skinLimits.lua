local Array = require('../../math.array')
local SkinGeometry = require('../../import.gltf.skinGeometry')
local Skinning = require('./skinning')
local Policy = require('../../nodes.core.propertyPolicy')

local Limits = {}
local drawKeys = { 'layerGroup', 'shadowGroup', 'layers', 'shadowLayers', 'zIndex' }

local function integer(value, name, maximum)
    if type(value) ~= 'number' or value ~= math.floor(value) or value < 1 or value > maximum then
        error(name .. ' must be an integer within 1..' .. maximum, 3)
    end
    return value
end

local function release(owner, state)
    for _, piece in ipairs(state.pieces) do
        piece:destroy()
    end
    state.pieces = {}
    for _, batch in ipairs(state.batches or {}) do
        local renderer = owner._world._activeRenderer
        local wires = renderer and renderer.wireMeshes
        if wires and wires[batch.geometry] then
            wires[batch.geometry].mesh:release()
            wires[batch.geometry] = nil
        end
        owner._world.resources:releaseOwned(batch.geometry.mesh)
    end
    state.batches = nil
end

local function vertices(state, count)
    local result = {}
    local influences = state.geometry.eightWeights and 8 or 4
    for i, original in Array.ipairs(state.geometry.vertices) do
        local vertex, weights = { Array.unpack(original) }, {}
        for j = 1, influences do
            local offset = j > 4 and 4 or 0
            weights[j] = {
                joint = state.skin.palette[vertex[8 + j + offset] + 1],
                weight = vertex[12 + j + offset],
                index = j,
            }
        end
        table.sort(weights, function(a, b)
            return a.weight > b.weight or a.weight == b.weight and a.index < b.index
        end)
        local total = 0
        for j = 1, math.min(count, influences) do
            total = total + weights[j].weight
        end
        assert(total > 0, 'Skinned vertex must have a positive bone weight')
        for j = 1, influences do
            local offset = j > 4 and 4 or 0
            vertex[8 + j + offset] = weights[j].joint or 0
            vertex[12 + j + offset] = j <= count and weights[j].weight / total or 0
        end
        result[i] = vertex
    end
    return result
end

local function installSkin(object, source, batch)
    object.geometry = batch.geometry
    object.skin = {
        model = source.model,
        definition = source.definition,
        node = source.node,
        palette = batch.palette,
        matrices = {},
    }
    Skinning.initialize(object)
end

local function rebuild(owner, state, influences, palette)
    -- Always rebuild from the immutable imported mesh, never from a previously reduced variant.
    local batches
    if influences < (state.geometry.eightWeights and 8 or 4) or palette < #state.skin.palette then
        batches = SkinGeometry.build(vertices(state, influences), owner._world.resources, palette)
    end
    release(owner, state)
    owner.geometry, owner.skin = state.geometry, state.skin
    if batches then
        state.batches = batches
        installSkin(owner, state.skin, batches[1])
        for i = 2, #batches do
            local piece = owner._world:create('Mesh3D', {
                name = owner.name .. '.Palette' .. i,
                _skinOwner = owner,
                geometry = batches[i].geometry,
            }, owner)
            installSkin(piece, state.skin, batches[i])
            state.pieces[#state.pieces + 1] = piece
        end
    else
        Skinning.update(owner)
    end
    local largest = 0
    for _, batch in ipairs(batches or {}) do
        largest = math.max(largest, #batch.palette)
    end
    owner.effectiveBonePaletteLimit = batches and largest or #state.skin.palette
    owner.skinDrawCount = batches and #batches or 1
    state.influences, state.palette = influences, palette
    owner.shadowRevision = (owner.shadowRevision or 0) + 1
end

function Limits.prepare(world)
    -- Run before frame-cache inspection: split meshes must join every pass in the same frame.
    local owners = world._skinLimitOwners or {}
    world._skinLimitOwners = owners
    local count = 0
    for _, object in ipairs(world.objects) do
        if object.skin and not object._skinOwner then
            count = count + 1
            owners[count] = object
        end
    end
    for i = #owners, count + 1, -1 do
        owners[i] = nil
    end
    for _, owner in ipairs(owners) do
        if not owner.destroyed then
            local influences = integer(owner.maxBoneInfluences, 'MaxBoneInfluences', 8)
            local palette =
                integer(owner.bonePaletteLimit, 'BonePaletteLimit', SkinGeometry.maxPalette)
            local state = owner._skinLimits
            if not state then
                state = {
                    geometry = owner.geometry,
                    skin = owner.skin,
                    pieces = {},
                    influences = 8,
                    palette = SkinGeometry.maxPalette,
                }
                owner._skinLimits = state
                owner.effectiveBonePaletteLimit = #owner.skin.palette
                owner.skinDrawCount = 1
                owner:onDestroy(function()
                    release(owner, state)
                end)
            end
            if state.influences ~= influences or state.palette ~= palette then
                rebuild(owner, state, influences, palette)
            end
            for _, piece in ipairs(state.pieces) do
                -- Generated draws share the owner's material components and local geometry size.
                -- Transform, visibility and opacity already propagate through their parent.
                for _, key in ipairs(Policy.meshKeys) do
                    if key ~= 'geometry' and key ~= 'shadowRevision' then
                        piece[key] = owner[key]
                    end
                end
                for _, key in ipairs(Policy.meshVectors) do
                    piece[key] = owner[key]
                end
                for _, key in ipairs(drawKeys) do
                    piece[key] = owner[key]
                end
                piece.size = owner.size
                Skinning.update(piece)
            end
        end
    end
end

return Limits
