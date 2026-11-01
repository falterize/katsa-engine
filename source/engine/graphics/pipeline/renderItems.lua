local white = { 1, 1, 1, 1 }
local RenderItems = {}

function RenderItems.install(Renderer)
    function Renderer:drawItem(o)
        if self.world.debug and self.world.debug.wireframe then
            return require('source.engine.graphics.debug.wireframe').draw(self, o)
        end
        local wire = false
        if o:isA('ParticleEmitter3D') then
            local before = self.world.particles.stats.rendered
            self.world.particles:draw(self.camera, o)
            self.stats.mainTriangles = self.stats.mainTriangles
                + (self.world.particles.stats.rendered - before) * 2
            return
        end
        local s, g = self:bindMaterial(o), love.graphics
        if s:hasUniform('debugWireframe') then
            s:send('debugWireframe', wire)
        end
        if s:hasUniform('objectLights1') then
            local palette = o._lightPalette
                or require('source.engine.graphics.pipeline.lightMasks').all
            s:send('objectLights1', palette)
        end
        local billboard = o.canvas ~= nil
        if s:hasUniform('instanced') then
            s:send('instanced', false)
        end
        if s:hasUniform('model') then
            s:send('model', 'row', billboard and o.matrix or o.combined or o.matrix)
        end
        if s:hasUniform('objectNormalMatrix') then
            s:send('objectNormalMatrix', 'row', o.normal)
        end
        if s:hasUniform('receiveShadow') then
            s:send(
                'receiveShadow',
                o.receiveShadow ~= false
                    and not self.shadows.samplingDisabled
                    and (not o._systemEffects or o._systemEffects.shadows)
            )
        end
        if s:hasUniform('unlit') then
            s:send(
                'unlit',
                billboard or o.unlit or o._systemEffects and not o._systemEffects.lighting or false
            )
        end
        if s:hasUniform('canvasTexture') then
            s:send('canvasTexture', billboard)
        end
        require('source.engine.components.image').bindUV(
            s,
            o._surfaceAppearance or o,
            o.textureImage or o.image or o.canvas
        )
        require('source.engine.shaders.systemLayers').bind(s, o)
        self:sendDecal(s, o)
        local c = o.color or white
        local t = self.tint
        t[1], t[2], t[3], t[4] =
            c[1], c[2], c[3], (c[4] or 1) * (o._renderOpacity or o:getEffectiveOpacity())
        if billboard or o:isA('Decal3D') then
            local brightness = o.brightness or 1
            assert(
                brightness >= 0 and brightness < math.huge,
                'Adornment.brightness must be finite and nonnegative'
            )
            for i = 1, 3 do
                t[i] = t[i] * brightness
            end
        end
        if s:hasUniform('tint') then
            s:send('tint', t)
        end
        if s:hasUniform('alphaCutoff') then
            s:send('alphaCutoff', o._effectiveCutoff or o.alphaCutoff or 0)
        end
        require('source.engine.animation.skeleton.skinning').bind(s, o)
        require('source.engine.materials.surface').bind(s, self.world, o)
        local mesh = billboard and self.quad.mesh
            or self.occlusionMeshes and self.occlusionMeshes[o]
            or o.geometry.mesh
        if wire then
            mesh = require('source.engine.graphics.debug.wireframe').mesh(self, o.geometry)
        end
        mesh:setTexture(billboard and o.canvas or o.textureImage or o.image)
        g.setMeshCullMode(o.doubleSided == false and 'back' or 'none')
        g.setColor(1, 1, 1, 1)
        self.stats.mainTriangles = self.stats.mainTriangles
            + require('source.engine.graphics.debug.triangles').mesh(mesh)
        g.draw(mesh)
    end

    function Renderer:sendDecal(shader, node)
        if not shader:hasUniform('decalTexture') then
            return
        end
        local decal = node and node:isA('Decal3D')
        shader:send('decalTexture', decal == true)
        if decal then
            local sx, sy, ox, oy = 1, 1, node.imageOffset[1], node.imageOffset[2]
            local repeatImage = node.mode == 'Texture'
                or node.mode == 'Tiles' and node.fitMode == 'Tile'
            local width, height = node.worldWidth, node.worldHeight
            if node.mode == 'Tiles' then
                width, height = width * node.canvasPixelsPerUnit, height * node.canvasPixelsPerUnit
            end
            local iw, ih = node.textureImage:getDimensions()
            ox, oy, sx, sy =
                require('source.engine.components.image').uv(node, iw, ih, width, height)
            if node.mode == 'Decal' then
                ox, oy = node.imageOffset[1], node.imageOffset[2]
            end
            shader:send('decalRepeat', repeatImage)
            shader:send('decalUVScale', { sx, sy })
            shader:send('decalUVOffset', { ox, oy })
            shader:send('decalUVRotation', math.rad(node.imageRotation))
        end
    end

    function Renderer:drawBatch(group, count)
        local o, g = group.example, love.graphics
        if o.geometry.eightWeights then
            assert(count == 1, 'Extended skins require individual draws')
            return self:drawItem(group.members[1])
        end
        local s = self:bindMaterial(o)
        if s:hasUniform('debugWireframe') then
            s:send('debugWireframe', false)
        end
        require('source.engine.components.image').bindUV(s, o._surfaceAppearance or o, o.image)
        require('source.engine.shaders.systemLayers').bind(s, o)
        self:sendDecal(s)
        require('source.engine.animation.skeleton.skinning').bind(s, o)
        require('source.engine.materials.surface').bind(s, self.world, o)
        local mesh = self.batches:upload(group)
        if s:hasUniform('instanced') then
            s:send('instanced', true)
        end
        if s:hasUniform('receiveShadow') then
            s:send(
                'receiveShadow',
                o.receiveShadow ~= false
                    and not self.shadows.samplingDisabled
                    and (not o._systemEffects or o._systemEffects.shadows)
            )
        end
        if s:hasUniform('unlit') then
            s:send('unlit', o.unlit or o._systemEffects and not o._systemEffects.lighting or false)
        end
        if s:hasUniform('canvasTexture') then
            s:send('canvasTexture', false)
        end
        if s:hasUniform('tint') then
            local c = o.color
            self.tint[1], self.tint[2], self.tint[3], self.tint[4] =
                c[1], c[2], c[3], (c[4] or 1) * (o._renderOpacity or 1)
            s:send('tint', self.tint)
        end
        if s:hasUniform('alphaCutoff') then
            s:send('alphaCutoff', o._effectiveCutoff or o.alphaCutoff or 0)
        end
        g.setMeshCullMode(o.doubleSided == false and 'back' or 'none')
        g.setColor(1, 1, 1, 1)
        mesh:setTexture(o.image)
        self.stats.mainTriangles = self.stats.mainTriangles
            + require('source.engine.graphics.debug.triangles').mesh(mesh) * count
        g.drawInstanced(mesh, count)
        self.batches:detach(mesh)
    end
end

return RenderItems
