local readValue = require('source.engine.math.managedValue').read
local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
-- Opaque instancing keeps individual culling while sharing mesh/texture draw calls.
local Surface = require('source.engine.materials.surface')
local allLights = require('source.engine.graphics.pipeline.lightMasks').all

local effectKeys = { 'lighting', 'shadows', 'fog', 'toneMapping' }
local vectorKeys = { 'atlasGrid', 'textureSize', 'textureOffset', 'tileSize', 'tileOffset' }
local Batches = {}
Batches.__index = Batches
local format = {
    { 'instanceRow1', 'float', 4 },
    { 'instanceRow2', 'float', 4 },
    { 'instanceRow3', 'float', 4 },
    { 'instanceRow4', 'float', 4 },
    { 'instanceNormal1', 'float', 3 },
    { 'instanceNormal2', 'float', 3 },
    { 'instanceNormal3', 'float', 3 },
    { 'instanceLights1', 'float', 2 },
}
local shadowFormat = { format[1], format[2], format[3], format[4] }

local function same(a, b)
    if a.skin or b.skin then
        return a == b
    end
    if
        a._renderOpacity ~= b._renderOpacity
        or a.receiveShadow ~= b.receiveShadow
        or a._resolvedMaterial ~= b._resolvedMaterial
        or a.geometry ~= b.geometry
        or a.image ~= b.image
        or a.unlit ~= b.unlit
        or a.doubleSided ~= b.doubleSided
        or a.alphaCutoff ~= b.alphaCutoff
        or not Surface.compatible(a._surfaceAppearance, b._surfaceAppearance)
    then
        return false
    end
    for _, key in ipairs(effectKeys) do
        local av = a._systemEffects and a._systemEffects[key] ~= false or not a._systemEffects
        local bv = b._systemEffects and b._systemEffects[key] ~= false or not b._systemEffects
        if av ~= bv then
            return false
        end
    end
    if a.imageMode ~= b.imageMode or a.atlasFrame ~= b.atlasFrame then
        return false
    end
    for _, key in ipairs(vectorKeys) do
        local av, bv = readValue(a[key]), readValue(b[key])
        if av and bv then
            for i = 1, #av do
                if av[i] ~= bv[i] then
                    return false
                end
            end
        elseif av ~= bv then
            return false
        end
    end
    local ac, bc = readValue(a.color), readValue(b.color)
    for i = 1, 4 do
        if ac[i] ~= bc[i] then
            return false
        end
    end
    return true
end

function Batches.new(options)
    local shadow = options and options.shadow == true
    return setmetatable({
        groups = {},
        membership = setmetatable({}, { __mode = 'k' }),
        shadow = shadow,
        format = shadow and shadowFormat or format,
        attached = {},
    }, Batches)
end

function Batches:pruneDestroyed()
    for i = #self.groups, 1, -1 do
        local group = self.groups[i]
        if
            group.example.destroyed or (group.lastUsed and self.prepareEpoch - group.lastUsed > 60)
        then
            group.retired = true
            if group.mesh then
                group.mesh:release()
            end
            table.remove(self.groups, i)
        end
    end
end

