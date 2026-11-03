local readValue = require('../math.managedValue').read
local M = require('../math.math3d')
local Geometry = require('../graphics.geometry.primitives')
local Validate = require('../core.validate')
local Node = require('../nodes')
local Objects = {}

function Objects.install(World3D)
    function World3D:addObject(o)
        assert(
            o.texture == nil and o.image == nil and o.pixelate == nil,
            'Mesh3D image properties were removed; create SurfaceAppearance3D under the mesh'
        )
        assert(
            o.name and not self.byName[o.name],
            'Object name must be unique: ' .. tostring(o.name)
        )
        assert(not o._world or o._world == self, 'Object belongs to another World3D')
        assert(o.material == nil, 'Mesh3D.material was removed; use a Shader3D node')
        o._world = self
        Node.adopt(o, o.className or 'Mesh3D')
        o.parent = o.parent or self.folders.Geometry
        o._world = self
        o.layers = o.layers or 1
        o:onDestroy(function()
            self:removeObject(o.name)
        end)
        assert(
            o.name and not self.byName[o.name],
            'Object name must be unique: ' .. tostring(o.name)
        )
        o.position = o.position or { 0, 0, 0 }
        o.rotation = o.rotation or { 0, 0, 0 }
        o.size = o.size or { 1, 1, 1 }
        Validate.vector(o.position, 'Object.position', 3)
        Validate.vector(o.rotation, 'Object.rotation', 3)
        Validate.vector(o.size, 'Object.size', 3)
        o.doubleSided = o.doubleSided == true
        require('source.engine.components.lighting').normalize(o, 1)
        require('source.engine.components.shadowing').normalize(
            o,
            { castShadow = true, receiveShadow = true }
        )
        o.visible = o.visible ~= false
        o.color = o.color or { 1, 1, 1, 1 }
        o.maxDistance = o.maxDistance or 0
        Validate.number(o.maxDistance, 'Object.maxDistance', 0)
        o.transparency = o.transparency or 0
        local legacyAlpha = o.color[4] or 1
        o.transparency = 1 - (1 - o.transparency) * legacyAlpha
        o.color = { o.color[1], o.color[2], o.color[3] }
        Validate.vector(o.color, 'Object.color', 3)
        Validate.number(o.transparency, 'Object.transparency', 0, 1)
        if not o.geometry and not self.geometry[o.kind or 'cube'] then
            local factory = Geometry[o.kind]
            assert(type(factory) == 'function', 'Unknown geometry: ' .. tostring(o.kind))
            self.geometry[o.kind] = factory()
            self.resources:own(self.geometry[o.kind].mesh)
        end
        o.geometry = o.geometry or assert(self.geometry[o.kind or 'cube'], 'Unknown geometry')
        o.image = self.resources:image('white')
        o.matrix = M.identity()
        o.normal = {}
        o.last = {}
        o.radius = 1
        self.objects[#self.objects + 1] = o
        self.byName[o.name] = o
        self:updateObject(o)
        return o
    end

    function World3D:updateAppearance(o)
        o._batchRevision = (o._batchRevision or 0) + 1
        local surface = require('source.engine.materials.surface').resolve(
            self,
            o,
            o._renderVisible,
            o._renderOpacity
        )
        local image = surface
            and require('source.engine.materials.surface').image(
                self.resources,
                surface,
                'colorMap',
                self.environment
            )
        o.image = image or self.resources:image('white')
        o._surfaceOpaque = surface and surface.alphaMode == 'Opaque' or false
        o._surfaceBlend = surface ~= nil and surface.alphaMode == 'Blend'
        o._effectiveCutoff = surface and surface.alphaMode == 'Mask' and surface.alphaCutoff
            or o.alphaCutoff
    end

    function World3D:updateObject(o, renderPose, geometryOnly)
        o._batchRevision = (o._batchRevision or 0) + 1
        if o.color[4] ~= nil then
            o.color = { o.color[1], o.color[2], o.color[3] }
        end
        o._renderVisible, o._renderOpacity = o:getVisibilityState()
        if not geometryOnly then
            self:updateAppearance(o)
        end
        self:resolveLayerGroup(o)
        local matrix = renderPose and o:getRenderWorldMatrix() or o:getWorldMatrix()
        renderPose = renderPose and o._renderWasInterpolated == true or false
        local revision = renderPose and o._renderRevision or o._transformRevision
        local size = readValue(o.size)
        if
            o._usingRenderPose ~= renderPose
            or revision ~= o._worldRevision
            or o.localMatrix
            or o._skinRevision ~= o.shadowRevision
            or o._geometry ~= o.geometry
            or o._geometryRevision ~= (o.geometry.boundsRevision or o.geometry.revision or 0)
            or o._geometryRadius ~= o.geometry.radius
            or o._localMatrix ~= o.localMatrix
            or o._sizeX ~= size[1]
            or o._sizeY ~= size[2]
            or o._sizeZ ~= size[3]
        then
            for i = 1, 16 do
                o.matrix[i] = matrix[i]
            end
            -- Geometric dimensions affect this mesh, never its descendants.
            for row = 0, 2 do
                for column = 1, 3 do
                    o.matrix[row * 4 + column] = matrix[row * 4 + column] * size[column]
                end
            end
            o._skinRevision = o.shadowRevision
            o._sizeX, o._sizeY, o._sizeZ = size[1], size[2], size[3]
            if o.localMatrix then
                o.combined = M.multiply(o.matrix, o.localMatrix, o.combined)
            else
                o.combined = nil
            end
            local final = o.combined or o.matrix
            M.normalMatrix(final, o.normal)
            o.worldPosition = o.worldPosition or {}
            o.worldPosition[1], o.worldPosition[2], o.worldPosition[3] =
                final[4], final[8], final[12]
            local norm = math.sqrt(
                final[1] ^ 2
                    + final[2] ^ 2
                    + final[3] ^ 2
                    + final[5] ^ 2
                    + final[6] ^ 2
                    + final[7] ^ 2
                    + final[9] ^ 2
                    + final[10] ^ 2
                    + final[11] ^ 2
            )
            o.radius = (o._skinRadius or o.geometry.radius) * norm
            o._worldRevision = revision
            o._usingRenderPose = renderPose
            o._geometry, o._localMatrix = o.geometry, o.localMatrix
            o._geometryRevision = o.geometry.boundsRevision or o.geometry.revision or 0
            o._geometryRadius = o.geometry.radius
        end
    end
end

return Objects
