local Array = require('../../math.array')
local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
-- CPU change tracking reuses records. Changed caster/projection revisions bypass
-- the maintenance clock so cached depth matches the current rendered pose.
local bit = require('bit')
local Frusta = require('./shadowFrusta')

local empty = {}
local objectFields = {
    'geometry',
    'image',
    '_effectiveCutoff',
    '_surfaceOpaque',
    'shadowRevision',
    '_surfaceBlendRevision',
    'layers',
    'shadowLayers',
    'shadowGroup',
    '_shaderBoundsPadding',
    '_shaderBoundsUnknown',
    'alphaCutoff',
    '_renderOpacity',
    'doubleSided',
    'parent',
    'shadowBoundsPadding',
    'imageMode',
    'atlasFrame',
}
local vectorFields = { 'atlasGrid', 'tileSize', 'tileOffset', 'textureSize', 'textureOffset' }
local lightFields = { 'range', 'radius', 'shadowLayers', 'shadowGroup', 'shadowRevision' }
local Cache = {}
Cache.__index = Cache

local function capture(target, key, value)
    local old = target[key]
    if not Array.is(value) then
        target[key] = value
        return old ~= value
    end
    if not Array.is(old) then
        old = {}
        target[key] = old
    end
    local changed = false
    for k, v in pairs(value) do
        changed = capture(old, k, v) or changed
    end
    for k in pairs(old) do
        if value[k] == nil then
            old[k] = nil
            changed = true
        end
    end
    return changed
end

local function overlaps(record, light)
    local p = light.worldPosition
    local radius = record.radius + light.range
    return (record.x - p[1]) ^ 2 + (record.y - p[2]) ^ 2 + (record.z - p[3]) ^ 2 <= radius ^ 2
end

function Cache.new()
    return setmetatable({ objects = {}, epoch = 0 }, Cache)
end

function Cache:scan(objects, assignments, layers, dependencies)
    local incremental = dependencies
        and dependencies.meshSnapshots
        and (not dependencies.volatile or dependencies.meshesStable)
        and not dependencies.refreshMeshes
    self.epoch = self.epoch + 1

    local function invalidate(bounds)
        for _, assignment in ipairs(assignments) do
            if
                bit.band(bounds.layers or 1, layers or -1, assignment.light.shadowLayers or -1)
                    ~= 0
                and (
                    bounds.unbounded
                    or assignment.kind == 2 and Frusta.intersects(bounds, assignment.frusta)
                    or assignment.kind ~= 2 and overlaps(bounds, assignment.light)
                )
            then
                assignment.dirty = true
            end
        end
    end
    for _, object in ipairs(objects) do
        local record = self.objects[object]
        if not record then
            record = { values = {} }
            self.objects[object] = record
        end
        record.epoch = self.epoch
        -- Prepared mesh revisions cover transforms, appearance and ancestor edits.
        -- Volatile/custom/skin paths still inspect their complete authored state.
        if
            not (
                incremental
                and record.revision ~= nil
                and record.revision == object._batchRevision
                and not object.skin
                and not object._particleCaster
                and not object._resolvedMaterial
            )
        then
            local active = object:isVisible()
                and object.castShadow ~= false
                and not object.onTop
                and (object._renderOpacity or object:getEffectiveOpacity()) > 0
                and (object.color[4] or 1) > 0
            local material = object._resolvedMaterial
            local changed = capture(record.values, 'matrix', object.combined or object.matrix)
            for _, key in ipairs(vectorFields) do
                changed = capture(record.values, key, object[key] or empty) or changed
            end
            for _, key in ipairs(objectFields) do
                -- Resource and parent identity must not be recursively copied.
                local value = object[key]
                if record.values[key] ~= value then
                    changed = true
                    record.values[key] = value
                end
            end
            if record.values.material ~= material then
                changed = true
                record.values.material = material
            end
            changed = capture(
                record.values,
                'animated',
                material and material.vertexAnimated or false
            ) or changed
            changed = capture(record.values, 'alpha', object.color[4] or 1) or changed
            changed = capture(record.values, 'uniforms', material and material.uniforms or empty)
                or changed
            changed = capture(record.values, 'geometryRevision', object.geometry.revision)
                or changed
            changed = capture(record.values, 'boundsRevision', object.geometry.boundsRevision)
                or changed
            local radius = object.radius
                + (object.shadowBoundsPadding or 0)
                + (object._shaderBoundsPadding or 0)
            local p = object.worldPosition
            changed = changed
                or record.active ~= active
                or record.radius ~= radius
                or (material and material.vertexAnimated)
            if changed and record.active then
                invalidate(record)
            end
            record.active, record.x, record.y, record.z, record.radius =
                active, p[1], p[2], p[3], radius
            -- Arbitrary vertex hooks can move geometry outside its CPU bounds.
            record.unbounded = object._shaderBoundsUnknown == true
            record.layers = object.shadowLayers or object.layers or 1
            if changed and active then
                invalidate(record)
            end
            record.revision = object._batchRevision
        end
    end
    for object, record in pairs(self.objects) do
        if record.epoch ~= self.epoch then
            if record.active then
                invalidate(record)
            end
            self.objects[object] = nil
        end
    end
end

function Cache.lightChanged(record, near)
    local light = record.light
    record.values = record.values or {}
    local changed = light.type ~= 'DirectionalLight3D'
            and capture(record.values, 'position', light.worldPosition)
        or false
    changed = capture(record.values, 'direction', light.worldDirection) or changed
    for _, key in ipairs(lightFields) do
        changed = capture(record.values, key, light[key]) or changed
    end
    return capture(record.values, 'near', near) or changed
end

function Cache.matrixChanged(record, matrix)
    record.values = record.values or {}
    return capture(record.values, 'matrix', matrix)
end
-- Reuse the final image only after every visible shadow dependency is settled.
-- This does not gate dynamic updates or discard hidden blockers.
function Cache.reusable(shadows, renderer, dependencies)
    if
        not shadows.wasEnabled
        or shadows.atlasInvalid
        or (shadows.pendingFaces or 0) > 0
        or shadows.scannedOwner ~= renderer
        or shadows.scannedRevision ~= dependencies.casterRevision
    then
        return false
    end
    for _, record in ipairs(shadows.assignments) do
        if record.dirty then
            return false
        end
        if (shadows.lightFade[record.light.slot] or 1) < 1 then
            return false
        end
        for face, visible in ipairs(record.faceVisible or {}) do
            if visible and record.facesDirty[face] then
                return false
            end
        end
    end
    return true
end

return Cache
