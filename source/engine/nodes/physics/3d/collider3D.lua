local Snapshot = require('source.engine.core.valueSnapshot')

local scalarFields = { 'shape', 'enabled', 'radius', 'height' }
local vectorFields = { 'size', 'position', 'rotation' }
local readValue = require('source.engine.math.managedValue').read
local unpack = require('source.engine.math.array').unpack
local Node = require('../../core.baseNode')
local Level = require('source.engine.physics.3d.collisionLevel')
local Decomposition = require('source.engine.physics.3d.decomposition')

local Class = Node.define('Collider3D', 'Node')
Class.propertySchema = {
    points = { visibleWhen = { key = 'shape', equals = 'Points' } },
    indices = { visibleWhen = { key = 'shape', equals = 'Points' } },
    status = { readOnly = true },
    shape = { options = { 'Box', 'Sphere', 'Capsule', 'Cylinder', 'Cone', 'Geometry', 'Points' } },
    geometrySource = {
        kind = 'node',
        hint = 'Select a Node3D / Mesh3D or enter an OBJ, GLB or glTF model path. File sources '
            .. 'use Size as local scale.',
        visibleWhen = { key = 'shape', equals = 'Geometry' },
    },
    collisionLevel = {
        options = Level.names,
        hint = 'Trimesh: exact triangles (static bodies). Single Convex: one hull per mesh. '
            .. 'Simplified Convex: one hull per mesh with few vertices. Multiple Convex: several '
            .. 'hulls that follow a concave model (cars, rooms, arches). Bounding Box: one box.',
        visibleWhen = { key = 'shape', oneOf = { 'Geometry', 'Points' } },
    },
    maxTriangles = {
        min = 1,
        max = 100000,
        visibleWhen = { key = 'shape', oneOf = { 'Geometry', 'Points' } },
    },
    hullPoints = {
        min = 4,
        max = 128,
        hint = 'Most vertices of each convex hull.',
        visibleWhen = {
            { key = 'shape', oneOf = { 'Geometry', 'Points' } },
            { key = 'collisionLevel', oneOf = { 'Simplified Convex', 'Multiple Convex' } },
        },
    },
    maxHulls = {
        min = 1,
        max = 64,
        hint = 'Most convex pieces the model is cut into.',
        visibleWhen = {
            { key = 'shape', oneOf = { 'Geometry', 'Points' } },
            { key = 'collisionLevel', oneOf = { 'Multiple Convex' } },
        },
    },
    concavity = {
        min = 0,
        max = 1,
        hint = 'How much of the model volume a piece may leave empty inside its hull before it is '
            .. 'cut again (0.02 = 2%). Lower values fit tighter and make more pieces.',
        visibleWhen = {
            { key = 'shape', oneOf = { 'Geometry', 'Points' } },
            { key = 'collisionLevel', oneOf = { 'Multiple Convex' } },
        },
    },
    resolution = {
        min = 8,
        max = 96,
        hint = 'Voxels along the longest side used to find concave regions. Higher is slower.',
        visibleWhen = {
            { key = 'shape', oneOf = { 'Geometry', 'Points' } },
            { key = 'collisionLevel', oneOf = { 'Multiple Convex' } },
        },
    },
}

function Class.initialize(self)
    self.shape = self.shape or 'Box'
    self.size = self.size or { 1, 1, 1 }
    self.radius = self.radius or 0.5
    self.height = self.height or 1
    self.position = self.position or { 0, 0, 0 }
    self.rotation = self.rotation or { 0, 0, 0 }
    self.enabled = self.enabled ~= false
    self.collisionLevel = self.collisionLevel or 'Bounding Box'
    self.maxTriangles = self.maxTriangles or 4096
    local defaults = Decomposition.defaults
    self.hullPoints = self.hullPoints or defaults.hullPoints
    self.maxHulls = self.maxHulls or defaults.maxHulls
    self.concavity = self.concavity or defaults.concavity
    self.resolution = self.resolution or defaults.resolution
    self.status = 'Ready'
end

function Class.mount(world, properties, parent)
    assert(parent and parent:isA('Body3D'), 'Collider3D requires a Body3D parent')
    local node = Node.new('Collider3D', properties, parent)
    node:onDestroy(function()
        if not parent.destroyed and not parent._destroying then
            parent._collidersDirty = true
        end
    end)
    parent._collidersDirty = true
    return node
