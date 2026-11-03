local ipairs = require('../../math.array').ipairs
local Batches = require('../pipeline.batches')
local Types = require('./sourceTypes')
local kind, faces, pointDirections = Types.kind, Types.faces, Types.pointDirections
local ShadowDepthPass = {}

function ShadowDepthPass.install(Shadows)
    function Shadows:buildFrustum(matrix)
        for axis = 1, 3 do
            for side = 0, 1 do
                local index = (axis - 1) * 2 + side + 1
                local plane = self.planes[index] or {}
                self.planes[index] = plane
                local row, sign = (axis - 1) * 4, side == 0 and 1 or -1
                for i = 1, 4 do
                    plane[i] = matrix[12 + i] + sign * matrix[row + i]
                end
                plane[5] = math.sqrt(plane[1] ^ 2 + plane[2] ^ 2 + plane[3] ^ 2)
            end
        end
    end

    function Shadows:visible(object)
        if object._shaderBoundsUnknown then
            return true
        end
        local p, radius =
            object.worldPosition,
            object.radius + (object.shadowBoundsPadding or 0) + (object._shaderBoundsPadding or 0)
        for _, plane in ipairs(self.planes) do
            if
                plane[1] * p[1] + plane[2] * p[2] + plane[3] * p[3] + plane[4]
                < -radius * plane[5]
            then
                return false
            end
        end
        return true
    end

    function Shadows:bind(object)
        local opaque = require('source.engine.graphics.materials.opaqueMesh').eligible(
            object,
            object._world and object._world._activeRenderer
        )
        if opaque and not self.opaqueShader then
            local source = katsa.filesystem.read('assets/shaders/engine/shadow.glsl')
            source = source:gsub(
                '#ifdef PIXEL.-#endif',
                '#ifdef PIXEL\nvec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) { '
                    .. 'return vec4(1.0); }\n#endif'
            )
            self.opaqueShader = self.resources:own(katsa.graphics.newShader(source))
        end
        local shader = object._resolvedMaterial and object._resolvedMaterial.shadowShader
            or opaque and self.opaqueShader
            or self.shader
        assert(shader, 'A world material must provide a shadow vertex shader')
        katsa.graphics.setShader(shader)
        require('source.engine.animation.skeleton.skinning').bind(shader, object)
        shader:send('viewProjection', 'row', self.currentMatrix)
        shader:send('atlasTile', self.tile)
        if not opaque then
            shader:send(
                'surfaceOpaque',
                object._surfaceAppearance and object._surfaceAppearance.alphaMode == 'Opaque'
                    or false
            )
            shader:send('alphaCutoff', object._effectiveCutoff or object.alphaCutoff or 0)
            require('source.engine.components.image').bindUV(
                shader,
                object._surfaceAppearance or object,
                object.image
            )
            if shader:hasUniform('particleCaster') then
                shader:send('particleCaster', object._particleCaster == true)
            end
            shader:send(
                'opacity',
                (object._renderOpacity or object:getEffectiveOpacity()) * (object.color[4] or 1)
            )
        end
        if object._resolvedMaterial then
            object._resolvedMaterial:bindShadow(self.currentTime)
        end
        katsa.graphics.setMeshCullMode(object.doubleSided and 'none' or 'back')
        return shader
    end

    function Shadows:drawBatch(group, count)
        local object, g = group.example, katsa.graphics
        local shader = self:bind(object)
        local mesh
        if object.geometry.eightWeights then
            assert(count == 1, 'Extended skins require individual shadow draws')
            shader:send('instanced', false)
            shader:send('model', 'row', object.combined or object.matrix)
            mesh = object.geometry.mesh
        else
            shader:send('instanced', true)
            mesh = self.batches:upload(group)
        end
        self.batchUploadedRows = self.batchUploadedRows + (group.uploadedRows or 0)
        mesh:setTexture(object.image)
        self.triangles = self.triangles
            + require('source.engine.graphics.debug.triangles').mesh(mesh) * count
        if object.geometry.eightWeights then
            g.draw(mesh)
        else
            g.drawInstanced(mesh, count)
            self.batches:detach(mesh)
        end
        self.drawCalls = self.drawCalls + 1
    end

    function Shadows:drawFace(world, matrix, tileIndex, time)
        local g = katsa.graphics
        if not self.depthPassStarted then
            g.push('all')
            g.origin()
            g.setCanvas({ depthstencil = self.depth })
            g.setDepthMode('less', true)
            g.setFrontFaceWinding('cw')
            g.setColor(1, 1, 1, 1)
            self.depthPassStarted = true
        end
        local col, row = tileIndex % self.columns, math.floor(tileIndex / self.columns)
        self.tile[1], self.tile[2], self.tile[3], self.tile[4] =
            1 / self.columns,
            1 / self.rows,
            -1 + (2 * col + 1) / self.columns,
            -1 + (2 * row + 1) / self.rows
        self.currentMatrix, self.currentTime = matrix, time
        g.setScissor(col * self.resolution, row * self.resolution, self.resolution, self.resolution)
        g.clear(false, false, 1)
        self.updatedFaces = self.updatedFaces + 1
        self:buildFrustum(matrix)
        for i = #self.casters, 1, -1 do
            self.casters[i] = nil
        end
        for _, object in ipairs(self.sourceCasters or world._shadowObjects or world.objects) do
            self.casterTests = self.casterTests + 1
            if self:visible(object) then
                self.casters[#self.casters + 1] = object
            end
        end
        self.casterSubmissions = self.casterSubmissions + #self.casters
        -- Each tile owns its retained membership/instance rows. A different face
        -- must not overwrite this face's buffer or its row revision history.
        local batches = self.faceBatches[tileIndex]
        if batches and self.faceOwners[tileIndex] ~= self.currentLight then
            batches:release()
            batches = nil
        end
        self.faceOwners[tileIndex] = self.currentLight
        if not batches then
            batches = Batches.new({ shadow = true })
            self.faceBatches[tileIndex] = batches
        end
        self.batches = batches
        batches:prepare(self.casters, self.dependencies)
        self.batchComparisons = self.batchComparisons + batches.comparisons
        self.batchMatrixRows = self.batchMatrixRows + batches.matrixRows
        batches:draw(self)
    end
end

return ShadowDepthPass