function Batches:prepare(objects, dependencies, meshes)
    self.prepareEpoch = (self.prepareEpoch or 0) + 1
    self:pruneDestroyed()
    -- Revisions cover resolved appearance and transforms, not just node identity.
    -- Arbitrary custom shaders, animation and external textures retain full comparisons.
    local incremental = dependencies
        and dependencies.meshSnapshots
        and (not dependencies.volatile or dependencies.meshesStable)
        and not dependencies.refreshMeshes
    self.comparisons, self.matrixRows = 0, 0
    self.meshAllocations, self.uploadedRows = 0, 0
    for _, group in ipairs(self.groups) do
        group.count = 0
    end
    for _, o in ipairs(objects) do
        local drawMesh = meshes and meshes[o]
        local previous = self.membership[o]
        local target
        if incremental and previous and not o.skin then
            local group = previous.group
            if
                not group.retired
                and group.drawMesh == drawMesh
                and not group.example.destroyed
                and not group.example._appearancePending
                and previous.revision == o._batchRevision
                and previous.exampleRevision == group.example._batchRevision
            then
                target = group
            end
        end
        if not target then
            for _, group in ipairs(self.groups) do
                self.comparisons = self.comparisons + 1
                if group.drawMesh == drawMesh and same(o, group.example) then
                    target = group
                    break
                end
            end
        end
        if not target then
            target = {
                example = o,
                drawMesh = drawMesh,
                count = 0,
                data = {},
                members = {},
                revisions = {},
                dirty = true,
            }
            self.groups[#self.groups + 1] = target
        end
        target.lastUsed = self.prepareEpoch
        previous = previous or {}
        self.membership[o] = previous
        previous.group, previous.revision = target, o._batchRevision
        previous.exampleRevision = target.example._batchRevision
        target.count = target.count + 1
        local row = target.data[target.count]
        local rowDirty = false
        if not row then
            row = {}
            rowDirty = true
            target.data[target.count] = row
        end
        if
            not incremental
            or target.members[target.count] ~= o
            or target.revisions[target.count] ~= o._batchRevision
        then
            self.matrixRows = self.matrixRows + 1
            local matrix = o.combined or o.matrix
            for i = 1, 16 do
                if row[i] ~= matrix[i] then
                    rowDirty = true
                    row[i] = matrix[i]
                end
            end
            if not self.shadow then
                for i = 1, 9 do
                    if row[16 + i] ~= o.normal[i] then
                        rowDirty = true
                        row[16 + i] = o.normal[i]
                    end
                end
            end
        end
        target.members[target.count] = o
        target.revisions[target.count] = o._batchRevision
        if not self.shadow then
            for i = 1, 2 do
                local value = (o._lightPalette or allLights)[i]
                if row[25 + i] ~= value then
                    rowDirty = true
                    row[25 + i] = value
                end
            end
        end
        if rowDirty then
            target.dirty = true
            target.dirtyFirst = math.min(target.dirtyFirst or target.count, target.count)
            target.dirtyLast = math.max(target.dirtyLast or target.count, target.count)
        end
    end
    for _, group in ipairs(self.groups) do
        for i = #group.members, group.count + 1, -1 do
            group.members[i], group.revisions[i] = nil, nil
        end
    end
end

function Batches:draw(renderer)
    self.drawing = true
    self.attributeAttachments, self.attributeDetachments = 0, 0
    for _, group in ipairs(self.groups) do
        if group.count > 0 then
            if group.count == 1 then
                -- The example can be offscreen after regrouping, so use the current instance
                -- matrix.
                renderer:drawBatch(group, 1)
            else
                renderer:drawBatch(group, group.count)
            end
        end
    end
    self.drawing = false
    for mesh in pairs(self.attached) do
        self:detach(mesh)
        self.attached[mesh] = nil
    end
end

function Batches:upload(group)
    assert(
        not group.example.geometry.eightWeights,
        'Instance rows would overwrite extra skin weights'
    )
    if not group.mesh or group.capacity < #group.data then
        if group.mesh then
            group.mesh:release()
        end
        -- Camera motion can reveal one more instance every frame. Keep bounded
        -- geometric spare capacity instead of reallocating the GPU buffer per row.
        local capacity = math.max(8, group.capacity or 0)
        while capacity < #group.data do
            capacity = capacity * 2
        end
        group.capacity = capacity
        group.mesh = katsa.graphics.newMesh(self.format, capacity, 'points', 'dynamic')
        group.mesh:setVertices(group.data, 1, #group.data)
        group.uploadedRows = #group.data
        self.meshAllocations = (self.meshAllocations or 0) + 1
        self.totalMeshAllocations = (self.totalMeshAllocations or 0) + 1
    elseif group.dirty then
        local first, last = group.dirtyFirst or 1, group.dirtyLast or #group.data
        local rows = group.uploadRows or {}
        group.uploadRows = rows
        local count = last - first + 1
        for i = 1, count do
            rows[i] = group.data[first + i - 1]
        end
        for i = #rows, count + 1, -1 do
            rows[i] = nil
        end
        group.mesh:setVertices(rows, first, count)
        group.uploadedRows = count
    else
        group.uploadedRows = 0
    end
    self.uploadedRows = (self.uploadedRows or 0) + group.uploadedRows
    group.dirty = false
    group.dirtyFirst, group.dirtyLast = nil, nil
    local geometry = group.drawMesh or group.example.geometry.mesh
    for _, attribute in ipairs(self.format) do
        geometry:attachAttribute(attribute[1], group.mesh, 'perinstance')
        self.attributeAttachments = (self.attributeAttachments or 0) + 1
    end
    if self.drawing then
        self.attached[geometry] = true
    end
    return geometry
end

function Batches:detach(mesh)
    -- Overwriting per-instance attributes between batches is sufficient. Remove
    -- them once at the pass boundary before any non-instanced or foreign draw.
    if self.drawing then
        return
    end
    for _, attribute in ipairs(self.format) do
        mesh:detachAttribute(attribute[1])
        self.attributeDetachments = (self.attributeDetachments or 0) + 1
    end
end

function Batches:release()
    self.drawing = false
    for mesh in pairs(self.attached) do
        self:detach(mesh)
    end
    self.attached = {}
    for _, group in ipairs(self.groups) do
        if group.mesh then
            group.mesh:release()
        end
    end
    self.groups = {}
    self.membership = setmetatable({}, { __mode = 'k' })
end

return Batches
