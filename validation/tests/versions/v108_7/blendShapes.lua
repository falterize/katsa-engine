-- Blend shapes (Blender Shape Keys) from a synthetic GLB: a sparse target, a dense target, shape
-- names, per-instance geometry, Godot-style access and a glTF `weights` animation.
local ffi = require('ffi')
local GLB = require('source.engine.import.glb')
local Models = require('source.engine.import.models')

local Module = {}

local function document(skinned)
    local buffer = ffi.new('uint8_t[172]')
    local floats = ffi.cast('float*', buffer)
    local base = { 0, 0, 0, 1, 0, 0, 0, 1, 0 }
    for i, v in ipairs(base) do
        floats[i - 1] = v
    end
    -- dense target "Wide": the first vertex moves by -1 along x
    floats[9] = -1
    ffi.cast('uint16_t*', buffer + 72)[0] = 1 -- sparse index
    ffi.cast('float*', buffer + 76)[1] = 2 -- sparse value: vertex 2 moves +2 along y
    ffi.cast('float*', buffer + 88)[0], ffi.cast('float*', buffer + 88)[1] = 0, 1
    local weights = ffi.cast('float*', buffer + 96)
    weights[0], weights[1], weights[2], weights[3] = 0, 0, 1, 0.5
    local doc = {
        asset = { version = '2.0' },
        buffers = { { byteLength = 112 } },
        bufferViews = {
            { buffer = 0, byteOffset = 0, byteLength = 36 },
            { buffer = 0, byteOffset = 36, byteLength = 36 },
            { buffer = 0, byteOffset = 72, byteLength = 2 },
            { buffer = 0, byteOffset = 76, byteLength = 12 },
            { buffer = 0, byteOffset = 88, byteLength = 8 },
            { buffer = 0, byteOffset = 96, byteLength = 16 },
        },
        accessors = {
            { bufferView = 0, componentType = 5126, count = 3, type = 'VEC3' },
            { bufferView = 1, componentType = 5126, count = 3, type = 'VEC3' },
            {
                componentType = 5126,
                count = 3,
                type = 'VEC3',
                sparse = {
                    count = 1,
                    indices = { bufferView = 2, componentType = 5123 },
                    values = { bufferView = 3 },
                },
            },
            { bufferView = 4, componentType = 5126, count = 2, type = 'SCALAR' },
            { bufferView = 5, componentType = 5126, count = 4, type = 'SCALAR' },
        },
        meshes = {
            {
                primitives = {
                    {
                        attributes = { POSITION = 0 },
                        targets = { { POSITION = 2 }, { POSITION = 1 } },
                    },
                },
                extras = { targetNames = { 'Smile', 'Wide' } },
            },
        },
        nodes = { { name = 'Face', mesh = 0 } },
        scenes = { { nodes = { 0 } } },
        animations = {
            {
                name = 'Talk',
                samplers = { { input = 3, output = 4 } },
                channels = { { sampler = 0, target = { node = 0, path = 'weights' } } },
            },
        },
    }
    if skinned then
        -- Three vertices on two joints, then the skin itself.
        local joints, weights = ffi.cast('uint8_t*', buffer + 112), ffi.cast('float*', buffer + 124)
        for v = 0, 2 do
            joints[v * 4], joints[v * 4 + 1] = 0, 1
            weights[v * 4], weights[v * 4 + 1] = 0.5, 0.5
        end
        doc.buffers[1].byteLength = 172
        doc.bufferViews[7] = { buffer = 0, byteOffset = 112, byteLength = 12 }
        doc.bufferViews[8] = { buffer = 0, byteOffset = 124, byteLength = 48 }
        doc.accessors[6] = { bufferView = 6, componentType = 5121, count = 3, type = 'VEC4' }
        doc.accessors[7] = { bufferView = 7, componentType = 5126, count = 3, type = 'VEC4' }
        local primitive = doc.meshes[1].primitives[1]
        primitive.attributes.JOINTS_0, primitive.attributes.WEIGHTS_0 = 5, 6
        doc.nodes = { { name = 'Face', mesh = 0, skin = 0 }, { name = 'J1' }, { name = 'J2' } }
        doc.scenes = { { nodes = { 0, 1, 2 } } }
        doc.skins = { { joints = { 1, 2 } } }
    end
    return doc, ffi.string(buffer, skinned and 172 or 112)