end

function Class:update(dt) end

-- The settings that change the hulls a Simplified / Multiple Convex level builds.
function Class:decompositionKey()
    return table.concat({ self.hullPoints, self.maxHulls, self.concavity, self.resolution }, ',')
end

function Class:descriptor(body)
    if self.shape ~= 'Geometry' and self._geometrySourceCache then
        self._geometryStates, self._geometryOrder, self._geometrySourceCache = nil, nil, nil
    end
    self._primitiveSnapshot = self._primitiveSnapshot or {}
    local changed = Snapshot.fields(self._primitiveSnapshot, self, scalarFields, vectorFields)
    if not changed and self.shape ~= 'Geometry' and self.shape ~= 'Points' and self._descriptor then
        self.status = 'Ready'
        return self._descriptor, self._descriptorKey
    end
    local signature = self.shape
        .. tostring(self.enabled)
        .. table.concat(readValue(self.size), ':')
        .. table.concat(readValue(self.position), ':')
        .. table.concat(readValue(self.rotation), ':')
        .. self.radius
        .. ':'
        .. self.height
    if self.shape == 'Points' then
        local builder = require('source.engine.physics.3d.pointCollider')
        signature = signature
            .. ':'
            .. builder.changed(self)
            .. ':'
            .. self.collisionLevel
            .. ':'
            .. self.maxTriangles
            .. ':'
            .. self:decompositionKey()
            .. ':'
            .. body.bodyType
        if signature ~= self._descriptorKey then
            local success, descriptor = pcall(builder.build, self, body)
            if not success then
                self.status = tostring(descriptor)
                return self._descriptor, self._descriptorKey or signature .. ':invalid'
            end
            self._descriptor = descriptor
        end
    elseif self.shape == 'Geometry' then
        if Level.isTrimesh(self.collisionLevel) and body.bodyType ~= 'Static' then
            self.status = 'Trimesh requires a Static Body3D'
            return nil, signature .. ':nonstatic'
        end
        local builder = require('source.engine.physics.3d.modelCollider')
        if
            not self.geometrySource
            or self.geometrySource == ''
            or type(self.geometrySource) ~= 'string' and self.geometrySource.destroyed
        then
            self._geometryStates, self._geometryOrder, self._geometrySourceCache = nil, nil, nil
            self.status = 'Waiting for GeometrySource'
            return nil, signature .. ':missing'
        end
        local ok, parts, key = pcall(builder.collect, self, body)
        if not ok then
            self.status = tostring(parts)
            return self._descriptor, self._descriptorKey or signature .. ':invalid'
        end
        signature = signature .. key .. self.collisionLevel .. self.maxTriangles .. self:decompositionKey()
        if signature ~= self._descriptorKey then
            local success, descriptor = pcall(builder.build, self, body, parts)
            if not success then
                self.status = tostring(descriptor)
                return self._descriptor, self._descriptorKey or signature .. ':invalid'
            end
            self._descriptor = descriptor
        end
    else
        self._descriptor = {
            shape = self.shape,
            size = { unpack(self.size) },
            radius = self.radius,
            height = self.height,
            position = { unpack(self.position) },
            rotation = { unpack(self.rotation) },
        }
    end
    self._descriptorKey = signature
    self.status = 'Ready'
    return self._descriptor, signature
end

function Class:getPointsFromMesh(source, options)
    source, options = source or self.geometrySource, options or {}
    return require('source.engine.physics.3d.pointCollider').extract(source, self.parent, {
        scale = options.scale or (type(source) == 'string' and self.size or nil),
        weldEpsilon = options.weldEpsilon,
        maxTriangles = options.maxTriangles or self.maxTriangles,
    })
end

function Class:setPoints(points, indices)
    local builder = require('source.engine.physics.3d.pointCollider')
    self.points = builder.copy(points)
    self.indices = nil
    if indices then
        self.indices = {}
        for i = 1, #indices do
            self.indices[i] = indices[i]
        end
    end
    self.shape = 'Points'
    return self
end

function Class:setPointsFromMesh(source, options)
    local points, indices = self:getPointsFromMesh(source, options)
    return self:setPoints(points, indices)
end

-- Explicit file names complement the existing mesh API; both accept either source type.
Class.getPointsFromModel = Class.getPointsFromMesh
Class.setPointsFromModel = Class.setPointsFromMesh

return Class
