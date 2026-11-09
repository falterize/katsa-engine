local M = require('../../math.math3d')

local function rotate(v, c, t, out)
    out[1], out[2], out[3] = v[1] * c + v[3] * t, v[2], v[3] * c - v[1] * t
    return out
end
local RenderBindings = {}

function RenderBindings.install(Renderer)
    function Renderer:drawSky(world, camera)
        local s = world.lighting.sky
        if not s.enabled then
            return
        end
        local g = katsa.graphics
        local image = require('source.engine.components.image').resolve(
            world.resources,
            s,
            s.texture,
            world.environment
        )
        assert(
            s.layout == 'Cross' or s.layout == 'Panorama',
            'Sky Layout must be Cross or Panorama'
        )
        assert(
            s.layout ~= 'Cross'
                or world.resources:isMissingImage(s.texture)
                or image:getWidth() * 3 == image:getHeight() * 4,
            'Cross sky must have 4:3 aspect ratio'
        )
        -- The sky shader builds texture coordinates per cube face (or from atan), so they jump at
        -- face edges, the panorama seam and the poles. Mipmapping would read those jumps as
        -- minification and sample the smallest level there: a line of the wrong colour. The sky
        -- is sampled without mipmaps.
        if self._skyUnmipped ~= image then
            image:setMipmapFilter()
            self._skyUnmipped = image
        end
        local shader = self.sky
        g.setShader(shader)
        local yaw = math.rad(s.yaw)
        local c, t = math.cos(yaw), math.sin(yaw)
        shader:send('right', rotate(camera.right, c, t, self.skyRight))
        shader:send('up', rotate(camera.up, c, t, self.skyUp))
        shader:send('forward', rotate(camera.forward, c, t, self.skyForward))
        self.skySize[1], self.skySize[2] = self.width, self.height
        shader:send('viewSize', self.skySize)
        -- The sky is infinitely far, so orthographic cameras still show it with their fov lens.
        shader:send('focal', camera.focal)
        shader:send('panorama', s.layout == 'Panorama' or world.resources:isMissingImage(s.texture))
        self.skyInset[1] = (s.layout == 'Panorama' and 0.5 or 2) / image:getWidth()
        self.skyInset[2] = (s.layout == 'Panorama' and 0.5 or 1.5) / image:getHeight()
        shader:send('edgeInset', self.skyInset)
        for i = 1, 3 do
            self.skyTint[i] = s.color[i] / 255
        end
        self.skyTint[4] = s.brightness
        shader:send('tint', self.skyTint)
        g.setColor(1, 1, 1, 1)
        g.draw(image, 0, 0, 0, self.width / image:getWidth(), self.height / image:getHeight())
        g.setShader()
    end

    function Renderer:sendFrame(s)
        if s:hasUniform('objectLightMaskEnabled') then
            s:send('objectLightMaskEnabled', self.lightLoop == 'Masked')
        end
        if s:hasUniform('viewProjection') then
            s:send('viewProjection', 'row', self.camera.viewProjection)
        end
        if s == rawget(self, 'wireShader') then
            s:send('viewportSize', { self.width * self.density, self.height * self.density })
            return
        end
        local l, f = self.world.lighting, self.world.lighting.fog
        for i = 1, 3 do
            self.ambient[i] = l.ambient[i] / 255
            self.fogColor[i] = f.color[i] / 255
        end
        -- Volumetric fog replaces the per-pixel distance fog (post/passes/volumetricFog.lua).
        self.fogColor[4] = (f.enabled and not f.volumetric) and f.maxOpacity or 0
        self.fogSettings[1], self.fogSettings[2], self.fogSettings[3], self.fogSettings[4] =
            f.density, f.offset, f.endDistance, f.mode == 'Linear' and 1 or 0
        if s:hasUniform('ambient') then
            s:send('ambient', self.ambient)
        end
        if s:hasUniform('toneMapping') then
            s:send('toneMapping', l.toneMapping == true)
        end
        if s:hasUniform('exposure') then
            s:send('exposure', l.exposure or 1)
        end
        if s:hasUniform('brightness') then
            s:send('brightness', l.brightness)
        end
        if s:hasUniform('cameraPosition') then
            s:send('cameraPosition', self.camera.worldPosition or self.camera.position)
        end
        if s:hasUniform('fogColor') then
            s:send('fogColor', self.fogColor)
        end
        if s:hasUniform('fogSettings') then
            s:send('fogSettings', self.fogSettings)
        end
        if s:hasUniform('time') then
            s:send('time', self.time)
        end
        if not (self.world.debug and self.world.debug.wireframe) then
            self.lights:send(s)
            self.shadows:send(s, l)
        end
    end

    function Renderer:bindMaterial(object)
        local wire = self.world.debug and self.world.debug.wireframe
        local material = not wire and object and object._resolvedMaterial
        assert(not material or material.kind == 'world', '3D objects require a world material')
        local shader = wire and self.wireShader
            or material and material.shader
            or require('source.engine.graphics.pipeline.shaderVariants').get(self, object)
        katsa.graphics.setShader(shader)
        if self.shaderFrames[shader] ~= self.frame then
            self:sendFrame(shader)
            self.shaderFrames[shader] = self.frame
        end
        if shader:hasUniform('depthPrepassEnabled') then
            shader:send(
                'depthPrepassEnabled',
                self.depthPrepassActive
                        and not material
                        and not (object and (not object:isA('Mesh3D') or object.blend or object._surfaceBlend or object.onTop or (object._renderOpacity or 1) < 1))
                    or false
            )
            if self.depthPrepassActive and shader:hasUniform('depthPrepassTexture') then
                shader:send('depthPrepassTexture', self.prepassDepth)
                local width, height = self.canvas:getPixelDimensions()
                self.prepassSize = self.prepassSize or {}
                self.prepassSize[1], self.prepassSize[2] = width, height
                shader:send('depthPrepassSize', self.prepassSize)
            end
        end
        if material then
            material:bind(self.time)
        end
        return shader
    end
end

return RenderBindings