end

local function vertex(object, index)
    return object.geometry.vertices[index]
end

function Module.run(self)
    local resources = self.manager.resources:scope()
    local world = require('source.engine.world.world').new(resources)
    local doc, binary = document()
    local model = GLB.decode(doc, binary, 'synthetic.glb', resources)
    local objects = Models.instantiate(world, model, { name = 'Face' })
    local face = objects[1]
    self:check(
        face:getBlendShapeCount() == 2
            and face:findBlendShapeByName('Wide') == 2
            and face:getBlendShapeName(1) == 'Smile'
            and face:findBlendShapeByName('Frown') == nil,
        'Shape key names reach the mesh with Godot-style lookup'
    )
    local list = face:getBlendShapes()
    self:check(#list == 2 and list[1] == 'Smile' and list[2] == 'Wide', 'getBlendShapes lists index to name')
    local markers = GLB.markers({
        fps = 30,
        markers = '[{"name":"A","time":0.5},{"name":"B","keyframe":15,"value":"x"}]',
    })
    self:check(
        markers[1].time == 0.5 and markers[2].time == 0.5 and markers[2].value == 'x',
        'Markers accept seconds or keyframe numbers from a JSON string'
    )
    face:setBlendShapeValue('Smile', 0.5)
    face:setBlendShapeValue(2, 1)
    world:updateNodes(0)
    self:check(
        math.abs(vertex(face, 2)[2] - 1) < 1e-6 and math.abs(vertex(face, 1)[1] + 1) < 1e-6,
        'Sparse and dense shape keys displace the vertices by weight'
    )
    self:check(
        model.parts[1].geometry.vertices[2][2] == 0 and model.parts[1].geometry ~= face.geometry,
        'The imported asset keeps its base shape; the mesh owns a dynamic copy'
    )
    face:setBlendShapeValue('Smile', 0)
    face:setBlendShapeValue('Wide', 0)
    world:updateNodes(0)
    self:check(
        vertex(face, 2)[2] == 0 and vertex(face, 1)[1] == 0 and face:getBlendShapeValue('Smile') == 0,
        'Zero weights restore the base shape'
    )
    self:check(
        not pcall(face.setBlendShapeValue, face, 'Frown', 1),
        'An unknown shape is an error, not a silent no-op'
    )
    local rows = require('source.engine.editor.inspectors.properties').list(face)
    local row
    for _, item in ipairs(rows) do
        if item.key == 'blend: Wide' then
            row = item
        end
    end
    self:check(row and row.kind == 'number' and row.container ~= nil, 'The inspector lists a row per blend shape')
    row.container[row.storageKey] = 0.75
    self:check(face:getBlendShapeValue('Wide') == 0.75, 'Editing the row sets the blend shape')
    face:setBlendShapeValue('Wide', 0)
    local track = model.controller:load('Talk', { looped = false })
    track:play()
    model.controller:update(0.5)
    self:check(
        math.abs(face:getBlendShapeValue('Wide') - 0.25) < 1e-3,
        'A glTF weights channel animates the shapes'
    )

    -- Skin limits split a skinned mesh into palette batches; the new draws keep following.
    local skinnedWorld = require('source.engine.world.world').new(self.manager.resources:scope())
    local doc2, binary2 = document(true)
    local model2 = GLB.decode(doc2, binary2, 'skinned.glb', resources)
    local mesh = Models.instantiate(skinnedWorld, model2, { name = 'Skinned' })[1]
    mesh:setBlendShapeValue('Smile', 1)
    skinnedWorld:updateNodes(0)
    mesh.maxBoneInfluences = 1
    require('source.engine.animation.skeleton.skinLimits').prepare(skinnedWorld)
    mesh:setBlendShapeValue('Wide', 1)
    skinnedWorld:updateNodes(0)
    self:check(
        math.abs(mesh.geometry.vertices[2][2] - 2) < 1e-6 and mesh.geometry.vertices[1][1] == -1,
        'After skin limits split the mesh, blend shapes still drive its draws'
    )
end

return Module
