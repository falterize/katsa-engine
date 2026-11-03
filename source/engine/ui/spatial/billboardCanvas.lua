-- Install one cohesive responsibility on the public class.
local ContentBounds = require('./contentBounds')
local BillboardCanvas = {}

function BillboardCanvas.install(BillboardUI)
    function BillboardUI:resolveCanvas(camera)
        self._camera = camera or self._camera
        local w, h = self:resolvedSize(self._camera)
        if self.sizeMode == 'World3D' then
            w, h = w * self.canvasPixelsPerUnit, h * self.canvasPixelsPerUnit
        end
        local cw, ch = require('source.engine.ui.layout.metrics').resolve(self.canvasSize, w, h)
        assert(
            cw > 0 and ch > 0 and cw < math.huge and ch < math.huge,
            'CanvasSize must resolve positive finite dimensions'
        )
        -- Limit logical dimensions as well as density before allocating.
        local limit = math.min(self.maxTextureSize or 2048, self.textureLimit)
        local ratio = math.min(1, limit / cw, limit / ch)
        cw, ch =
            math.max(1, math.floor(cw * ratio + 0.5)), math.max(1, math.floor(ch * ratio + 0.5))
        self.resolvedCanvasSize[1], self.resolvedCanvasSize[2] = cw, ch
    end

    function BillboardUI:resolvedSize(camera)
        local rw, rh = camera and camera.width or 1280, camera and camera.height or 720
        if self.sizeMode == 'World3D' then
            if self:isA('SurfaceUI') then
                rw, rh = require('source.engine.world.surfaces.faces').referenceSize(self)
            else
                rw, rh = self:extentDimensions()
            end
        end
        return require('source.engine.ui.layout.metrics').resolve(
            self.size,
            rw,
            rh,
            self.sizeRelativeTo or self.relativeTo
        )
    end

    function BillboardUI:extentDimensions()
        local support = require('source.engine.world.surfaces.support').resolve(self)
        local d = self.supportSize
        if support and support:isA('Mesh3D') then
            require('source.engine.graphics.geometry.objectBounds').get(support)
            local b = support.geometry.bounds
            return (b[4] - b[1]) * support.size[1],
                (b[5] - b[2]) * support.size[2],
                (b[6] - b[3]) * support.size[3]
        end
        return d[1], d[2], d[3]
    end

    function BillboardUI:refresh()
        local filter = require('source.engine.components.image').pixelate(
            self,
            self._world.environment
        ) and 'nearest' or 'linear'
        self.canvas:setFilter(filter, filter)
        self:resolveCanvas()
        if
            self.ui.width ~= self.resolvedCanvasSize[1]
            or self.ui.height ~= self.resolvedCanvasSize[2]
        then
            self.ui.width, self.ui.height = self.resolvedCanvasSize[1], self.resolvedCanvasSize[2]
            self.dirty = true
        end
        self.ui:layout()
        local revision = self.ui:changed()
        local physicalScale = katsa.graphics.getDPIScale()
        local target = math.max(
            (self.screenWidth or self.size[1]) / self.resolvedCanvasSize[1],
            (self.screenHeight or self.size[2]) / self.resolvedCanvasSize[2]
        ) * physicalScale
        local density =
            math.max(2, math.min(4, 2 ^ math.ceil(math.log(math.max(1, target)) / math.log(2))))
        local limit = math.min(self.maxTextureSize or 2048, self.textureLimit)
        density = math.max(
            0.5,
            math.min(
                density,
                limit / math.max(self.resolvedCanvasSize[1], self.resolvedCanvasSize[2])
            )
        )
        if density ~= self.canvasDensity then
            self.dirty = true
        end
        if self.ui.animated then
            self.dirty = true
        end
        if self.enabled == false and self.uiRevision then
            return
        end
        if not self.dirty and revision == self.uiRevision then
            return
        end
        local bounds = self.bounds
        bounds[1], bounds[2], bounds[3], bounds[4] =
            0, 0, self.resolvedCanvasSize[1], self.resolvedCanvasSize[2]
        if not self:isA('SurfaceUI') then
            ContentBounds.measure(self.ui.children, 0, 0, bounds)
        end
        for i = 1, 2 do
            bounds[i] = math.floor(bounds[i])
        end
        for i = 3, 4 do
            bounds[i] = math.ceil(bounds[i])
        end
        local width, height = bounds[3] - bounds[1], bounds[4] - bounds[2]
        density = math.min(density, limit / math.max(width, height))
        if
            self.canvasAllocationWidth ~= width
            or self.canvasAllocationHeight ~= height
            or density ~= self.canvasDensity
        then
            self.resources:releaseOwned(self.canvas)
            self.canvas =
                self.resources:own(katsa.graphics.newCanvas(width, height, { dpiscale = density }))
        end
        self.canvasDensity = density
        self.canvasAllocationWidth, self.canvasAllocationHeight = width, height
        self.ui:setDensity(density)
        self.canvas:setFilter('linear', 'linear')
        local g = katsa.graphics
        g.push('all')
        g.setCanvas({ self.canvas, stencil = self.ui.hasCorners or false })
        -- A refresh can run inside another UI's draw (a ViewportFrame's world), which leaves its
        -- clip scissor and stencil test active. They would clip the clear and the content, and a
        -- never-written canvas then shows uninitialised GPU memory.
        g.setScissor()
        g.setStencilTest()
        g.setColor(1, 1, 1, 1)
        g.setBlendMode('alpha')
        g.clear(0, 0, 0, 0)
        g.setShader()
        g.setDepthMode()
        g.origin()
        g.translate(-bounds[1], -bounds[2])
        self.ui:draw()
        g.pop()
        self.dirty = false
        self.uiRevision = self.ui.revision
        return true
    end
end

return BillboardCanvas
